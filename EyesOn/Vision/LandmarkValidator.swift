import Vision
import CoreGraphics

// MARK: - Result

struct LandmarkValidationResult {
    let isSafe: Bool
    let rejectionReason: String?

    // Debug values (always populated even on failure)
    let headYawDeg: Double
    let headPitchDeg: Double
    let leftEyeAR: CGFloat      // eye aspect ratio (h/w): 0 = closed, ~0.30 = open
    let rightEyeAR: CGFloat
    let interEyeDist: CGFloat   // in face-box–normalized units

    var debugText: String {
        if let r = rejectionReason { return "✗ \(r)" }
        return String(
            format: "✓ yaw:%.0f° pitch:%.0f° EAR L:%.2f R:%.2f",
            headYawDeg, headPitchDeg, leftEyeAR, rightEyeAR
        )
    }
}

// MARK: - Config

struct LandmarkValidatorConfig {
    /// Face bounding-box minimum width (fraction of image width)
    var minFaceWidth: CGFloat   = 0.10
    /// Max absolute head yaw before correction is suppressed
    var maxYawDeg: Double       = 22.0
    /// Max absolute head pitch
    var maxPitchDeg: Double     = 22.0
    /// Eye Aspect Ratio minimum — below this = squinting / closed
    var minEyeAR: CGFloat       = 0.11
    /// Minimum landmark points per eye
    var minEyePoints: Int       = 6
    /// Minimum inter-eye distance in face-box–normalised units
    var minInterEyeDist: CGFloat = 0.10

    static let `default` = LandmarkValidatorConfig()
}

// MARK: - Validator

struct LandmarkValidator {

    static func validate(
        _ obs: VNFaceObservation,
        config: LandmarkValidatorConfig = .default
    ) -> LandmarkValidationResult {

        guard let landmarks = obs.landmarks else {
            return fail("Landmark yok", yaw: 0, pitch: 0, lAR: 0, rAR: 0, ied: 0)
        }

        // ── 1. Face bounding box size ──────────────────────────────────────
        guard obs.boundingBox.width >= config.minFaceWidth else {
            return fail(
                "Yüz çok küçük (\(Int(obs.boundingBox.width * 100))%)",
                yaw: 0, pitch: 0, lAR: 0, rAR: 0, ied: 0
            )
        }

        // ── 2. Eye landmark point count ────────────────────────────────────
        let leftN  = landmarks.leftEye?.pointCount  ?? 0
        let rightN = landmarks.rightEye?.pointCount ?? 0
        guard leftN >= config.minEyePoints, rightN >= config.minEyePoints else {
            return fail(
                "Landmark yetersiz (L:\(leftN) R:\(rightN))",
                yaw: 0, pitch: 0, lAR: 0, rAR: 0, ied: 0
            )
        }

        // ── 3. Eye aspect ratio (blink / squint) ───────────────────────────
        let lAR = eyeAR(landmarks.leftEye)
        let rAR = eyeAR(landmarks.rightEye)
        guard lAR >= config.minEyeAR, rAR >= config.minEyeAR else {
            return fail(
                "Göz kapalı/kısık (L:\(fmt2(lAR)) R:\(fmt2(rAR)))",
                yaw: 0, pitch: 0, lAR: lAR, rAR: rAR, ied: 0
            )
        }

        // ── 4. Head yaw (Vision provides this directly in radians) ─────────
        let yawDeg   = abs((obs.yaw?.doubleValue   ?? 0) * 180 / .pi)
        let pitchDeg = abs((obs.pitch?.doubleValue ?? 0) * 180 / .pi)

        guard yawDeg <= config.maxYawDeg else {
            return fail(
                "Kafa çok dönük (yaw \(Int(yawDeg))°)",
                yaw: yawDeg, pitch: pitchDeg, lAR: lAR, rAR: rAR, ied: 0
            )
        }
        guard pitchDeg <= config.maxPitchDeg else {
            return fail(
                "Kafa çok eğik (pitch \(Int(pitchDeg))°)",
                yaw: yawDeg, pitch: pitchDeg, lAR: lAR, rAR: rAR, ied: 0
            )
        }

        // ── 5. Inter-eye distance sanity ───────────────────────────────────
        let ied = interEyeDist(landmarks)
        guard ied >= config.minInterEyeDist else {
            return fail(
                "Gözler çok yakın (\(fmt3(ied)))",
                yaw: yawDeg, pitch: pitchDeg, lAR: lAR, rAR: rAR, ied: ied
            )
        }

        // ── All checks passed ──────────────────────────────────────────────
        return LandmarkValidationResult(
            isSafe: true, rejectionReason: nil,
            headYawDeg: yawDeg, headPitchDeg: pitchDeg,
            leftEyeAR: lAR, rightEyeAR: rAR, interEyeDist: ied
        )
    }

    // MARK: - Helpers

    private static func fail(
        _ reason: String,
        yaw: Double, pitch: Double,
        lAR: CGFloat, rAR: CGFloat, ied: CGFloat
    ) -> LandmarkValidationResult {
        LandmarkValidationResult(
            isSafe: false, rejectionReason: reason,
            headYawDeg: yaw, headPitchDeg: pitch,
            leftEyeAR: lAR, rightEyeAR: rAR, interEyeDist: ied
        )
    }

    /// Eye Aspect Ratio = bounding-box height / width of eye landmark points.
    /// Open eye ≈ 0.25–0.35. Closed/squinting < 0.12.
    private static func eyeAR(_ eye: VNFaceLandmarkRegion2D?) -> CGFloat {
        guard let eye, eye.pointCount >= 4 else { return 0 }
        let pts = eye.normalizedPoints
        let w = (pts.map { $0.x }.max()! - pts.map { $0.x }.min()!)
        let h = (pts.map { $0.y }.max()! - pts.map { $0.y }.min()!)
        return w > 0.001 ? h / w : 0
    }

    /// Inter-eye distance in face-box–normalised units (landmark-space).
    private static func interEyeDist(_ lm: VNFaceLandmarks2D) -> CGFloat {
        guard let l = lm.leftEye, let r = lm.rightEye,
              l.pointCount > 0, r.pointCount > 0 else { return 0 }
        let lc = centroid(l.normalizedPoints)
        let rc = centroid(r.normalizedPoints)
        return hypot(rc.x - lc.x, rc.y - lc.y)
    }

    private static func centroid(_ pts: [CGPoint]) -> CGPoint {
        CGPoint(
            x: pts.map { $0.x }.reduce(0, +) / CGFloat(pts.count),
            y: pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count)
        )
    }

    private static func fmt2(_ v: CGFloat) -> String { String(format: "%.2f", v) }
    private static func fmt3(_ v: CGFloat) -> String { String(format: "%.3f", v) }
}
