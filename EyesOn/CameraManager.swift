import AVFoundation

final class CameraManager: NSObject {

    let captureSession = AVCaptureSession()

    // nonisolated let: safely accessible from any thread or actor
    nonisolated let frameStream: AsyncStream<CMSampleBuffer>
    nonisolated private let frameContinuation: AsyncStream<CMSampleBuffer>.Continuation

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
        // frameContinuation is nonisolated let → safe to call from any thread
        frameContinuation.yield(sampleBuffer)
    }
}
