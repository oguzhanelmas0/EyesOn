import AVFoundation

final class CameraManager: NSObject {

    let captureSession = AVCaptureSession()

    // CameraManager is not actor-isolated, so these are reachable from the capture
    // queue and from the main actor alike. Marking them `nonisolated` was a no-op that
    // Swift 6 rejects outright, since AsyncStream is not Sendable.
    let frameStream: AsyncStream<CMSampleBuffer>
    private let frameContinuation: AsyncStream<CMSampleBuffer>.Continuation

    private let videoOutput = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "com.eyeson.capture", qos: .userInitiated)

    override init() {
        let (stream, continuation) = AsyncStream<CMSampleBuffer>.makeStream(
            bufferingPolicy: .bufferingNewest(1)  // drop old frames if Vision is slow
        )
        frameStream = stream
        frameContinuation = continuation
        super.init()
    }

    // MARK: - Setup

    func setup() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .hd1280x720
        addVideoInput()
        addVideoOutput()
        captureSession.commitConfiguration()
    }

    private func addVideoInput() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else { return }
        captureSession.addInput(input)
    }

    private func addVideoOutput() {
        // Pin the pixel format explicitly. Left unset, AVFoundation picks its own
        // (typically biplanar YCbCr), which every downstream stage then has to guess at.
        // Core Image's warp kernels want a plain RGB buffer.
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        guard captureSession.canAddOutput(videoOutput) else { return }
        captureSession.addOutput(videoOutput)
    }

    // MARK: - Session Control

    func startSession() {
        let session = captureSession
        Task.detached(priority: .userInitiated) {
            session.startRunning()
        }
    }

    func stopSession() {
        let session = captureSession
        Task.detached(priority: .userInitiated) {
            session.stopRunning()
        }
    }

    var hasCamera: Bool { !captureSession.inputs.isEmpty }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Called on the capture queue; the continuation is thread-safe by contract.
        frameContinuation.yield(sampleBuffer)
    }
}
