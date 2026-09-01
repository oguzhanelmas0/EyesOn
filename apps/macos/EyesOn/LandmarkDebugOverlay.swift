import SwiftUI
import Vision

/// Debug overlay drawn over the live frame: face box, eye outlines, iris and centroid
/// markers, MediaPipe 478 mesh points, ROI boxes, correction arrows, and a text HUD.
struct LandmarkDebugOverlay: View {

    let observations:       [VNFaceObservation]
    let mediaPipeLandmarks: [Landmark3D]?
    let landmarkSource:     String
    let frameSize:          CGSize
    let plan:               CorrectionPlan?
    let validationResult:   LandmarkValidationResult?
    let method:             GazeMethod
    let showFaceBox:        Bool
    let showLandmarks:      Bool
    let showEyeROI:         Bool

    var body: some View {
        GeometryReader { geo in
            let mapper = VisionCoordinateMapper(imageSize: frameSize, viewSize: geo.size)
            ZStack(alignment: .bottomLeading) {
                Canvas { ctx, _ in
                    if let mpLandmarks = mediaPipeLandmarks, !mpLandmarks.isEmpty {
                        drawMediaPipe(mpLandmarks, mapper: mapper, in: &ctx)
                    } else {
                        for obs in observations {
                            drawObservation(obs, mapper: mapper, in: &ctx)
                        }
                    }

                    if let plan {
                        drawCorrection(plan, mapper: mapper, in: &ctx)
                    }
                }
                hudView(mapper: mapper)
                    .padding(8)
            }
        }
    }

    /// High-contrast colour for the correction arrows; SwiftUI has no `.magenta`.
    private let arrowColor = Color(red: 1.0, green: 0.15, blue: 0.9)

    // MARK: - MediaPipe 478 Rendering

    private func drawMediaPipe(
        _ landmarks: [Landmark3D],
        mapper: VisionCoordinateMapper,
        in ctx: inout GraphicsContext
    ) {
        guard showLandmarks else { return }

        // 1. Draw subtle mesh points
        for i in 0..<min(landmarks.count, 468) {
            let viewPt = mapper.imagePxToViewPt(landmarks[i].cgPoint)
            let r: CGFloat = 1.0
            let dot = Path(ellipseIn: CGRect(x: viewPt.x - r, y: viewPt.y - r, width: r * 2, height: r * 2))
            ctx.fill(dot, with: .color(.white.opacity(0.35)))
        }

        // 2. Draw eye contours
        drawContour(MediaPipeFaceAdapter.viewerLeftEyeContourIndices, landmarks: landmarks, mapper: mapper, color: .yellow, label: "L", in: &ctx)
        drawContour(MediaPipeFaceAdapter.viewerRightEyeContourIndices, landmarks: landmarks, mapper: mapper, color: .orange, label: "R", in: &ctx)

        // 3. Draw Left Iris (468 center + 469..472 ring)
        drawIris(centerIdx: 468, ringIndices: [469, 470, 471, 472], landmarks: landmarks, mapper: mapper, color: .cyan, in: &ctx)

        // 4. Draw Right Iris (473 center + 474..477 ring)
        drawIris(centerIdx: 473, ringIndices: [474, 475, 476, 477], landmarks: landmarks, mapper: mapper, color: .cyan, in: &ctx)
    }

    private func drawContour(
        _ indices: [Int],
        landmarks: [Landmark3D],
        mapper: VisionCoordinateMapper,
        color: Color,
        label: String,
        in ctx: inout GraphicsContext
    ) {
        guard indices.count >= 2 else { return }
        var path = Path()
        let firstPt = mapper.imagePxToViewPt(landmarks[indices[0]].cgPoint)
        path.move(to: firstPt)

        for i in indices.dropFirst() {
            if i < landmarks.count {
                let pt = mapper.imagePxToViewPt(landmarks[i].cgPoint)
                path.addLine(to: pt)
            }
        }
        path.closeSubpath()
        ctx.stroke(path, with: .color(color), lineWidth: 1.5)
        ctx.fill(path, with: .color(color.opacity(0.12)))

        ctx.draw(Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(color),
                 at: CGPoint(x: firstPt.x + 4, y: firstPt.y - 6))
    }

