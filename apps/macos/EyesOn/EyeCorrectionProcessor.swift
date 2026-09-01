import CoreImage
import CoreGraphics

/// Applies a `CorrectionPlan` to a frame.
///
/// Method: the whole eye interior is moved as **one rigid piece** and blended back
/// through a feathered mask built from the eye contour.
///
/// Why a rigid translation and not a local "pull" kernel: a falloff-based kernel copies
/// the iris to its target but leaves the original partially in place whenever the shift
/// exceeds the rigid zone — a double, ghosted iris. Translating the entire masked patch
/// is bijective: the old iris position is filled by the sclera that moves with it, so
/// there is nothing left behind to ghost.
///
/// The mask (convex hull of the eye contour, feathered) still guarantees the reference
/// project's core promise: nothing outside the eyelids can move.
enum EyeCorrectionProcessor {

    static func apply(_ plan: CorrectionPlan, to image: CIImage) -> CIImage {
        guard plan.blend > 0.001 else { return image }

        var result = image
        for warp in [plan.left, plan.right].compactMap({ $0 }) {
            // Patches always come from the untouched original; masks are disjoint,
            // so compositing them onto the running result is safe.
            result = correct(warp, source: image, over: result)
        }
        return result.cropped(to: image.extent)
    }

    private static func correct(_ warp: EyeWarp,
                                source: CIImage,
                                over background: CIImage) -> CIImage {
        let roi = warp.roi.intersection(source.extent)
        guard !roi.isNull, roi.width >= 4, roi.height >= 4,
              let mask = contourMask(warp: warp, roi: roi)
        else { return background }

        // Move the eye interior in one piece. `clampedToExtent` fills the trailing
        // edge after the translation (the equivalent of OpenCV's border replication
        // in the reference implementation).
        let moved = source
            .cropped(to: roi)
            .clampedToExtent()
            .transformed(by: CGAffineTransform(translationX: warp.shift.x,
                                               y: warp.shift.y))
            .cropped(to: roi)

        return moved.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: background,
            kCIInputMaskImageKey: mask
        ]).cropped(to: background.extent)
    }

    // MARK: - Mask

    /// Soft-edged mask from the eye contour.
    ///
    /// Ported from `_blend_roi` in `reference/gaze-corrector/gaze_corrector.py`:
    /// convex hull of the contour, then a Gaussian feather. The hull is dilated so the
    /// mask holds full weight over the iris even when it sits at an eye corner —
    /// otherwise the feather band would mix the moved and original iris there.
    private static func contourMask(warp: EyeWarp, roi: CGRect) -> CIImage? {
        guard warp.contour.count >= 3 else { return nil }

        let w = Int(roi.width.rounded(.up))
        let h = Int(roi.height.rounded(.up))
        guard w > 1, h > 1,
              let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }

        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // ROI-local coordinates; both spaces are y-up, no flip needed.
        let local = warp.contour.map { CGPoint(x: $0.x - roi.minX, y: $0.y - roi.minY) }
        let hull = convexHull(local)
        guard hull.count >= 3 else { return nil }

        let centroid = CGPoint(x: hull.reduce(0) { $0 + $1.x } / CGFloat(hull.count),
                               y: hull.reduce(0) { $0 + $1.y } / CGFloat(hull.count))

        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.beginPath()
        for (i, p) in hull.enumerated() {
            let dx = p.x - centroid.x, dy = p.y - centroid.y
            let len = max(hypot(dx, dy), 0.001)
            let q = CGPoint(x: p.x + dx / len * warp.maskDilate,
                            y: p.y + dy / len * warp.maskDilate)
            if i == 0 { ctx.move(to: q) } else { ctx.addLine(to: q) }
        }
        ctx.closePath()
        ctx.fillPath()

        guard let cg = ctx.makeImage() else { return nil }

        return CIImage(cgImage: cg)
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: warp.feather])
            .cropped(to: CGRect(x: 0, y: 0, width: w, height: h))
            .transformed(by: CGAffineTransform(translationX: roi.minX, y: roi.minY))
    }

    /// Andrew's monotone chain convex hull.
    private static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }

        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }

        var lower: [CGPoint] = []
        for p in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }
        var upper: [CGPoint] = []
        for p in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }
        lower.removeLast(); upper.removeLast()
        return lower + upper
    }
}
