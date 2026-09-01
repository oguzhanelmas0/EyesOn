import CoreGraphics
import Foundation

// Method B — 3D geometric gaze redirection.
// Ported from `reference/deepwarp-cam/model_managers/gaze_corrector_v1.py` (MIT),
// after Hsu, Wang, Lei & Chen, "Look at Me! Correcting Eye Gaze in Live Video
// Communication", ACM TOMM 15(2), 2019.
//
// Why this matters: it does not use the iris landmark at all. It recovers the eye's
// position in 3D space from the inter-ocular distance — a measurement Apple Vision
// gives us reliably — and computes the angle the gaze must rotate through so that a
// person looking at the screen appears to look at the camera.
//
// That makes it usable *today*, before MediaPipe, whereas Method A is bottlenecked on
// Vision's coarse pupil point.
//
// Coordinate note: the reference works in OpenCV's top-left origin. This port converts
// to that convention internally and returns displacements back in CIImage space (y up).

struct GazeGeometryResult {
    /// Eye position in cm, relative to the screen centre.
    let eyeXcm: CGFloat
    let eyeYcm: CGFloat
    let eyeZcm: CGFloat

    /// Rotation the gaze must undergo, in degrees.
    /// Positive vertical = rotate gaze upward.
    let verticalAngleDeg: Double
    let horizontalAngleDeg: Double

    /// Image scale recovered from the known inter-pupillary distance.
    let pixelsPerCm: CGFloat

    /// Per-eye pixel displacement in CIImage space (y up).
    let leftCorrection: CGPoint
    let rightCorrection: CGPoint

    /// Magnitude of the redirection, for the behaviour FSM.
    var gazeAngleDeg: Double { hypot(verticalAngleDeg, horizontalAngleDeg) }
}

enum GazeGeometry3D {

    /// Camera geometry. Defaults describe a typical laptop; a future calibration
    /// screen should let the user adjust them.
    struct Calibration {
        var focalLengthPx: CGFloat = CorrectionConfig.defaultFocalLengthPx
        var ipdCm: CGFloat         = CorrectionConfig.defaultIPDcm
        var cameraOffset           = CorrectionConfig.defaultCameraOffsetCm

        /// Horizontal sign convention. ⚠️ Not yet verified against a live camera —
        /// flip this if the horizontal correction pushes the wrong way.
        var invertHorizontal: Bool = false
        /// Vertical sign convention. Derived from the reference's frame:
        /// a positive vertical angle means "rotate the gaze upward", which in
        /// CIImage space (y up) is a positive y displacement.
        var invertVertical: Bool = false

        static let `default` = Calibration()
    }

    static func estimate(_ face: FaceGeometry,
                         calibration: Calibration = .default) -> GazeGeometryResult? {

        let ipdPx = face.interocularDistancePx
        guard ipdPx > 1 else { return nil }

        let f = calibration.focalLengthPx
        let W = face.imageSize.width
        let H = face.imageSize.height
        let offset = calibration.cameraOffset

        // Depth from the known physical inter-pupillary distance.
        // Negative = in front of the camera.
        let eyeZ = -(f * calibration.ipdCm) / ipdPx
        let absZ = abs(eyeZ)

        // The reference measures y downward from the top of the frame; convert.
        let lxTop = face.leftEye.center.x
        let rxTop = face.rightEye.center.x
        let lyTop = H - face.leftEye.center.y
        let ryTop = H - face.rightEye.center.y

        let eyeX = -absZ * (lxTop + rxTop - W) / (2 * f) + offset.x
        let eyeY =  absZ * (lyTop + ryTop - H) / (2 * f) + offset.y

        // Rotation required = (angle from eye to screen centre) − (angle from eye to camera).
        // The reference expresses that difference as a sum, because the second term is
        // formed with a negated numerator.
        let dz = 0 - eyeZ
        let dzCam = offset.z - eyeZ
        guard abs(dz) > 0.001, abs(dzCam) > 0.001 else { return nil }

        var aV = atan(Double((0 - eyeY) / dz)) * 180 / .pi
              +  atan(Double((eyeY - offset.y) / dzCam)) * 180 / .pi
        var aH = atan(Double((0 - eyeX) / dz)) * 180 / .pi
              +  atan(Double((eyeX - offset.x) / dzCam)) * 180 / .pi

        if calibration.invertVertical   { aV = -aV }
        if calibration.invertHorizontal { aH = -aH }

        // Convert the rotation into an on-image iris displacement.
        // The iris travels across the eyeball surface: shift ≈ radius × sin(angle).
        let pixelsPerCm = ipdPx / calibration.ipdCm
        let radiusPx = CorrectionConfig.eyeballRadiusCm * pixelsPerCm

        let dx = radiusPx * CGFloat(sin(aH * .pi / 180))
        let dy = radiusPx * CGFloat(sin(aV * .pi / 180))
        let displacement = CGPoint(x: dx, y: dy)

        return GazeGeometryResult(
            eyeXcm: eyeX, eyeYcm: eyeY, eyeZcm: eyeZ,
            verticalAngleDeg: aV,
            horizontalAngleDeg: aH,
            pixelsPerCm: pixelsPerCm,
            leftCorrection: displacement,
            rightCorrection: displacement
        )
    }

    /// Focal-length calibration helper.
    /// The user places their face a known distance away; the focal length follows
    /// from the measured inter-ocular pixel distance.
    static func calibrateFocalLength(ipdPx: CGFloat,
                                     distanceCm: CGFloat,
                                     ipdCm: CGFloat = CorrectionConfig.defaultIPDcm) -> CGFloat {
        ipdPx * distanceCm / ipdCm
    }
}
