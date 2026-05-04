import CoreImage
import Vision

// Gaussian warp-based eye correction.
//
// Uses a Metal CIWarpKernel (GaussianEyeWarp.metal) to simulate natural eye
// rotation. Instead of copy-pasting the iris region (which leaves a ghost),
// the entire eye socket is warped smoothly:
//
//   • At the eye centre:    full displacement → iris appears camera-facing ✓
//   • At the eye corners:   near-zero displacement → outline stays fixed ✓
//   • Between:              Gaussian falloff → looks like a real eye rotation ✓
//
// Falls back to the original image if the Metal kernel is unavailable.

struct EyeCorrectionProcessor {

    // ── Tuning ─────────────────────────────────────────────────────────────
    /// Proportion of the raw pupil offset to compensate [0, 1].
    static let correctionStrength: CGFloat = 0.90
    /// Hard cap on per-axis pixel displacement.
    static let maxPixelShift: CGFloat      = 20.0
    /// Gaussian sigma as a fraction of eye width.
    static let sigmaFraction: CGFloat      = 0.45
    // ───────────────────────────────────────────────────────────────────────

    static func correct(
        image: CIImage,
        observation: VNFaceObservation,
        gazeEstimate: GazeEstimate,
        validation: LandmarkValidationResult
    ) -> CIImage {
        guard validation.isSafe,
              gazeEstimate.direction != .center,
              let landmarks = observation.landmarks else { return image }

        var result = image
        let size   = image.extent.size

        if let eye = landmarks.leftEye {
            result = warpEye(result, eye: eye, pupil: landmarks.leftPupil,
                             faceBox: observation.boundingBox, imageSize: size,
                             rawOffset: gazeEstimate.rawOffset)
        }
        if let eye = landmarks.rightEye {
            result = warpEye(result, eye: eye, pupil: landmarks.rightPupil,
                             faceBox: observation.boundingBox, imageSize: size,
                             rawOffset: gazeEstimate.rawOffset)
        }
        return result
    }

    // MARK: - Per-eye warp

    private static func warpEye(
        _ image: CIImage,
        eye: VNFaceLandmarkRegion2D,
        pupil: VNFaceLandmarkRegion2D?,
        faceBox: CGRect,
        imageSize: CGSize,
        rawOffset: CGPoint
    ) -> CIImage {
        let eyeRect = pixelRect(for: eye, faceBox: faceBox, imageSize: imageSize)
        guard eyeRect.width > 4, eyeRect.height > 4 else { return image }

        // Use centroid (average of landmark points), same reference as GazeEstimator
        let eyeCenter    = eyeCentroid(for: eye, faceBox: faceBox, imageSize: imageSize)
        let currentPupil = pupilPixelCenter(pupil: pupil, faceBox: faceBox,
                                            imageSize: imageSize, fallback: eyeCenter)

        // Displacement needed to bring iris to eye centre (with strength scaling)
        var dispX = (currentPupil.x - eyeCenter.x) * correctionStrength
        var dispY = (currentPupil.y - eyeCenter.y) * correctionStrength
        dispX = clamp(dispX, limit: maxPixelShift)
        dispY = clamp(dispY, limit: maxPixelShift)
        guard abs(dispX) > 0.5 || abs(dispY) > 0.5 else { return image }

        let sigma = eyeRect.width * sigmaFraction

        // Metal Gaussian warp (preferred)
        if let warpKernel = EyeWarpKernel.shared {
            return warpKernel.apply(
                to: image,
                pupilCenter: currentPupil,
                eyeCenter: eyeCenter,
                sigma: sigma,
                strength: correctionStrength
            )
        }

        // ── Fallback: simple pixel shift (visible but leaves ghost iris) ──────
        let dx = -dispX
        let dy = -dispY
        let targetCenter = CGPoint(x: currentPupil.x + dx,
                                   y: currentPupil.y + dy)
        let irisRadius = eyeRect.width * 0.40
        let irisRect   = CGRect(x: targetCenter.x - irisRadius,
                                y: targetCenter.y - irisRadius,
                                width: irisRadius * 2, height: irisRadius * 2)
        let shifted = image.transformed(by: CGAffineTransform(translationX: dx, y: dy))
        let sigma2  = Double(irisRect.width) * 0.12
        let mask    = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: irisRect)
            .applyingGaussianBlur(sigma: sigma2)
            .cropped(to: image.extent)
        return shifted
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: mask
            ])
            .cropped(to: image.extent)
    }

    // MARK: - Coordinate helpers

    private static func eyeCentroid(
        for region: VNFaceLandmarkRegion2D,
        faceBox: CGRect, imageSize: CGSize
    ) -> CGPoint {
        let pts = region.normalizedPoints
        let cx = pts.map { $0.x }.reduce(0, +) / CGFloat(pts.count)
        let cy = pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count)
        return CGPoint(x: (faceBox.minX + cx * faceBox.width)  * imageSize.width,
                       y: (faceBox.minY + cy * faceBox.height) * imageSize.height)
    }

    private static func pixelRect(
        for region: VNFaceLandmarkRegion2D,
        faceBox: CGRect, imageSize: CGSize
    ) -> CGRect {
        let pts = region.normalizedPoints.map { pt in
            CGPoint(x: (faceBox.minX + pt.x * faceBox.width)  * imageSize.width,
                    y: (faceBox.minY + pt.y * faceBox.height) * imageSize.height)
        }
        guard let minX = pts.map({ $0.x }).min(), let maxX = pts.map({ $0.x }).max(),
              let minY = pts.map({ $0.y }).min(), let maxY = pts.map({ $0.y }).max()
        else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func pupilPixelCenter(
        pupil: VNFaceLandmarkRegion2D?, faceBox: CGRect,
        imageSize: CGSize, fallback: CGPoint
    ) -> CGPoint {
        guard let pupil, pupil.pointCount > 0 else { return fallback }
        let pts = pupil.normalizedPoints
        let cx  = pts.map { $0.x }.reduce(0, +) / CGFloat(pts.count)
        let cy  = pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count)
        return CGPoint(x: (faceBox.minX + cx * faceBox.width)  * imageSize.width,
                       y: (faceBox.minY + cy * faceBox.height) * imageSize.height)
    }

    private static func clamp(_ v: CGFloat, limit: CGFloat) -> CGFloat {
        max(-limit, min(limit, v))
    }
}
