import AppKit
import AVFoundation
import Combine
import CoreImage
import Metal
import Vision

final class CameraViewModel: ObservableObject {

    enum CameraState {
        case loading, running, denied, unavailable
    }

    @Published var cameraState: CameraState              = .loading
    @Published var faceObservations: [VNFaceObservation]  = []
    @Published var frameSize: CGSize                     = .zero
    @Published var gazeDirection: GazeDirection?
    @Published var processedFrame: NSImage?
    @Published var correctionEnabled: Bool               = true
    @Published var validationResult: LandmarkValidationResult?

    private let manager          = CameraManager()
    private let visionProcessor  = VisionProcessor()
    private var processingTask: Task<Void, Never>?
    private var directionSmoother = GazeSmoother(size: 6)

    private let ciContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() { return CIContext(mtlDevice: device) }
        return CIContext()
    }()

    var captureSession: AVCaptureSession { manager.captureSession }

    var isCorrecting: Bool {
        correctionEnabled
            && (validationResult?.isSafe == true)
            && (gazeDirection ?? .center) != .center
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

    // MARK: - Permission

    private func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor [weak self] in
                if granted { self?.launchCamera() } else { self?.cameraState = .denied }
            }
        }
    }

    // MARK: - Pipeline

    private func launchCamera() {
        manager.setup()
        guard manager.hasCamera else { cameraState = .unavailable; return }
        cameraState = .running
        manager.startSession()
        startFrameProcessing()
    }

    private func startFrameProcessing() {
        let stream    = manager.frameStream
        let processor = visionProcessor
        let ctx       = ciContext

        processingTask = Task {
            for await sampleBuffer in stream {
                guard !Task.isCancelled else { break }
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

                // 1. Vision — background thread via actor
                let result = await processor.process(pixelBuffer: pixelBuffer)

                // 2. Landmark validation — gates all correction
                let validation = result.observations.first.map { LandmarkValidator.validate($0) }

                // 3. Gaze estimate — continuous offset + discrete direction
                let gazeEstimate: GazeEstimate?
                if validation?.isSafe == true {
                    gazeEstimate = result.observations.first.flatMap { GazeEstimator.estimate(from: $0) }
                } else {
                    gazeEstimate = nil
                }

                // 4. Smooth discrete direction for UI display
                let smoothedDirection: GazeDirection?
                if let est = gazeEstimate {
                    smoothedDirection = directionSmoother.add(est.direction)
                } else {
                    directionSmoother.reset()
                    smoothedDirection = nil
                }

                // 5. Eye correction — uses continuous rawOffset for proportional shift
                var displayCI = result.ciImage
                if correctionEnabled,
                   let obs   = result.observations.first,
                   let valid = validation,
                   let est   = gazeEstimate,
                   est.direction != .center {
                    displayCI = EyeCorrectionProcessor.correct(
                        image: displayCI,
                        observation: obs,
                        gazeEstimate: est,
                        validation: valid
                    )
                }

                // 6. Render → NSImage
                let nsImage = render(displayCI, context: ctx)

                // 7. Publish
                faceObservations = result.observations
                frameSize        = result.imageSize
                gazeDirection    = smoothedDirection
                validationResult = validation
                processedFrame   = nsImage
            }
        }
    }

    private func render(_ ciImage: CIImage, context: CIContext) -> NSImage? {
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: ciImage.extent.size)
    }
}
