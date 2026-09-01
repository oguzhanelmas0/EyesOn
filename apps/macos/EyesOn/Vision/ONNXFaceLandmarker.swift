import Foundation
import CoreGraphics
import CoreImage
import CoreVideo
import OnnxRuntimeBindings

/// 3D landmark point (x, y in CIImage pixels, z in relative depth).
struct Landmark3D: Sendable {
    let x: CGFloat
    let y: CGFloat
    let z: CGFloat

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

/// Executes MediaPipe Face Landmarker (478 3D points) via ONNX Runtime on macOS.
final class ONNXFaceLandmarker: @unchecked Sendable {

    private var session: ORTSession?
    private var env: ORTEnv?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    init?() {
        guard let modelPath = findModelPath() else {
            print("[ONNXFaceLandmarker] ❌ Model file face_landmarks_detector.onnx not found in Bundle or models/")
            return nil
        }

        do {
            let env = try ORTEnv(loggingLevel: .warning)
            self.env = env

            let options = try ORTSessionOptions()
            try options.setIntraOpNumThreads(2)
            try options.setGraphOptimizationLevel(.all)

            self.session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
            print("[ONNXFaceLandmarker] ✅ Initialized successfully with model: \(modelPath)")
        } catch {
            print("[ONNXFaceLandmarker] ❌ Failed to initialize session: \(error)")
            return nil
        }
    }

    private func findModelPath() -> String? {
        // 1. Bundle Resources
        if let bundlePath = Bundle.main.path(forResource: "face_landmarks_detector", ofType: "onnx") {
            return bundlePath
        }
        if let bundlePath = Bundle.main.path(forResource: "face_landmarks_detector", ofType: "onnx", inDirectory: "Resources") {
            return bundlePath
        }

        // 2. Relative filesystem path for dev / testing
        let candidates = [
            Bundle.main.bundlePath + "/Contents/Resources/face_landmarks_detector.onnx",
            FileManager.default.currentDirectoryPath + "/models/face_landmarks_detector.onnx",
            FileManager.default.currentDirectoryPath + "/apps/macos/EyesOn/face_landmarks_detector.onnx",
            "/Volumes/Oğuzhan SSD/Projects/EyesON/models/face_landmarks_detector.onnx",
            "/Volumes/Oğuzhan SSD/Projects/EyesON/apps/macos/EyesOn/face_landmarks_detector.onnx"
        ]

        for path in candidates {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    /// Runs MediaPipe Face Landmarker on a cropped face region of the frame.
    ///
    /// - Parameters:
    ///   - ciImage: Full frame CIImage (CIImage coordinate system: origin bottom-left).
    ///   - faceBoxCI: Face bounding box in CIImage pixel space.
    /// - Returns: Array of 478 `Landmark3D` points in CIImage pixel space, or `nil` on failure.
    func detectLandmarks(in ciImage: CIImage, faceBoxCI: CGRect) -> [Landmark3D]? {
        guard let session = self.session else { return nil }

        // 1. Center a square bounding box on the face with 35% margin to preserve natural aspect ratio
        let centerX = faceBoxCI.midX
        let centerY = faceBoxCI.midY
        let faceDim = max(faceBoxCI.width, faceBoxCI.height) * 1.35
        var cropBox = CGRect(
            x: centerX - faceDim * 0.5,
            y: centerY - faceDim * 0.5,
            width: faceDim,
            height: faceDim
        )

        // Clamp to image bounds
        cropBox = cropBox.intersection(ciImage.extent)
        guard cropBox.width > 20, cropBox.height > 20 else { return nil }

        // 2. Crop and resize to 256x256
        let cropped = ciImage.cropped(to: cropBox)
        let scaleX = 256.0 / cropBox.width
        let scaleY = 256.0 / cropBox.height
        let transform = CGAffineTransform(translationX: -cropBox.minX, y: -cropBox.minY)
            .concatenating(CGAffineTransform(scaleX: scaleX, y: scaleY))
        let resized = cropped.transformed(by: transform)

        // 3. Render 256x256 RGB pixel buffer
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            256, 256,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }

        ciContext.render(resized, to: pb)

        // 4. Convert BGRA pixels to float32 RGB tensor [1, 256, 256, 3] in [0, 1]
        // Note: CIContext.render renders top row of CIImage into row 0 of CVPixelBuffer memory.
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)
        let ptr = baseAddress.assumingMemoryBound(to: UInt8.self)

        var floatTensor = [Float](repeating: 0, count: 1 * 256 * 256 * 3)
        var tensorIdx = 0

        for y in 0..<256 {
            let rowPtr = ptr.advanced(by: y * bytesPerRow)
            for x in 0..<256 {
                let pixel = rowPtr.advanced(by: x * 4)
                let b = Float(pixel[0]) / 255.0
                let g = Float(pixel[1]) / 255.0
                let r = Float(pixel[2]) / 255.0

                floatTensor[tensorIdx]     = r
                floatTensor[tensorIdx + 1] = g
                floatTensor[tensorIdx + 2] = b
                tensorIdx += 3
            }
        }

        // 5. Create ORTValue input
        let tensorShape: [NSNumber] = [1, 256, 256, 3]
        let tensorData = NSMutableData(bytes: &floatTensor, length: floatTensor.count * MemoryLayout<Float>.size)
        guard let inputOrtValue = try? ORTValue(
            tensorData: tensorData,
            elementType: .float,
            shape: tensorShape
        ) else { return nil }

        // 6. Run inference
        let outputNames: Set<String> = ["Identity", "Identity_1", "Identity_2"]
        guard let outputs = try? session.run(
            withInputs: ["input_12": inputOrtValue],
            outputNames: outputNames,
            runOptions: nil
        ), let landmarksOutput = outputs["Identity"] else {
            return nil
        }

        // 7. Parse 478 points from Identity output
        guard let outputData = try? landmarksOutput.tensorData() else { return nil }
        let rawFloats = (outputData as Data).withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }

        guard rawFloats.count >= 478 * 3 else { return nil }

        // 8. Map from 256x256 top-down model coordinates back to CIImage pixel coordinates
        // modelX: 0 (left) -> 256 (right) ==> cropBox.minX -> cropBox.maxX
        // modelY: 0 (top / forehead) -> 256 (bottom / chin) ==> cropBox.maxY -> cropBox.minY
        var resultPoints: [Landmark3D] = []
        resultPoints.reserveCapacity(478)

        for i in 0..<478 {
            let modelX = CGFloat(rawFloats[i * 3])
            let modelY = CGFloat(rawFloats[i * 3 + 1])
            let modelZ = CGFloat(rawFloats[i * 3 + 2])

            let fullX = cropBox.minX + (modelX / 256.0) * cropBox.width
            let fullY = cropBox.maxY - (modelY / 256.0) * cropBox.height
            let fullZ = modelZ * (cropBox.width / 256.0)

            resultPoints.append(Landmark3D(x: fullX, y: fullY, z: fullZ))
        }

        return resultPoints
    }
}
