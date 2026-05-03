import CoreImage
import Vision

// Conservative eye correction — shifts iris region slightly toward camera gaze.
//
// Constraints (MVP 4.1):
//   • Maximum pixel shift is clamped to maxPixelShift (default 5 px).
//   • Only the iris neighbourhood is affected — eyelids stay untouched.
//   • Feathering radius is tighter to reduce visible blurring.
//   • Correction is skipped when LandmarkValidationResult.isSafe == false.
//
// MVP 5+ will replace this with a CoreML-based eye redirection model.

struct EyeCorrectionProcessor {

    // ── Tuning ─────────────────────────────────────────────────────────────
    /// Shift magnitude as fraction of eye width/height (conservative).
    static let hFraction: CGFloat    = 0.18
    static let vFraction: CGFloat    = 0.14
    /// Hard cap on pixel displacement regardless of eye size.
    static let maxPixelShift: CGFloat = 5.0
    /// Iris neighbourhood radius as fraction of eye width (smaller = less blur).
    static let irisRadiusFraction: CGFloat = 0.45
    // ───────────────────────────────────────────────────────────────────────

    static func correct(
        image: CIImage,
        observation: VNFaceObservation,
        gaze: GazeDirection,
        validation: LandmarkValidationResult
    ) -> CIImage {
        // Safety gate: never correct when landmarks are unreliable
        guard validation.isSafe, gaze != .center,
              let landmarks = observation.landmarks else { return image }

        var result = image
        let size   = image.extent.size

        if let eye = landmarks.leftEye {
            result = applyShift(to: result, eye: eye,
                                faceBox: observation.boundingBox,
                                imageSize: size, gaze: gaze)
        }
        if let eye = landmarks.rightEye {
            result = applyShift(to: result, eye: eye,
                                faceBox: observation.boundingBox,
                                imageSize: size, gaze: gaze)
        }
        return result
    }

    // MARK: - Private

    private static func applyShift(
        to image: CIImage,
        eye: VNFaceLandmarkRegion2D,
        faceBox: CGRect,
        imageSize: CGSize,
        gaze: GazeDirection
    ) -> CIImage {
        let eyeRect = pixelRect(for: eye, faceBox: faceBox, imageSize: imageSize)
        guard eyeRect.width > 4, eyeRect.height > 4 else { return image }

        // Compute raw shift and clamp to maxPixelShift
        let rawDx = gaze.correctionShift.x * eyeRect.width  * hFraction
        let rawDy = gaze.correctionShift.y * eyeRect.height * vFraction
        let dx = clamp(rawDx, limit: maxPixelShift)
        let dy = clamp(rawDy, limit: maxPixelShift)

        // Iris neighbourhood: smaller rectangle centred on the eye
        let irisW = eyeRect.width  * irisRadiusFraction * 2
        let irisH = eyeRect.height * irisRadiusFraction * 2
        let irisRect = CGRect(
            x: eyeRect.midX - irisW / 2,
            y: eyeRect.midY - irisH / 2,
            width: irisW, height: irisH
        )

        // Shift full image — masked to iris neighbourhood only
        let shifted = image.transformed(by: CGAffineTransform(translationX: dx, y: dy))

        // Tight feathered mask centred on iris (small blur radius = sharper boundary)
        let blurSigma = min(irisRect.width, irisRect.height) * 0.30
        let mask = CIImage(color: CIColor(red: 1, green: 1, blue: 1, alpha: 1))
            .cropped(to: irisRect)
            .applyingGaussianBlur(sigma: Double(blurSigma))
            .cropped(to: image.extent)

        return shifted
            .applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: mask
            ])
            .cropped(to: image.extent)
    }

    // MARK: - Coordinate helpers

    /// Vision landmark region → pixel CGRect (CIImage space: origin bottom-left).
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

    private static func clamp(_ value: CGFloat, limit: CGFloat) -> CGFloat {
        max(-limit, min(limit, value))
    }
}
