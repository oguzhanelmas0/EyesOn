import SwiftUI
import Vision

/// Comprehensive debug overlay drawn over the live camera frame.
/// Shows face box, eye outlines, centroids, pupil centres, ROI boxes and a HUD.
struct LandmarkDebugOverlay: View {

    let observations:     [VNFaceObservation]
    let frameSize:        CGSize
    let gazeEstimate:     GazeEstimate?
    let validationResult: LandmarkValidationResult?
    let showFaceBox:      Bool
    let showLandmarks:    Bool
    let showEyeROI:       Bool

    var body: some View {
        GeometryReader { geo in
            let mapper = VisionCoordinateMapper(imageSize: frameSize, viewSize: geo.size)
            ZStack(alignment: .bottomLeading) {
                Canvas { ctx, size in
                    for obs in observations {
                        drawObservation(obs, mapper: mapper, in: &ctx)
                    }
                }
                hudView(mapper: mapper)
                    .padding(8)
            }
        }
    }

    // MARK: - Canvas Drawing

    private func drawObservation(
        _ obs: VNFaceObservation,
        mapper: VisionCoordinateMapper,
        in ctx: inout GraphicsContext
    ) {
        guard let landmarks = obs.landmarks else { return }
        let fb = obs.boundingBox

        // Face bounding box
        if showFaceBox {
            let faceRect = mapper.toViewRect(fb)
            ctx.stroke(Path(faceRect), with: .color(.green.opacity(0.7)), lineWidth: 1.5)
        }

        if showLandmarks {
            drawEye(landmarks.leftEye,  faceBox: fb, mapper: mapper, color: .blue,   label: "L", in: &ctx)
            drawEye(landmarks.rightEye, faceBox: fb, mapper: mapper, color: .red,    label: "R", in: &ctx)
            drawPupilDot(landmarks.leftPupil,  faceBox: fb, mapper: mapper, color: .yellow,  in: &ctx)
            drawPupilDot(landmarks.rightPupil, faceBox: fb, mapper: mapper, color: .orange,  in: &ctx)
            drawCentroidDot(landmarks.leftEye,  faceBox: fb, mapper: mapper, color: .blue,   in: &ctx)
            drawCentroidDot(landmarks.rightEye, faceBox: fb, mapper: mapper, color: .red,    in: &ctx)
        }

        if showEyeROI {
            drawROI(landmarks.leftEye,  faceBox: fb, mapper: mapper, in: &ctx)
            drawROI(landmarks.rightEye, faceBox: fb, mapper: mapper, in: &ctx)
        }
    }

    private func drawEye(
        _ region: VNFaceLandmarkRegion2D?,
        faceBox fb: CGRect,
        mapper: VisionCoordinateMapper,
        color: Color,
        label: String,
        in ctx: inout GraphicsContext
    ) {
        guard let region, region.pointCount >= 2 else { return }
        let pts = region.normalizedPoints.map { mapper.toViewPt(local: $0, inFaceBox: fb) }
        var path = Path()
        path.move(to: pts[0])
        pts.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        ctx.stroke(path, with: .color(color), lineWidth: 1.5)
        ctx.fill(path, with: .color(color.opacity(0.15)))

        // Label at first point
        if let first = pts.first {
            ctx.draw(
                Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(color),
                at: CGPoint(x: first.x + 4, y: first.y - 6)
            )
        }
    }

