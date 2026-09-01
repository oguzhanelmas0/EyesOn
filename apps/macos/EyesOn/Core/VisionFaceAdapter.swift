import CoreGraphics
import Vision

/// Converts Apple Vision's output into the source-agnostic `FaceGeometry`.
///
/// This is the seam that ADR-001 will cut: when MediaPipe lands, a
/// `MediaPipeFaceAdapter` produces the same `FaceGeometry` and nothing downstream
/// of this file changes.
///
/// All coordinate maths goes through `VisionCoordinateMapper` so the conversion lives
/// in exactly one place (this closes problem P3 in docs/EYE_CONTACT.md).
enum VisionFaceAdapter {

    static func makeFaceGeometry(from obs: VNFaceObservation,
                                 imageSize: CGSize) -> FaceGeometry? {
        guard let landmarks = obs.landmarks,
              let leftEyeRegion  = landmarks.leftEye,
              let rightEyeRegion = landmarks.rightEye,
              leftEyeRegion.pointCount  > 0,
              rightEyeRegion.pointCount > 0
        else { return nil }

        // viewSize is irrelevant for image-space conversions; pass imageSize.
        let mapper = VisionCoordinateMapper(imageSize: imageSize, viewSize: imageSize)
        let faceBox = obs.boundingBox

        guard let left = makeEye(contourRegion: leftEyeRegion,
                                 irisRegion: landmarks.leftPupil,
                                 faceBox: faceBox, mapper: mapper),
              let right = makeEye(contourRegion: rightEyeRegion,
                                  irisRegion: landmarks.rightPupil,
                                  faceBox: faceBox, mapper: mapper)
        else { return nil }

        // Vision supplies head pose directly, so we do not need solvePnP here.
        // The reference project computes it from landmarks because MediaPipe does
        // not provide it; when we switch engines that code will be needed.
        let pose = HeadPose(
            yawDeg:   (obs.yaw?.doubleValue   ?? 0) * 180 / .pi,
            pitchDeg: (obs.pitch?.doubleValue ?? 0) * 180 / .pi,
            rollDeg:  (obs.roll?.doubleValue  ?? 0) * 180 / .pi
        )

        return FaceGeometry(leftEye: left, rightEye: right,
                            headPose: pose, imageSize: imageSize)
    }

    /// Reduces an arbitrary-length eye contour to the six anchor points DeepWarp
    /// expects, with the inner/outer corners at indices 0 and 3.
    ///
    /// Vision gives 6–8 contour points depending on the model revision, so this
    /// resamples rather than assuming a fixed count.
    private static func anchorPoints(from contour: [CGPoint]) -> [CGPoint] {
        guard contour.count >= 6 else { return [] }
        if contour.count == 6 { return contour }
        let step = CGFloat(contour.count - 1) / 5.0
        return (0..<6).map { contour[Int((CGFloat($0) * step).rounded())] }
    }

    private static func makeEye(contourRegion: VNFaceLandmarkRegion2D,
                                irisRegion: VNFaceLandmarkRegion2D?,
                                faceBox: CGRect,
                                mapper: VisionCoordinateMapper) -> EyeGeometry? {
        let contour = contourRegion.normalizedPoints.map {
            mapper.toImagePx(local: $0, inFaceBox: faceBox)
        }
        guard !contour.isEmpty else { return nil }

        // Fall back to the contour centroid when no pupil is reported — the eye is
        // then treated as looking straight ahead, which is the safe default.
        let iris: CGPoint
        if let irisRegion, irisRegion.pointCount > 0 {
            iris = mapper.centroidImagePx(of: irisRegion, inFaceBox: faceBox)
        } else {
            let n = CGFloat(contour.count)
            iris = CGPoint(x: contour.reduce(0) { $0 + $1.x } / n,
                           y: contour.reduce(0) { $0 + $1.y } / n)
        }

        // DeepWarp wants six points with the corners first and last. Vision returns
        // its eye region already ordered around the contour, so the corners are the
        // horizontal extremes; resample six points evenly between them.
        let anchors = Self.anchorPoints(from: contour)

        return EyeGeometry.make(contour: contour, irisCenter: iris, anchorPoints: anchors)
    }
}