    private func drawIris(
        centerIdx: Int,
        ringIndices: [Int],
        landmarks: [Landmark3D],
        mapper: VisionCoordinateMapper,
        color: Color,
        in ctx: inout GraphicsContext
    ) {
        guard centerIdx < landmarks.count else { return }
        let centerView = mapper.imagePxToViewPt(landmarks[centerIdx].cgPoint)

        // Draw ring
        var ringPath = Path()
        if let firstIdx = ringIndices.first, firstIdx < landmarks.count {
            ringPath.move(to: mapper.imagePxToViewPt(landmarks[firstIdx].cgPoint))
            for idx in ringIndices.dropFirst() where idx < landmarks.count {
                ringPath.addLine(to: mapper.imagePxToViewPt(landmarks[idx].cgPoint))
            }
            ringPath.closeSubpath()
            ctx.stroke(ringPath, with: .color(color), lineWidth: 1.5)
            ctx.fill(ringPath, with: .color(color.opacity(0.3)))
        }

        // Draw iris center dot
        let r: CGFloat = 3.0
        let dot = Path(ellipseIn: CGRect(x: centerView.x - r, y: centerView.y - r, width: r * 2, height: r * 2))
        ctx.fill(dot, with: .color(.white))
        ctx.stroke(dot, with: .color(color), lineWidth: 1.2)
    }

    // MARK: - Vision Fallback Drawing

    private func drawObservation(
        _ obs: VNFaceObservation,
        mapper: VisionCoordinateMapper,
        in ctx: inout GraphicsContext
    ) {
        guard let landmarks = obs.landmarks else { return }
        let fb = obs.boundingBox

        if showFaceBox {
            ctx.stroke(Path(mapper.toViewRect(fb)),
                       with: .color(.green.opacity(0.7)), lineWidth: 1.5)
        }

        if showLandmarks {
            drawEye(landmarks.leftEye,  faceBox: fb, mapper: mapper, color: .blue, label: "L", in: &ctx)
            drawEye(landmarks.rightEye, faceBox: fb, mapper: mapper, color: .red,  label: "R", in: &ctx)
            drawPupilDot(landmarks.leftPupil,  faceBox: fb, mapper: mapper, color: .yellow, in: &ctx)
            drawPupilDot(landmarks.rightPupil, faceBox: fb, mapper: mapper, color: .orange, in: &ctx)
        }

        if showEyeROI {
            drawROI(landmarks.leftEye,  faceBox: fb, mapper: mapper, in: &ctx)
            drawROI(landmarks.rightEye, faceBox: fb, mapper: mapper, in: &ctx)
        }
    }

    /// Arrow from the iris's current position to where the warp moves it.
    private func drawCorrection(
        _ plan: CorrectionPlan,
        mapper: VisionCoordinateMapper,
        in ctx: inout GraphicsContext
    ) {
        for warp in [plan.left, plan.right].compactMap({ $0 }) {
            let target = mapper.imagePxToViewPt(warp.irisTo)
            let source = mapper.imagePxToViewPt(warp.irisFrom)

            var line = Path()
            line.move(to: source)
            line.addLine(to: target)
            ctx.stroke(line, with: .color(arrowColor), lineWidth: 2.2)

            let r: CGFloat = 3.5
            ctx.fill(Path(ellipseIn: CGRect(x: target.x - r, y: target.y - r,
                                            width: r * 2, height: r * 2)),
                     with: .color(arrowColor))
        }
    }

