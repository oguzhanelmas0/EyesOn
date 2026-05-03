import AVFoundation
import Combine
import Vision

final class CameraViewModel: ObservableObject {

    enum CameraState {
        case loading, running, denied, unavailable
    }

    @Published var cameraState: CameraState = .loading
    @Published var faceObservations: [VNFaceObservation] = []
    @Published var frameSize: CGSize = .zero

    private let manager = CameraManager()
    private let visionProcessor = VisionProcessor()
    private var processingTask: Task<Void, Never>?

    var captureSession: AVCaptureSession { manager.captureSession }

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

    // MARK: - Camera + Vision Pipeline

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

        processingTask = Task {
            for await sampleBuffer in stream {
                guard !Task.isCancelled else { break }
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { continue }

                // Suspends main actor → Vision actor processes on background thread
                let result = await processor.process(pixelBuffer: pixelBuffer)

                // Resume on main actor to publish results
                faceObservations = result.observations
                frameSize        = result.imageSize
            }
        }
    }
}
