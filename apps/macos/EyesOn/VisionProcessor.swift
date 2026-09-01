import Vision
import CoreImage

actor VisionProcessor {

    private let requestHandler = VNSequenceRequestHandler()
    private let faceRectanglesRequest = VNDetectFaceRectanglesRequest()
    private let landmarksRequest = VNDetectFaceLandmarksRequest()
    private let onnxLandmarker = ONNXFaceLandmarker()

    struct FrameResult {
        let observations: [VNFaceObservation]
        let mediaPipeLandmarks: [Landmark3D]?
        let faceGeometry: FaceGeometry?
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
            try requestHandler.perform([landmarksRequest, faceRectanglesRequest], on: pixelBuffer, orientation: .up)
        } catch {
            return FrameResult(
                observations: [],
                mediaPipeLandmarks: nil,
                faceGeometry: nil,
                imageSize: imageSize,
                ciImage: ciImage
            )
        }

        let observations = landmarksRequest.results ?? []
        var mediaPipeLandmarks: [Landmark3D]? = nil
        var faceGeometry: FaceGeometry? = nil

        // Run MediaPipe Face Landmarker if face is detected
        if let primaryFace = faceRectanglesRequest.results?.first ?? observations.first {
            let bbox = primaryFace.boundingBox
            // Convert Vision normalized bounding box (origin bottom-left) to CIImage pixel space
            let faceBoxCI = CGRect(
                x: bbox.minX * imageSize.width,
                y: bbox.minY * imageSize.height,
                width: bbox.width * imageSize.width,
                height: bbox.height * imageSize.height
            )

            if let mpPoints = onnxLandmarker?.detectLandmarks(in: ciImage, faceBoxCI: faceBoxCI) {
                mediaPipeLandmarks = mpPoints
                faceGeometry = MediaPipeFaceAdapter.makeFaceGeometry(from: mpPoints, imageSize: imageSize)
            }
        }

        // Fallback to Apple Vision adapter if MediaPipe is unavailable or fails
        if faceGeometry == nil, let obs = observations.first {
            faceGeometry = VisionFaceAdapter.makeFaceGeometry(from: obs, imageSize: imageSize)
        }

        return FrameResult(
            observations: observations,
            mediaPipeLandmarks: mediaPipeLandmarks,
            faceGeometry: faceGeometry,
            imageSize: imageSize,
            ciImage: ciImage
        )
    }
}