    private func drawEye(
        _ region: VNFaceLandmarkRegion2D?, faceBox fb: CGRect,
        mapper: VisionCoordinateMapper, color: Color, label: String,
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

        if let first = pts.first {
            ctx.draw(Text(label).font(.system(size: 9, weight: .bold)).foregroundColor(color),
                     at: CGPoint(x: first.x + 4, y: first.y - 6))
        }
    }

    private func drawPupilDot(
        _ region: VNFaceLandmarkRegion2D?, faceBox fb: CGRect,
        mapper: VisionCoordinateMapper, color: Color, in ctx: inout GraphicsContext
    ) {
        guard let region, region.pointCount > 0 else { return }
        let c = mapper.centroidViewPt(of: region, inFaceBox: fb)
        let r: CGFloat = 5
        let dot = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r*2, height: r*2))
        ctx.fill(dot, with: .color(color))
        ctx.stroke(dot, with: .color(.white.opacity(0.8)), lineWidth: 1)
    }

    private func drawROI(
        _ region: VNFaceLandmarkRegion2D?, faceBox fb: CGRect,
        mapper: VisionCoordinateMapper, in ctx: inout GraphicsContext
    ) {
        guard let region, region.pointCount > 0 else { return }
        var bounds = mapper.boundsViewRect(of: region, inFaceBox: fb)
        bounds = bounds.insetBy(dx: -bounds.width * 0.20, dy: -bounds.height * 0.20)
        ctx.stroke(Path(bounds), with: .color(.cyan.opacity(0.8)),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }

    // MARK: - HUD

    @ViewBuilder
    private func hudView(mapper: VisionCoordinateMapper) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(buildHUDLines(mapper: mapper), id: \.self) { line in
                Text(line)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.black.opacity(0.75))
        .cornerRadius(6)
    }

    private func buildHUDLines(mapper: VisionCoordinateMapper) -> [String] {
        var lines: [String] = []

        lines.append(String(format: "IMG %dx%d  VIEW %dx%d  [ %@ ]",
                            Int(mapper.imageSize.width), Int(mapper.imageSize.height),
                            Int(mapper.viewSize.width),  Int(mapper.viewSize.height),
                            landmarkSource))

        guard let plan else {
            lines.append("Yüz yok / güvenli değil")
            if let v = validationResult, !v.isSafe {
                lines.append("✗ \(v.rejectionReason ?? "?")")
            }
            return lines
        }

        let g = plan.gazeInfo
        lines.append(String(format: "İris offset  L(%.3f, %.3f)  R(%.3f, %.3f)",
                            g.leftIrisOffset.x, g.leftIrisOffset.y,
                            g.rightIrisOffset.x, g.rightIrisOffset.y))
        lines.append(String(format: "Bakış açısı  %.1f°   Yön: %@",
                            g.gazeAngleDeg, plan.direction.label))

        if let geo = plan.geometry {
            lines.append(String(format: "3B göz konumu  x%.1f  y%.1f  z%.1f cm   %.1f px/cm",
                                geo.eyeXcm, geo.eyeYcm, geo.eyeZcm, geo.pixelsPerCm))
            lines.append(String(format: "Düzeltme açısı  dikey %.1f°  yatay %.1f°",
                                geo.verticalAngleDeg, geo.horizontalAngleDeg))
        }

        lines.append(String(format: "FSM %@  blend %.2f   Yöntem: %@",
                            plan.state.rawValue, plan.blend, method.label))
        lines.append(String(format: "Uygulanan kayma  (%.1f, %.1f) px%@",
                            plan.appliedShift.x, plan.appliedShift.y,
                            plan.isCorrecting ? "  ⚡" : ""))

        if let v = validationResult {
            lines.append(String(format: "EAR L%.2f R%.2f  Yaw %.0f°  Pitch %.0f°",
                                v.leftEyeAR, v.rightEyeAR, v.headYawDeg, v.headPitchDeg))
            lines.append(v.isSafe ? "Safe: YES" : "Safe: NO — \(v.rejectionReason ?? "?")")
        }

        return lines
    }
}
