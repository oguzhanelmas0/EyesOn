import CoreGraphics
import Vision

/// Converts between Vision normalised coordinates, CIImage pixel coordinates,
/// and SwiftUI view pixel coordinates.
///
/// Vision: [0,1] normalised, origin **bottom-left**.
/// CIImage: pixel coords, origin **bottom-left**.
/// SwiftUI view: pixel coords, origin **top-left**, scaled with resizeAspectFill.
struct VisionCoordinateMapper {

    let imageSize: CGSize   // CVPixelBuffer size, e.g. 1280×720
    let viewSize:  CGSize   // SwiftUI view size in display pixels

    // MARK: - Derived layout values (resizeAspectFill)

    var scale:   CGFloat { max(viewSize.width  / imageSize.width,
                               viewSize.height / imageSize.height) }
    var scaledW: CGFloat { imageSize.width  * scale }
    var scaledH: CGFloat { imageSize.height * scale }
    var offsetX: CGFloat { (scaledW - viewSize.width)  / 2 }
    var offsetY: CGFloat { (scaledH - viewSize.height) / 2 }

    // MARK: - Vision → View (SwiftUI, top-left origin)

    /// Full-image Vision normalised point → SwiftUI view pixel.
    func toViewPt(_ pt: CGPoint) -> CGPoint {
        CGPoint(x:  pt.x        * scaledW - offsetX,
                y: (1.0 - pt.y) * scaledH - offsetY)
    }

    /// Face-landmark local normalised point → SwiftUI view pixel.
    func toViewPt(local: CGPoint, inFaceBox fb: CGRect) -> CGPoint {
        toViewPt(CGPoint(x: fb.minX + local.x * fb.width,
                         y: fb.minY + local.y * fb.height))
    }

    /// Vision bounding rect (bottom-left origin) → SwiftUI CGRect (top-left origin).
    func toViewRect(_ rect: CGRect) -> CGRect {
        let tl = toViewPt(CGPoint(x: rect.minX, y: rect.maxY))
        let br = toViewPt(CGPoint(x: rect.maxX, y: rect.minY))
        return CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
    }

    // MARK: - Vision → CIImage (bottom-left origin, pixel units)

    /// Full-image Vision normalised point → CIImage pixel (bottom-left origin).
    func toImagePx(_ pt: CGPoint) -> CGPoint {
        CGPoint(x: pt.x * imageSize.width,
                y: pt.y * imageSize.height)
    }

    /// Face-landmark local normalised point → CIImage pixel (bottom-left origin).
    func toImagePx(local: CGPoint, inFaceBox fb: CGRect) -> CGPoint {
        toImagePx(CGPoint(x: fb.minX + local.x * fb.width,
                          y: fb.minY + local.y * fb.height))
    }

    // MARK: - Helpers

    /// Centroid of a landmark region in CIImage pixel space.
    func centroidImagePx(of region: VNFaceLandmarkRegion2D, inFaceBox fb: CGRect) -> CGPoint {
        let pts = region.normalizedPoints
        guard !pts.isEmpty else { return .zero }
        let cx = pts.map { $0.x }.reduce(0, +) / CGFloat(pts.count)
        let cy = pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count)
        return toImagePx(local: CGPoint(x: cx, y: cy), inFaceBox: fb)
    }

    /// Centroid of a landmark region in SwiftUI view pixel space.
    func centroidViewPt(of region: VNFaceLandmarkRegion2D, inFaceBox fb: CGRect) -> CGPoint {
        let pts = region.normalizedPoints
        guard !pts.isEmpty else { return .zero }
        let cx = pts.map { $0.x }.reduce(0, +) / CGFloat(pts.count)
        let cy = pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count)
        return toViewPt(local: CGPoint(x: cx, y: cy), inFaceBox: fb)
    }

    /// Bounding rect of a landmark region in SwiftUI view pixel space.
    func boundsViewRect(of region: VNFaceLandmarkRegion2D, inFaceBox fb: CGRect) -> CGRect {
        let pts = region.normalizedPoints
        guard !pts.isEmpty else { return .zero }
        guard let minX = pts.map({ $0.x }).min(), let maxX = pts.map({ $0.x }).max(),
              let minY = pts.map({ $0.y }).min(), let maxY = pts.map({ $0.y }).max()
        else { return .zero }
        let tl = toViewPt(local: CGPoint(x: minX, y: maxY), inFaceBox: fb)
        let br = toViewPt(local: CGPoint(x: maxX, y: minY), inFaceBox: fb)
        return CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
    }
}
