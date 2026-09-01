import CoreGraphics
import CoreImage
import Foundation
import OnnxRuntimeBindings

/// DeepWarp eye-gaze redirection model, run through ONNX Runtime.
///
/// Ported from `reference/deepwarp-cam` (MIT), after Hsu, Wang, Lei & Chen,
/// "Look at Me! Correcting Eye Gaze in Live Video Communication", ACM TOMM 15(2), 2019.
///
/// Why this exists: a 2D pixel warp can only stretch the pixels already in the frame.
/// When the iris moves, the sclera that should appear behind it does not exist anywhere
/// in the image, so any purely geometric method blurs or ghosts at larger corrections.
/// This network was trained to *synthesise* the redirected eye — it predicts a dense
/// flow field plus a light-correction term — which is why it clears that ceiling.
///
/// Model inputs (per eye, separate weights for left and right):
///   - image  48×64×3, RGB normalised to [0, 1]
///   - anchor 48×64×12, distance maps for six eye landmarks
///   - angle  2, (vertical, horizontal) redirection in **degrees**
///
/// The model needs no iris landmark: the anchor map comes from the eye contour and the
/// angle from inter-ocular geometry. TF→ONNX fidelity verified in EXP-007.
final class DeepWarpModel: @unchecked Sendable {

    // Model input geometry, fixed at training time.
    static let inputHeight = 48
    static let inputWidth  = 64
    static let anchorCount = 6
    static let anchorChannels = 12   // six landmarks × (Δx, Δy)

    private let env: ORTEnv
    private let leftSession: ORTSession
    private let rightSession: ORTSession
    private let ciContext: CIContext

    /// Nil when either model file is missing or fails to load, so callers fall back
    /// to the geometric warp rather than losing correction entirely.
    init?(ciContext: CIContext) {
        guard let leftPath = Self.modelPath(for: .left),
              let rightPath = Self.modelPath(for: .right) else {
            print("[DeepWarpModel] ❌ deepwarp_L.onnx / deepwarp_R.onnx not found")
            return nil
        }
        do {
            let env = try ORTEnv(loggingLevel: .warning)
            let options = try ORTSessionOptions()
            try options.setIntraOpNumThreads(2)
            try options.setGraphOptimizationLevel(.all)

            self.env = env
            self.leftSession  = try ORTSession(env: env, modelPath: leftPath,  sessionOptions: options)
            self.rightSession = try ORTSession(env: env, modelPath: rightPath, sessionOptions: options)
            self.ciContext = ciContext
            print("[DeepWarpModel] ✅ Loaded both eye models")
        } catch {
            print("[DeepWarpModel] ❌ Session init failed: \(error)")
            return nil
        }
    }

    private static func modelPath(for side: EyeSide) -> String? {
        let name = side == .left ? "deepwarp_L" : "deepwarp_R"
        if let p = Bundle.main.path(forResource: name, ofType: "onnx") { return p }
        let fallback = "/Volumes/Oğuzhan SSD/Projects/EyesON/models/deepwarp/onnx/\(name).onnx"
        return FileManager.default.fileExists(atPath: fallback) ? fallback : nil
    }

    // MARK: - Crop geometry

    /// The eye crop rectangle the model was trained on.
    ///
    /// Ported verbatim from `_extract_single_eye`: a box 1.5× as tall as it is
    /// half-wide, positioned asymmetrically about the eye centre (7/12 above,
    /// 5/12 below) so it captures the upper lid and brow shadow.
    ///
    /// The reference works in OpenCV's y-down space; here y is up, so "above" is +y.
    static func cropRect(for eye: EyeGeometry) -> CGRect? {
        guard eye.anchorPoints.count == anchorCount else { return nil }
        let p = eye.anchorPoints
        let eyeLen = abs(p[3].x - p[0].x)
        guard eyeLen > 2 else { return nil }

        let halfW = eyeLen * 3.0 / 4.0
        let boxH  = 1.5 * halfW
        let up    = boxH * 7.0 / 12.0
        let down  = boxH * 5.0 / 12.0

        let cx = (p[0].x + p[3].x) / 2
        let cy = (p[0].y + p[3].y) / 2

        return CGRect(x: cx - halfW, y: cy - down, width: halfW * 2, height: up + down)
    }

    // MARK: - Inference

    /// Runs the model for one eye and returns the corrected patch as a CIImage placed
    /// back at `cropRect`, or nil if anything is unavailable.
    ///
    /// - Parameters:
    ///   - angleDeg: (vertical, horizontal) redirection in degrees, from `GazeGeometry3D`
    func correctedEye(from source: CIImage,
                      eye: EyeGeometry,
                      side: EyeSide,
                      angleDeg: CGPoint) -> CIImage? {
        guard let crop = Self.cropRect(for: eye)?.intersection(source.extent),
              !crop.isNull, crop.width >= 8, crop.height >= 8 else { return nil }

        guard let rgb = sampleCrop(source, rect: crop) else { return nil }
        let anchor = anchorMap(eye: eye, crop: crop, side: side)

        guard let output = runModel(side: side, image: rgb, anchor: anchor,
                                    angle: (Float(angleDeg.y), Float(angleDeg.x)))
        else { return nil }

        return makeImage(from: output, placedAt: crop)
    }

