import CoreImage
import Vision

// Conservative iris-targeted correction.
//
// MVP 4.2 improvements over MVP 4.1:
//   • Proportional shift — correction scales with actual pupil displacement.
//   • Iris-targeted mask — mask is centred on the pupil landmark, not the eye centroid.
//   • Tighter blur — sigma = 8% of iris region (was 30%), sharper boundary.
//   • Larger max shift (14 px) — visibly effective at typical webcam distances.
//   • correctionScale = 0.55 — 55% compensation, leaves some natural gaze intact.

struct EyeCorrectionProcessor {

    // ── Tuning ─────────────────────────────────────────────────────────────
    /// Proportion of the raw pupil displacement that is compensated.
    static let correctionScale: CGFloat = 0.55
    /// Hard cap on pixel displacement (keeps correction from looking artificial).
    static let maxPixelShift: CGFloat   = 14.0
    /// Iris neighbourhood radius as fraction of eye width.
    static let irisRadiusFraction: CGFloat = 0.52
    /// Blur sigma as fraction of iris diameter — tight for a sharper boundary.
    static let blurSigmaFraction: Double   = 0.08
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
            result = applyShift(
                to: result, eye: eye,
                pupil: landmarks.leftPupil,
                faceBox: observation.boundingBox,
                imageSize: size,
                rawOffset: gazeEstimate.rawOffset
            )
        }
        if let eye = landmarks.rightEye {
            result = applyShift(
                to: result, eye: eye,
                pupil: landmarks.rightPupil,
                faceBox: observation.boundingBox,
                imageSize: size,
                rawOffset: gazeEstimate.rawOffset
            )
        }
        return result
    }

    // MARK: - Private

    private static func applyShift(
        to image: CIImage,
        eye: VNFaceLandmarkRegion2D,
        pupil: VNFaceLandmarkRegion2D?,
        faceBox: CGRect,
        imageSize: CGSize,
        rawOffset: CGPoint
    ) -> CIImage {
        let eyeRect = pixelRect(for: eye, faceBox: faceBox, imageSize: imageSize)
        guard eyeRect.width > 4, eyeRect.height > 4 else { return image }

        // Proportional pixel shift — opposite to rawOffset direction
        // rawOffset.x > 0 means pupil is RIGHT → shift LEFT (negative dx in CIImage)
        let dx = clamp(-rawOffset.x * eyeRect.width  * correctionScale, limit: maxPixelShift)
        let dy = clamp(-rawOffset.y * eyeRect.height * correctionScale, limit: maxPixelShift)

        // Skip negligible shifts (avoids pointless blending)
        guard abs(dx) > 0.5 || abs(dy) > 0.5 else { return image }

        // Iris region centred on pupil landmark (if available) or eye centroid
        let irisRadius = eyeRect.width * irisRadiusFraction
        let irisCenter = pupilPixelCenter(pupil: pupil, faceBox: faceBox,
                                          imageSize: imageSize,
                                          fallback: CGPoint(x: eyeRect.midX, y: eyeRect.midY))
        let irisRect = CGRect(
            x: irisCenter.x - irisRadius,
            y: irisCenter.y - irisRadius,
            width: irisRadius * 2,
            height: irisRadius * 2
        )

        // Shift the full image — only iris neighbourhood is exposed via mask
        let shifted = image.transformed(by: CGAffineTransform(translationX: dx, y: dy))

        // Tight feathered mask centred on iris
        let blurSigma = Double(irisRect.width) * blurSigmaFraction
        let mask = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: irisRect)
            .applyingGaussianBlur(sigma: blurSigma)
            .cropped(to: image.extent)

        return shifted
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: mask
            ])
            .cropped(to: image.extent)
    }

    // MARK: - Coordinate helpers

    private static func pixelRect(
        for region: VNFaceLandmarkRegion2D,
        faceBox: CGRect,
        imageSize: CGSize
    ) -> CGRect {
        let pts = region.normalizedPoints.map { pt in
            CGPoint(
                x: (faceBox.minX + pt.x * faceBox.width)  * imageSize.width,
                y: (faceBox.minY + pt.y * faceBox.height) * imageSize.height
            )
        }
        guard let minX = pts.map({ $0.x }).min(),
              let maxX = pts.map({ $0.x }).max(),
              let minY = pts.map({ $0.y }).min(),
              let maxY = pts.map({ $0.y }).max() else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func pupilPixelCenter(
        pupil: VNFaceLandmarkRegion2D?,
        faceBox: CGRect,
        imageSize: CGSize,
        fallback: CGPoint
    ) -> CGPoint {
        guard let pupil, pupil.pointCount > 0 else { return fallback }
        let pts = pupil.normalizedPoints
        let cx  = pts.map { $0.x }.reduce(0, +) / CGFloat(pts.count)
        let cy  = pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count)
        return CGPoint(
            x: (faceBox.minX + cx * faceBox.width)  * imageSize.width,
            y: (faceBox.minY + cy * faceBox.height) * imageSize.height
        )
    }

    private static func clamp(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        max(-limit, min(limit, value))
    }
}
