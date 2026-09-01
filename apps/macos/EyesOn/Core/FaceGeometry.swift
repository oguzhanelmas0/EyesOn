import CoreGraphics

// Landmark-source-agnostic geometry types.
//
// Everything here lives in **CIImage pixel space**: origin bottom-left, y increasing
// upwards. This is the space the warp kernel samples in, so keeping the whole core in
// it removes a class of sign errors.
//
// Note the vertical convention differs from the Python reference projects, which use
// OpenCV's top-left origin. The correction formula `-offset × size × damping` is
// origin-agnostic as long as offset and displacement share a convention — which they do
// here — so the ported maths is unchanged.

/// One eye, fully described in image pixels.
struct EyeGeometry {
    /// Eye contour points in CIImage pixel space.
    let contour: [CGPoint]
    /// Centroid of the contour points.
    let center: CGPoint
    /// Iris/pupil centre. With Apple Vision this is a coarse single point;
    /// with MediaPipe it is the centroid of 5 iris landmarks.
    let irisCenter: CGPoint
    /// Contour bounding box.
    let bounds: CGRect

    var width: CGFloat { bounds.width }
    var height: CGFloat { bounds.height }

    /// Eye aspect ratio: height / width. Open ≈ 0.25–0.35, closed < 0.12.
    var aspectRatio: CGFloat { width > 0.001 ? height / width : 0 }

    /// Openness in [0, 1], normalised against a fully open eye.
    var openness: CGFloat {
        min(aspectRatio / CorrectionConfig.openEyeAspectRatio, 1.0)
    }

    /// Iris displacement from the eye centre, normalised by eye dimensions.
    /// Range roughly [-1, 1] per axis.
    ///
    /// Ported from `reference/gaze-corrector/gaze_estimator.py::_eye_geometry`.
    /// Unlike the current Vision-era code, x and y are divided by their **own**
    /// dimension rather than both by the width.
    var normalisedIrisOffset: CGPoint {
        CGPoint(
            x: (irisCenter.x - center.x) / max(width, 1.0),
            y: (irisCenter.y - center.y) / max(height, 1.0)
        )
    }
}

/// Head orientation in degrees.
struct HeadPose {
    let yawDeg: Double
    let pitchDeg: Double
    let rollDeg: Double

    static let zero = HeadPose(yawDeg: 0, pitchDeg: 0, rollDeg: 0)
}

/// A detected face, independent of which landmark engine produced it.
///
/// `leftEye` / `rightEye` follow the naming of the source engine. With Apple Vision,
/// `leftEye` is observed to land on the **image-left** side of the frame.
struct FaceGeometry {
    let leftEye: EyeGeometry
    let rightEye: EyeGeometry
    let headPose: HeadPose
    let imageSize: CGSize

    /// Distance between the two eye centres, in pixels.
    /// This is the scale reference the 3D geometry method depends on.
    var interocularDistancePx: CGFloat {
        hypot(rightEye.center.x - leftEye.center.x,
              rightEye.center.y - leftEye.center.y)
    }
}