    /// Rasterises the crop to 48×64 RGB in [0, 1], row 0 = top (model convention).
    private func sampleCrop(_ image: CIImage, rect: CGRect) -> [Float]? {
        let w = Self.inputWidth, h = Self.inputHeight
        var bgra = [UInt8](repeating: 0, count: w * h * 4)

        // Scale the crop to exactly 48×64 and render it.
        let scaled = image
            .cropped(to: rect)
            .transformed(by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
            .transformed(by: CGAffineTransform(scaleX: CGFloat(w) / rect.width,
                                               y: CGFloat(h) / rect.height))

        ciContext.render(scaled,
                         toBitmap: &bgra,
                         rowBytes: w * 4,
                         bounds: CGRect(x: 0, y: 0, width: w, height: h),
                         format: .BGRA8,
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        // BGRA, y-up → RGB float, y-down (the model's row order).
        var out = [Float](repeating: 0, count: h * w * 3)
        for row in 0..<h {
            let srcRow = h - 1 - row
            for col in 0..<w {
                let s = (srcRow * w + col) * 4
                let d = (row * w + col) * 3
                out[d + 0] = Float(bgra[s + 2]) / 255.0   // R
                out[d + 1] = Float(bgra[s + 1]) / 255.0   // G
                out[d + 2] = Float(bgra[s + 0]) / 255.0   // B
            }
        }
        return out
    }

    /// Builds the 48×64×12 anchor map.
    ///
    /// For each of the six landmarks the model gets two channels holding the signed
    /// pixel distance from that landmark to every position in the crop. This is how the
    /// network learns where the eyelids and corners are without a segmentation mask.
    ///
    /// Channel order per landmark is (Δx, Δy); landmark order is `[3,2,1,0,5,4]` for the
    /// left eye and `[0,1,2,3,4,5]` for the right, exactly as in the reference.
    private func anchorMap(eye: EyeGeometry, crop: CGRect, side: EyeSide) -> [Float] {
        let w = Self.inputWidth, h = Self.inputHeight
        let seq = side == .left ? [3, 2, 1, 0, 5, 4] : [0, 1, 2, 3, 4, 5]
        var map = [Float](repeating: 0, count: h * w * Self.anchorChannels)

        let sx = CGFloat(w) / crop.width
        let sy = CGFloat(h) / crop.height

        for (i, idx) in seq.enumerated() {
            let pt = eye.anchorPoints[idx]
            let lx = Float(((pt.x - crop.minX) * sx).rounded())
            // Flip to the model's y-down row order.
            let ly = Float((CGFloat(h) - (pt.y - crop.minY) * sy).rounded())

            let cx = i * 2, cy = i * 2 + 1
            for row in 0..<h {
                let dy = Float(row) - ly
                for col in 0..<w {
                    let base = (row * w + col) * Self.anchorChannels
                    map[base + cx] = Float(col) - lx
                    map[base + cy] = dy
                }
            }
        }
        return map
    }

    private func runModel(side: EyeSide,
                          image: [Float],
                          anchor: [Float],
                          angle: (Float, Float)) -> [Float]? {
        let h = Self.inputHeight, w = Self.inputWidth
        do {
            let imgT = try tensor(image, shape: [1, NSNumber(value: h), NSNumber(value: w), 3])
            let ancT = try tensor(anchor, shape: [1, NSNumber(value: h), NSNumber(value: w),
                                                  NSNumber(value: Self.anchorChannels)])
            let angT = try tensor([angle.0, angle.1], shape: [1, 2])

            let session = side == .left ? leftSession : rightSession
            let outputs = try session.run(
                withInputs: ["input_image:0": imgT,
                             "input_anchor:0": ancT,
                             "input_angle:0": angT],
                outputNames: ["output_image:0"],
                runOptions: nil
            )
            guard let out = outputs["output_image:0"],
                  let data = try? out.tensorData() as Data else { return nil }

            return data.withUnsafeBytes { raw in
                Array(raw.bindMemory(to: Float.self).prefix(h * w * 3))
            }
        } catch {
            print("[DeepWarpModel] ❌ inference failed: \(error)")
            return nil
        }
    }

    private func tensor(_ values: [Float], shape: [NSNumber]) throws -> ORTValue {
        var v = values
        let data = NSMutableData(bytes: &v, length: v.count * MemoryLayout<Float>.stride)
        return try ORTValue(tensorData: data,
                            elementType: .float,
                            shape: shape)
    }

    /// Turns the model's 48×64×3 output back into a CIImage at the crop's position.
    private func makeImage(from values: [Float], placedAt rect: CGRect) -> CIImage? {
        let w = Self.inputWidth, h = Self.inputHeight
        var bgra = [UInt8](repeating: 255, count: w * h * 4)

        for row in 0..<h {
            let dstRow = h - 1 - row     // back to y-up
            for col in 0..<w {
                let s = (row * w + col) * 3
                let d = (dstRow * w + col) * 4
                bgra[d + 2] = UInt8(max(0, min(255, values[s + 0] * 255)))  // R
                bgra[d + 1] = UInt8(max(0, min(255, values[s + 1] * 255)))  // G
                bgra[d + 0] = UInt8(max(0, min(255, values[s + 2] * 255)))  // B
                bgra[d + 3] = 255
            }
        }

        let data = Data(bgra)
        let image = CIImage(bitmapData: data,
                            bytesPerRow: w * 4,
                            size: CGSize(width: w, height: h),
                            format: .BGRA8,
                            colorSpace: CGColorSpaceCreateDeviceRGB())

        // Scale the 48×64 patch back to the crop's size in the frame.
        return image
            .transformed(by: CGAffineTransform(scaleX: rect.width / CGFloat(w),
                                               y: rect.height / CGFloat(h)))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}