    private func drawPupilDot(
        _ region: VNFaceLandmarkRegion2D?,
        faceBox fb: CGRect,
        mapper: VisionCoordinateMapper,
        color: Color,
        in ctx: inout GraphicsContext
    ) {
        guard let region, region.pointCount > 0 else { return }
        let centre = mapper.centroidViewPt(of: region, inFaceBox: fb)
        let r: CGFloat = 5
        let dot = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r*2, height: r*2))
        ctx.fill(dot, with: .color(color))
        ctx.stroke(dot, with: .color(.white.opacity(0.8)), lineWidth: 1)
    }

    private func drawCentroidDot(
        _ region: VNFaceLandmarkRegion2D?,
        faceBox fb: CGRect,
        mapper: VisionCoordinateMapper,
        color: Color,
        in ctx: inout GraphicsContext
    ) {
        guard let region, region.pointCount > 0 else { return }
        let centre = mapper.centroidViewPt(of: region, inFaceBox: fb)
        let r: CGFloat = 4
        let ring = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r*2, height: r*2))
        ctx.stroke(ring, with: .color(color), lineWidth: 2)
    }

    private func drawROI(
        _ region: VNFaceLandmarkRegion2D?,
        faceBox fb: CGRect,
        mapper: VisionCoordinateMapper,
        in ctx: inout GraphicsContext
    ) {
        guard let region, region.pointCount > 0 else { return }
        var bounds = mapper.boundsViewRect(of: region, inFaceBox: fb)
        // 20% padding
        let padX = bounds.width  * 0.20
        let padY = bounds.height * 0.20
        bounds = bounds.insetBy(dx: -padX, dy: -padY)
        let dash = Path(bounds)
        ctx.stroke(dash, with: .color(.cyan.opacity(0.8)),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    // MARK: - HUD

    @ViewBuilder
    private func hudView(mapper: VisionCoordinateMapper) -> some View {
        let lines = buildHUDLines(mapper: mapper)
        VStack(alignment: .leading, spacing: 1) {
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.black.opacity(0.72))
        .cornerRadius(6)
    }

    private func buildHUDLines(mapper: VisionCoordinateMapper) -> [String] {
        var lines: [String] = []

        // Image / view / scale
        lines.append(String(format: "IMG: %dx%d  VIEW: %dx%d  SCALE: %.2f×",
                            Int(mapper.imageSize.width), Int(mapper.imageSize.height),
                            Int(mapper.viewSize.width),  Int(mapper.viewSize.height),
                            mapper.scale))

        if let obs = observations.first, let lm = obs.landmarks {
            let fb = obs.boundingBox

            // Eye centroids in image pixel space
            if let le = lm.leftEye {
                let c = mapper.centroidImagePx(of: le, inFaceBox: fb)
                lines.append(String(format: "L-eye centroid: (%.0f, %.0f)px", c.x, c.y))
            }
            if let re = lm.rightEye {
                let c = mapper.centroidImagePx(of: re, inFaceBox: fb)
                lines.append(String(format: "R-eye centroid: (%.0f, %.0f)px", c.x, c.y))
            }

            // Pupil centres in image pixel space + delta
            if let lp = lm.leftPupil, let le = lm.leftEye {
                let p = mapper.centroidImagePx(of: lp, inFaceBox: fb)
                let e = mapper.centroidImagePx(of: le, inFaceBox: fb)
                lines.append(String(format: "L-pupil: (%.0f, %.0f)px  Δ=(%.1f, %.1f)", p.x, p.y, p.x-e.x, p.y-e.y))
            }
            if let rp = lm.rightPupil, let re = lm.rightEye {
                let p = mapper.centroidImagePx(of: rp, inFaceBox: fb)
                let e = mapper.centroidImagePx(of: re, inFaceBox: fb)
                lines.append(String(format: "R-pupil: (%.0f, %.0f)px  Δ=(%.1f, %.1f)", p.x, p.y, p.x-e.x, p.y-e.y))
            }
        }

        // Gaze
        if let g = gazeEstimate {
            lines.append(String(format: "Gaze: %@  rawOff: (%.3f, %.3f)",
                                g.direction.label, g.rawOffset.x, g.rawOffset.y))
        } else {
            lines.append("Gaze: —")
        }

        // Validation
        if let v = validationResult {
            lines.append(String(format: "EAR L:%.2f R:%.2f  Yaw:%.0f°  Pitch:%.0f°",
                                v.leftEyeAR, v.rightEyeAR, v.headYawDeg, v.headPitchDeg))
            if v.isSafe {
                lines.append("Safe: YES")
            } else {
                lines.append("Safe: NO — \(v.rejectionReason ?? "?")")
            }
        }

        return lines
    }
}
