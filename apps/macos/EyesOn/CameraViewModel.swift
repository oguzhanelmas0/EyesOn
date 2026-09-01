import AppKit
import AVFoundation
import Combine
import CoreImage
import Metal
import Vision

@MainActor
final class CameraViewModel: ObservableObject {

    enum CameraState {
        case loading, running, denied, unavailable
    }

    // MARK: - Published state

    @Published var cameraState: CameraState             = .loading
    @Published var faceObservations: [VNFaceObservation] = []
    @Published var mediaPipeLandmarks: [Landmark3D]?    = nil
    @Published var landmarkSource: String               = "MediaPipe"
    @Published var frameSize: CGSize                    = .zero
    @Published var processedFrame: NSImage?
    @Published var validationResult: LandmarkValidationResult?

    /// Full per-frame result of the gaze pipeline: warps, behaviour state, both
    /// estimators' output. Drives both the correction and the debug HUD.
    @Published var plan: CorrectionPlan?
    @Published var gazeDirection: GazeDirection?

    // Correction controls
    /// Left on during active development so each run starts correcting.
    @Published var correctionEnabled: Bool = true
    @Published var correctionStrength: CGFloat = CorrectionConfig.defaultStrength
    /// Debug multiplier. Default 1.0.
    @Published var debugGain: CGFloat = 1.0
    @Published var gazeMethod: GazeMethod = .irisOffset

    // Debug overlay controls
    @Published var debugOverlayEnabled: Bool = true
    @Published var showFaceBox:         Bool = true
    @Published var showLandmarks:       Bool = true
    @Published var showEyeROI:          Bool = true

    // MARK: - Private

    private let manager         = CameraManager()
    private let visionProcessor = VisionProcessor()
    private let pipeline        = GazePipeline()
    private var processingTask: Task<Void, Never>?
    private var directionSmoother = GazeSmoother(size: 6)

    private let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: device) }
        return CIContext()
    }()

    var captureSession: AVCaptureSession { manager.captureSession }

    var isCorrecting: Bool {
        correctionEnabled && (validationResult?.isSafe == true) && (plan?.isCorrecting == true)
    }

    var isCorrectionSafe: Bool { validationResult?.isSafe ?? false }
    var rejectionReason: String? { validationResult?.rejectionReason }

    // MARK: - Lifecycle

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:    launchCamera()
        case .notDetermined: requestPermission()
        default:             cameraState = .denied
        }
    }

    func stop() {
        processingTask?.cancel()
        manager.stopSession()
    }

    private func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor [weak self] in
                if granted { self?.launchCamera() } else { self?.cameraState = .denied }
            }
        }
    }

    private func launchCamera() {
        manager.setup()
        guard manager.hasCamera else { cameraState = .unavailable; return }
        cameraState = .running
        manager.startSession()
        startFrameProcessing()
    }

    // MARK: - Frame pipeline

    private func startFrameProcessing() {
        let stream    = manager.frameStream
        let processor = visionProcessor
        let ctx       = ciContext

        processingTask = Task { @MainActor in
            for await sampleBuffer in stream {
                guard !Task.isCancelled else { break }
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

                // 1. Face & Landmark processing
                let result = await processor.process(pixelBuffer: pixelBuffer)

                // 2. Validation gate
                let validation: LandmarkValidationResult?
                if let obs = result.observations.first {
                    validation = LandmarkValidator.validate(obs)
                } else if result.faceGeometry != nil {
                    validation = LandmarkValidationResult(
                        isSafe: true,
                        rejectionReason: nil,
                        headYawDeg: result.faceGeometry?.headPose.yawDeg ?? 0,
                        headPitchDeg: result.faceGeometry?.headPose.pitchDeg ?? 0,
                        leftEyeAR: result.faceGeometry?.leftEye.aspectRatio ?? 0.3,
                        rightEyeAR: result.faceGeometry?.rightEye.aspectRatio ?? 0.3,
                        interEyeDist: 0.25
                    )
                } else {
                    validation = nil
                }

                // 3. Geometry → Gaze → Behaviour → Warp plan
                var framePlan: CorrectionPlan?
                if validation?.isSafe == true, let face = result.faceGeometry {
                    framePlan = pipeline.process(
                        face: face,
                        strength: correctionStrength,
                        gain: debugGain,
                        method: gazeMethod
                    )
                } else {
                    pipeline.reset()
                    directionSmoother.reset()
                }

                // 4. Correction
                var displayCI = result.ciImage
                if correctionEnabled, let framePlan {
                    displayCI = EyeCorrectionProcessor.apply(framePlan, to: displayCI)
                }

                // 5. Render
                let nsImage = render(displayCI, context: ctx)

                // 6. Publish
                faceObservations    = result.observations
                mediaPipeLandmarks  = result.mediaPipeLandmarks
                landmarkSource      = result.mediaPipeLandmarks != nil ? "MediaPipe (478 pts)" : "Apple Vision"
                frameSize           = result.imageSize
                validationResult    = validation
                plan                = framePlan
                gazeDirection       = framePlan.map { directionSmoother.add($0.direction) }
                processedFrame      = nsImage
            }
        }
    }

    private nonisolated func render(_ ciImage: CIImage, context: CIContext) -> NSImage? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: ciImage.extent.size)
    }
}
