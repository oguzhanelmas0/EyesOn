import SwiftUI
import Vision

struct FaceOverlayView: View {
    let observations: [VNFaceObservation]
    let frameSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                for observation in observations {
                    draw(observation, in: &context, viewSize: size)
                }
            }
        }
    }

    // MARK: - Drawing

    private func draw(_ obs: VNFaceObservation, in context: inout GraphicsContext, viewSize: CGSize) {
        // Face bounding box
        let faceRect = visionRectToView(obs.boundingBox, viewSize: viewSize)
        context.stroke(Path(faceRect), with: .color(.green.opacity(0.6)), lineWidth: 1.5)

        guard let landmarks = obs.landmarks else { return }

        drawEyeRegion(landmarks.leftEye,  faceBox: obs.boundingBox, in: &context, viewSize: viewSize)
        drawEyeRegion(landmarks.rightEye, faceBox: obs.boundingBox, in: &context, viewSize: viewSize)

        drawPupil(landmarks.leftPupil,  faceBox: obs.boundingBox, in: &context, viewSize: viewSize)
        drawPupil(landmarks.rightPupil, faceBox: obs.boundingBox, in: &context, viewSize: viewSize)
    }

    private func drawEyeRegion(
        _ region: VNFaceLandmarkRegion2D?,
        faceBox: CGRect,
        in context: inout GraphicsContext,
        viewSize: CGSize
    ) {
        guard let region, region.pointCount >= 2 else { return }

        let pts = region.normalizedPoints.map { pt in
            visionPointToView(
                CGPoint(x: faceBox.minX + pt.x * faceBox.width,
                        y: faceBox.minY + pt.y * faceBox.height),
                viewSize: viewSize
            )
        }

        var path = Path()
        path.move(to: pts[0])
        pts.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()

        context.stroke(path, with: .color(.cyan), lineWidth: 2)
        context.fill(path, with: .color(.cyan.opacity(0.12)))
    }

    private func drawPupil(
        _ pupil: VNFaceLandmarkRegion2D?,
        faceBox: CGRect,
        in context: inout GraphicsContext,
        viewSize: CGSize
    ) {
        guard let pupil, pupil.pointCount > 0 else { return }

        let pts = pupil.normalizedPoints
        let cx = pts.map { $0.x }.reduce(0, +) / CGFloat(pts.count)
        let cy = pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count)

        let absVision = CGPoint(x: faceBox.minX + cx * faceBox.width,
                                y: faceBox.minY + cy * faceBox.height)
        let viewPt = visionPointToView(absVision, viewSize: viewSize)

        let r: CGFloat = 4
        let dot = Path(ellipseIn: CGRect(x: viewPt.x - r, y: viewPt.y - r, width: r * 2, height: r * 2))
        context.fill(dot, with: .color(.yellow))
        context.stroke(dot, with: .color(.orange), lineWidth: 1)
    }

    // MARK: - Coordinate Conversion
    //
    // Vision: normalized [0,1], origin bottom-left
    // View:   pixels, origin top-left, resizeAspectFill mapping

    private func visionPointToView(_ pt: CGPoint, viewSize: CGSize) -> CGPoint {
        guard frameSize.width > 0, frameSize.height > 0 else { return .zero }

        let scale   = max(viewSize.width / frameSize.width, viewSize.height / frameSize.height)
        let scaledW = frameSize.width  * scale
        let scaledH = frameSize.height * scale
        let offsetX = (scaledW - viewSize.width)  / 2.0
        let offsetY = (scaledH - viewSize.height) / 2.0

        return CGPoint(
            x:  pt.x        * scaledW - offsetX,
            y: (1.0 - pt.y) * scaledH - offsetY
        )
    }

    private func visionRectToView(_ rect: CGRect, viewSize: CGSize) -> CGRect {
        let tl = visionPointToView(CGPoint(x: rect.minX, y: rect.maxY), viewSize: viewSize)
        let br = visionPointToView(CGPoint(x: rect.maxX, y: rect.minY), viewSize: viewSize)
        return CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
    }
}
