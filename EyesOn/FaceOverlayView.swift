import SwiftUI
import Vision

struct FaceOverlayView: View {
    let observations: [VNFaceObservation]
    let frameSize: CGSize

    var body: some View {
        GeometryReader { geometry in
            let mapper = VisionCoordinateMapper(imageSize: frameSize, viewSize: geometry.size)
            Canvas { context, _ in
                for observation in observations {
                    draw(observation, mapper: mapper, in: &context)
                }
            }
        }
    }

    // MARK: - Drawing

    private func draw(
        _ obs: VNFaceObservation,
        mapper: VisionCoordinateMapper,
        in context: inout GraphicsContext
    ) {
        let faceRect = mapper.toViewRect(obs.boundingBox)
        context.stroke(Path(faceRect), with: .color(.green.opacity(0.6)), lineWidth: 1.5)

        guard let landmarks = obs.landmarks else { return }
        drawEyeRegion(landmarks.leftEye,  faceBox: obs.boundingBox, mapper: mapper, in: &context)
        drawEyeRegion(landmarks.rightEye, faceBox: obs.boundingBox, mapper: mapper, in: &context)
        drawPupil(landmarks.leftPupil,  faceBox: obs.boundingBox, mapper: mapper, in: &context)
        drawPupil(landmarks.rightPupil, faceBox: obs.boundingBox, mapper: mapper, in: &context)
    }

    private func drawEyeRegion(
        _ region: VNFaceLandmarkRegion2D?,
        faceBox: CGRect,
        mapper: VisionCoordinateMapper,
        in context: inout GraphicsContext
    ) {
        guard let region, region.pointCount >= 2 else { return }
        let pts = region.normalizedPoints.map { mapper.toViewPt(local: $0, inFaceBox: faceBox) }
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
        mapper: VisionCoordinateMapper,
        in context: inout GraphicsContext
    ) {
        guard let pupil, pupil.pointCount > 0 else { return }
        let viewPt = mapper.centroidViewPt(of: pupil, inFaceBox: faceBox)
        let r: CGFloat = 4
        let dot = Path(ellipseIn: CGRect(x: viewPt.x - r, y: viewPt.y - r, width: r*2, height: r*2))
        context.fill(dot, with: .color(.yellow))
        context.stroke(dot, with: .color(.orange), lineWidth: 1)
    }
}
