import CoreGraphics
import Foundation

// Method A — iris-offset gaze estimation.
// Ported from `reference/gaze-corrector/gaze_estimator.py` (MIT).
//
// Requires no camera calibration and no model: it simply measures how far the iris
// sits from the eye centre and pushes it back. Direction is unambiguous, which makes
// it the safe default.
//
// Its ceiling is the quality of the iris landmark. With Apple Vision's single coarse
// pupil point the measured offset is only a few pixels even at a clear side glance,
// so this method only reaches its potential once MediaPipe lands (ADR-001).

/// Result of gaze estimation, independent of which method produced it.
struct GazeInfo {
    /// Normalised iris displacement per eye, roughly [-1, 1].
    let leftIrisOffset: CGPoint
    let rightIrisOffset: CGPoint

    let headPose: HeadPose

    /// Gaze deviation from the camera, in degrees. Drives the behaviour FSM.
    let gazeAngleDeg: Double

    /// Per-eye pixel displacement needed to bring the gaze to the camera,
    /// in CIImage space (y up). Not yet scaled by strength or blend.
    let leftCorrection: CGPoint
    let rightCorrection: CGPoint

    /// Average of both eyes' normalised offsets — used for the UI direction dot.
    var averageOffset: CGPoint {
        CGPoint(x: (leftIrisOffset.x + rightIrisOffset.x) / 2,
                y: (leftIrisOffset.y + rightIrisOffset.y) / 2)
    }
}

enum IrisGazeEstimator {

    /// Estimates gaze from iris position alone.
    static func estimate(_ face: FaceGeometry) -> GazeInfo {
        let lOffset = face.leftEye.normalisedIrisOffset
        let rOffset = face.rightEye.normalisedIrisOffset

        // Gaze angle from the mean offset magnitude.
        let avg = CGPoint(x: (abs(lOffset.x) + abs(rOffset.x)) / 2,
                          y: (abs(lOffset.y) + abs(rOffset.y)) / 2)
        let angle = Double(hypot(avg.x, avg.y)) * CorrectionConfig.gazeAngleScale

        return GazeInfo(
            leftIrisOffset:  lOffset,
            rightIrisOffset: rOffset,
            headPose:        face.headPose,
            gazeAngleDeg:    angle,
            leftCorrection:  correction(offset: lOffset, eye: face.leftEye),
            rightCorrection: correction(offset: rOffset, eye: face.rightEye)
        )
    }

    /// Displacement that moves the iris back toward the eye centre.
    ///
    /// The vertical component is damped: a person looking at a screen naturally sits
    /// slightly eyes-down, and fully correcting that reads as artificial.
    private static func correction(offset: CGPoint, eye: EyeGeometry) -> CGPoint {
        CGPoint(
            x: -offset.x * eye.width,
            y: -offset.y * eye.height * CorrectionConfig.verticalDamping
        )
    }
}
