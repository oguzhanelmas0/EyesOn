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
            // Face count badge
            .overlay(alignment: .topLeading) {
                if !observations.isEmpty {
                    Text("\(observations.count) yüz")
                        .font(.caption.monospaced())
                        .foregroundColor(.green)
                        .padding(6)
                        .background(.black.opacity(0.5))
                        .cornerRadius(6)
                        .padding(10)
                }
            }
        }
    }

    // MARK: - Drawing

    private func draw(_ obs: VNFaceObservation, in context: inout GraphicsContext, viewSize: CGSize) {
        // Face bounding box
        let faceRect = visionRectToView(obs.boundingBox, viewSize: viewSize)
        context.stroke(Path(faceRect), with: .color(.green.opacity(0.7)), lineWidth: 1.5)

        guard let landmarks = obs.landmarks else { return }

        if let eye = landmarks.leftEye {
            drawEye(eye, faceBox: obs.boundingBox, in: &context, viewSize: viewSize)
        }
        if let eye = landmarks.rightEye {
            drawEye(eye, faceBox: obs.boundingBox, in: &context, viewSize: viewSize)
        }
    }

    private func drawEye(
        _ region: VNFaceLandmarkRegion2D,
        faceBox: CGRect,
        in context: inout GraphicsContext,
        viewSize: CGSize
    ) {
        // Landmark points are normalized relative to the face bounding box
        let pts = region.normalizedPoints.map { pt in
            let absVision = CGPoint(
                x: faceBox.minX + pt.x * faceBox.width,
                y: faceBox.minY + pt.y * faceBox.height
            )
            return visionPointToView(absVision, viewSize: viewSize)
        }

        guard pts.count >= 2 else { return }

        var path = Path()
        path.move(to: pts[0])
        pts.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()

        context.stroke(path, with: .color(.cyan), lineWidth: 2)
        context.fill(path, with: .color(.cyan.opacity(0.15)))
    }

    // MARK: - Coordinate Conversion
    //
    // Vision space:  origin bottom-left, normalized [0,1]
    // View space:    origin top-left, pixels
    // Camera preview uses resizeAspectFill → scale to fill, crop excess

    private func visionPointToView(_ pt: CGPoint, viewSize: CGSize) -> CGPoint {
        guard frameSize.width > 0, frameSize.height > 0 else { return .zero }

        let scale   = max(viewSize.width / frameSize.width, viewSize.height / frameSize.height)
        let scaledW = frameSize.width  * scale
        let scaledH = frameSize.height * scale
        let offsetX = (scaledW - viewSize.width)  / 2.0
        let offsetY = (scaledH - viewSize.height) / 2.0

        return CGPoint(
            x:  pt.x          * scaledW - offsetX,
            y: (1.0 - pt.y)   * scaledH - offsetY
        )
    }

    private func visionRectToView(_ rect: CGRect, viewSize: CGSize) -> CGRect {
        // Vision rect: origin bottom-left → convert top-left and bottom-right corners
        let tl = visionPointToView(CGPoint(x: rect.minX, y: rect.maxY), viewSize: viewSize)
        let br = visionPointToView(CGPoint(x: rect.maxX, y: rect.minY), viewSize: viewSize)
        return CGRect(x: tl.x, y: tl.y, width: br.x - tl.x, height: br.y - tl.y)
    }
}
