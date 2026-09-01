import CoreGraphics

/// Adapts 478 MediaPipe Face Landmarker points into the source-agnostic `FaceGeometry` model.
struct MediaPipeFaceAdapter {

    // MARK: - MediaPipe Landmark Indices

    /// Viewer-left eye contour (Subject Right Eye in standard MediaPipe Mesh)
    static let viewerLeftEyeContourIndices = [
        33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161, 246
    ]

    /// Viewer-right eye contour (Subject Left Eye in standard MediaPipe Mesh)
    static let viewerRightEyeContourIndices = [
        362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385, 384, 398
    ]

    /// The six eye landmarks DeepWarp's anchor map expects, in model order.
    ///
    /// These are the MediaPipe equivalents of the dlib-68 eye points the model was
    /// trained on (`reference/deepwarp-cam/displayers/face_predictor.py`).
    /// Indices 0 and 3 are the inner/outer corners — the anchor-map builder derives
    /// the eye width from them, so the order matters.
    static let viewerLeftAnchorIndices  = [33, 160, 158, 133, 153, 144]
    static let viewerRightAnchorIndices = [362, 385, 387, 263, 373, 380]

    /// Viewer-left iris indices: center 468, boundary 469, 470, 471, 472
    static let viewerLeftIrisCenterIndex = 468
    static let viewerLeftIrisIndices = [468, 469, 470, 471, 472]

    /// Viewer-right iris indices: center 473, boundary 474, 475, 476, 477
    static let viewerRightIrisCenterIndex = 473
    static let viewerRightIrisIndices = [473, 474, 475, 476, 477]

    // MARK: - FaceGeometry Factory

    /// Converts 478 3D MediaPipe landmarks into `FaceGeometry`.
    ///
    /// - Parameters:
    ///   - landmarks: 478 `Landmark3D` points in CIImage pixel coordinates.
    ///   - imageSize: Full frame size.
    /// - Returns: Valid `FaceGeometry` or `nil` if landmark count is insufficient.
    static func makeFaceGeometry(
        from landmarks: [Landmark3D],
        imageSize: CGSize
    ) -> FaceGeometry? {
        guard landmarks.count >= 478 else { return nil }

        // Build eye A (viewer-left)
        let eyeAContour = viewerLeftEyeContourIndices.compactMap { idx in
            idx < landmarks.count ? landmarks[idx].cgPoint : nil
        }
        let eyeAIrisCenter = landmarks[viewerLeftIrisCenterIndex].cgPoint
        let eyeAAnchors = viewerLeftAnchorIndices.compactMap { idx in
            idx < landmarks.count ? landmarks[idx].cgPoint : nil
        }
        let eyeA = makeEyeGeometry(contour: eyeAContour, irisCenter: eyeAIrisCenter,
                                   anchorPoints: eyeAAnchors)

        // Build eye B (viewer-right)
        let eyeBContour = viewerRightEyeContourIndices.compactMap { idx in
            idx < landmarks.count ? landmarks[idx].cgPoint : nil
        }
        let eyeBIrisCenter = landmarks[viewerRightIrisCenterIndex].cgPoint
        let eyeBAnchors = viewerRightAnchorIndices.compactMap { idx in
            idx < landmarks.count ? landmarks[idx].cgPoint : nil
        }
        let eyeB = makeEyeGeometry(contour: eyeBContour, irisCenter: eyeBIrisCenter,
                                   anchorPoints: eyeBAnchors)

        guard let validEyeA = eyeA, let validEyeB = eyeB else { return nil }

        // Ensure leftEye is always image-left (smaller x) and rightEye is image-right
        let leftEye: EyeGeometry
        let rightEye: EyeGeometry
        if validEyeA.center.x <= validEyeB.center.x {
            leftEye = validEyeA
            rightEye = validEyeB
        } else {
            leftEye = validEyeB
            rightEye = validEyeA
        }

        let headPose = estimateHeadPose(from: landmarks, imageSize: imageSize)

        return FaceGeometry(
            leftEye: leftEye,
            rightEye: rightEye,
            headPose: headPose,
            imageSize: imageSize
        )
    }

    private static func makeEyeGeometry(contour: [CGPoint],
                                        irisCenter: CGPoint,
                                        anchorPoints: [CGPoint] = []) -> EyeGeometry? {
        guard !contour.isEmpty else { return nil }

        var minX = contour[0].x, maxX = contour[0].x
        var minY = contour[0].y, maxY = contour[0].y
        var sumX: CGFloat = 0, sumY: CGFloat = 0

        for pt in contour {
            minX = min(minX, pt.x); maxX = max(maxX, pt.x)
            minY = min(minY, pt.y); maxY = max(maxY, pt.y)
            sumX += pt.x; sumY += pt.y
        }

        let count = CGFloat(contour.count)
        let center = CGPoint(x: sumX / count, y: sumY / count)
        let bounds = CGRect(x: minX, y: minY, width: max(maxX - minX, 1), height: max(maxY - minY, 1))

        return EyeGeometry(
            contour: contour,
            center: center,
            irisCenter: irisCenter,
            bounds: bounds,
            anchorPoints: anchorPoints
        )
    }

    /// Estimates head pose (yaw, pitch, roll in degrees) from 3D facial landmarks.
    private static func estimateHeadPose(from landmarks: [Landmark3D], imageSize: CGSize) -> HeadPose {
        // Key points:
        // 1: Nose tip
        // 199: Chin
        // 33: Viewer left eye outer corner
        // 263: Viewer right eye outer corner
        // 61: Left mouth corner
        // 291: Right mouth corner
        guard landmarks.count >= 292 else { return .zero }

        let nose = landmarks[1]
        let leftEyeCorner = landmarks[33]
        let rightEyeCorner = landmarks[263]
        let chin = landmarks[199]

        // 1. Roll: angle of the line connecting eye corners
        let dX = rightEyeCorner.x - leftEyeCorner.x
        let dY = rightEyeCorner.y - leftEyeCorner.y
        let rollRad = atan2(dY, dX)
        let rollDeg = Double(rollRad * 180.0 / .pi)

        // 2. Yaw: asymmetry of nose x relative to eye corners midpoint
        let eyesMidX = (leftEyeCorner.x + rightEyeCorner.x) * 0.5
        let eyeSpan = max(abs(rightEyeCorner.x - leftEyeCorner.x), 1.0)
        let noseOffsetRatio = (nose.x - eyesMidX) / eyeSpan
        // Calibrated factor: 0.25 offset ratio ≈ 25 degrees yaw
        let yawDeg = Double(-noseOffsetRatio * 90.0)

        // 3. Pitch: vertical position of nose relative to eyes and chin
        let eyesMidY = (leftEyeCorner.y + rightEyeCorner.y) * 0.5
        let totalFaceHeight = max(abs(eyesMidY - chin.y), 1.0)
        let noseHeightRatio = (eyesMidY - nose.y) / totalFaceHeight
        // Natural neutral noseHeightRatio is around ~0.40
        let pitchOffset = noseHeightRatio - 0.40
        let pitchDeg = Double(pitchOffset * 90.0)

        return HeadPose(
            yawDeg: min(max(yawDeg, -45.0), 45.0),
            pitchDeg: min(max(pitchDeg, -45.0), 45.0),
            rollDeg: min(max(rollDeg, -45.0), 45.0)
        )
    }
}
