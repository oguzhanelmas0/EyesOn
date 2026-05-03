import Vision
import CoreImage

actor VisionProcessor {

    private let requestHandler = VNSequenceRequestHandler()
    private let landmarksRequest = VNDetectFaceLandmarksRequest()

    struct FrameResult {
        let observations: [VNFaceObservation]
        let imageSize: CGSize
        let ciImage: CIImage          // raw frame for correction pipeline
    }

    func process(pixelBuffer: CVPixelBuffer) -> FrameResult {
        let ciImage   = CIImage(cvPixelBuffer: pixelBuffer)
        let imageSize = CGSize(
            width:  CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        do {
            try requestHandler.perform([landmarksRequest], on: pixelBuffer, orientation: .up)
        } catch {
            return FrameResult(observations: [], imageSize: imageSize, ciImage: ciImage)
        }
        return FrameResult(
            observations: landmarksRequest.results ?? [],
            imageSize: imageSize,
            ciImage: ciImage
        )
    }
}
