import CoreGraphics
import Foundation
import QuartzCore

/// Which target the iris is driven towards.
enum GazeMethod: String, CaseIterable, Identifiable {
    /// Faithful port of the reference: move the iris toward the eye centroid, with the
    /// vertical component damped. Subtle by design.
    case irisOffset
    /// "Look at the camera": target = eye centroid + the 3D-geometry offset that
    /// accounts for the camera sitting above the screen. The correction is the full
    /// distance from the *current* iris position to that target, so a sideways glance
    /// is pulled all the way back. This is the product behaviour.
    case geometry3D

    var id: String { rawValue }

    var label: String {
        switch self {
        case .irisOffset: "İris"
        case .geometry3D: "Geometri"
        }
    }
}

/// A ready-to-apply warp for one eye, in CIImage pixel space.
struct EyeWarp {
    /// Rigid displacement applied to the whole eye interior, pixels.
    let shift: CGPoint
    /// Region the patch and its mask live in.
    let roi: CGRect
    /// Eye contour in image pixels. The blend mask is built from this, so nothing
    /// outside the eyelids can move — the reference project's key guarantee.
    let contour: [CGPoint]
    /// Feather radius for the blend mask, pixels.
    let feather: CGFloat
    /// How far the mask is grown beyond the contour hull, pixels. Keeps full mask
    /// weight over the iris even when it sits at an eye corner.
    let maskDilate: CGFloat
    /// Current iris position — for the debug arrow.
    let irisFrom: CGPoint
    /// Iris position after the shift — for the debug arrow.
    let irisTo: CGPoint
}

/// Everything the renderer and the HUD need for one frame.
struct CorrectionPlan {
    let left: EyeWarp?
    let right: EyeWarp?
    /// Behaviour blend ∈ [0, 1] — already folded into the displacements.
    let blend: Double
    let state: BehaviorState
    let gazeInfo: GazeInfo
    let geometry: GazeGeometryResult?
    /// Post-clamp displacement actually applied to the left eye, for the HUD.
    let appliedShift: CGPoint
    let direction: GazeDirection

    var isCorrecting: Bool {
        blend > 0.01 && (abs(appliedShift.x) > 0.3 || abs(appliedShift.y) > 0.3)
    }
}

/// Orchestrates the per-frame chain:
/// landmarks → smoothing → gaze estimation → behaviour FSM → blend → warp plan.
///
/// Holds the temporal state (EMA filters and the FSM), so it must be owned by the
/// frame loop and `reset()` when tracking is lost.
final class GazePipeline {

    private var smoother = FaceGeometrySmoother()
    private var fsm = BehaviorFSM()
    private var blendEMA = ScalarEMA(alpha: CorrectionConfig.blendAlpha)

    var calibration = GazeGeometry3D.Calibration.default

    func reset() {
        smoother.reset()
        fsm.reset()
        blendEMA.reset()
    }

    /// - Parameters:
    ///   - face: raw geometry for this frame
    ///   - strength: user-facing correction strength, 0…1
    ///   - gain: debug multiplier so a weak landmark signal can be made visible
    ///   - method: which estimator supplies the correction vector
    ///   - now: monotonic time; injectable for tests
    func process(face rawFace: FaceGeometry,
                 strength: CGFloat,
                 gain: CGFloat,
                 method: GazeMethod,
                 now: TimeInterval = CACurrentMediaTime()) -> CorrectionPlan {

        // 1. Temporal smoothing of the landmarks themselves. Doing this first means
        //    every downstream estimate inherits the stability.
        let face = smoother.smooth(rawFace)

        // 2. Method A always runs: the behaviour FSM needs a measure of *how far the
        //    user is looking away*, and only the iris can tell us that. Method B
        //    computes the redirection a screen-reader needs, which stays roughly
        //    constant and cannot detect a glance at one's notes.
        let gaze = IrisGazeEstimator.estimate(face)
        let geometry = GazeGeometry3D.estimate(face, calibration: calibration)

        // 3. Behaviour: should we correct at all, and by how much?
        let rawBlend = fsm.update(gazeAngleDeg: gaze.gazeAngleDeg,
                                  pose: face.headPose,
                                  now: now)
        let blend = blendEMA.update(rawBlend)

        // 4. Pick the target position for each iris and derive the full correction
        //    from where the iris actually is right now. This is what makes a sideways
        //    glance come back to the camera instead of being ignored.
        let scale = strength * gain * CGFloat(blend)
        let left  = makeWarp(eye: face.leftEye,
                             target: target(for: face.leftEye, geometry: geometry, method: method),
                             scale: scale)
        let right = makeWarp(eye: face.rightEye,
                             target: target(for: face.rightEye, geometry: geometry, method: method),
                             scale: scale)

        let direction = GazeEstimator.classify(
            dx: gaze.averageOffset.x,
            dy: gaze.averageOffset.y,
            eyeOpenness: (face.leftEye.openness + face.rightEye.openness) / 2
        )

        return CorrectionPlan(
            left: left,
            right: right,
            blend: blend,
            state: fsm.state,
            gazeInfo: gaze,
            geometry: geometry,
            appliedShift: left?.shift ?? .zero,
            direction: direction
        )
    }

    /// Where should this iris end up?
    private func target(for eye: EyeGeometry,
                        geometry: GazeGeometryResult?,
                        method: GazeMethod) -> CGPoint {
        switch method {
        case .irisOffset:
            // Reference behaviour: pull toward the centroid, damped vertically.
            return CGPoint(
                x: eye.center.x,
                y: eye.irisCenter.y
                 + (eye.center.y - eye.irisCenter.y) * CorrectionConfig.verticalDamping
            )
        case .geometry3D:
            // Centroid, nudged by the camera-above-screen offset. No damping: the
            // geometric offset already encodes the natural amount of "up".
            let off = geometry?.leftCorrection ?? .zero
            return CGPoint(x: eye.center.x + off.x, y: eye.center.y + off.y)
        }
    }

    /// Turns a target position into a bounded, ready-to-run warp.
    private func makeWarp(eye: EyeGeometry, target: CGPoint, scale: CGFloat) -> EyeWarp? {
        guard eye.width > 4, eye.height > 2 else { return nil }

        // Full correction = all the way from the current iris to the target,
        // then scaled by strength × gain × behaviour blend and clamped per axis.
        let full = CGPoint(x: target.x - eye.irisCenter.x,
                           y: target.y - eye.irisCenter.y)
        let limit = eye.width * CorrectionConfig.maxShiftFraction
        let shift = CGPoint(
            x: max(-limit, min(limit, full.x * scale)),
            y: max(-limit, min(limit, full.y * scale))
        )
        guard abs(shift.x) > 0.05 || abs(shift.y) > 0.05 else { return nil }

        let feather = max(eye.width * CorrectionConfig.featherFraction, 3)
        let dilate  = max(eye.width * CorrectionConfig.maskDilateFraction, 2)

        // ROI: room for the dilated + feathered mask and the shift itself.
        let pad = eye.width * CorrectionConfig.roiPadFraction
                + max(abs(shift.x), abs(shift.y))
        let roi = eye.bounds.insetBy(dx: -pad, dy: -pad)

        return EyeWarp(shift: shift, roi: roi,
                       contour: eye.contour,
                       feather: feather, maskDilate: dilate,
                       irisFrom: eye.irisCenter,
                       irisTo: CGPoint(x: eye.irisCenter.x + shift.x,
                                       y: eye.irisCenter.y + shift.y))
    }
}
