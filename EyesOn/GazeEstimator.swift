import Vision
import CoreGraphics

// Gaze direction in camera/image space (viewer's perspective, non-mirrored)
enum GazeDirection: Equatable {
    case center
    case left    // person looking to their left  (pupils shift right in image)
    case right   // person looking to their right (pupils shift left in image)
    case up
    case down

    var label: String {
        switch self {
        case .center: "Merkez"
        case .left:   "Sol"
        case .right:  "Sağ"
        case .up:     "Yukarı"
        case .down:   "Aşağı"
        }
    }

    var arrow: String {
        switch self {
        case .center: "⦿"
        case .left:   "←"
        case .right:  "→"
        case .up:     "↑"
        case .down:   "↓"
        }
    }

    var offset: CGPoint {
        switch self {
        case .center: CGPoint(x:  0.0, y:  0.0)
        case .left:   CGPoint(x: -1.0, y:  0.0)
        case .right:  CGPoint(x:  1.0, y:  0.0)
        case .up:     CGPoint(x:  0.0, y: -1.0)
        case .down:   CGPoint(x:  0.0, y:  1.0)
        }
    }
}

// MARK: - GazeEstimator

struct GazeEstimator {

    // ── Tuning ────────────────────────────────────────────────────────────
    // Offsets are expressed as a fraction of eye WIDTH (same scale for both axes)
    static let xThreshold: CGFloat  = 0.10   // raise if too sensitive laterally
    static let yThreshold: CGFloat  = 0.08   // raise if too many false up/down
    static let minEyeOpen: CGFloat  = 0.35   // suppress vertical when squinting
    // ──────────────────────────────────────────────────────────────────────

    static func estimate(from observation: VNFaceObservation) -> GazeDirection? {
        guard let landmarks = observation.landmarks else { return nil }

        let leftOff  = eyeOffset(pupil: landmarks.leftPupil,  eye: landmarks.leftEye)
        let rightOff = eyeOffset(pupil: landmarks.rightPupil, eye: landmarks.rightEye)

        let available = [leftOff, rightOff].compactMap { $0 }
        guard !available.isEmpty else { return nil }

        let avgX = available.map { $0.x }.reduce(0, +) / CGFloat(available.count)
        let avgY = available.map { $0.y }.reduce(0, +) / CGFloat(available.count)

        // Compute eye openness from landmark geometry (h/w aspect ratio)
        // VNFaceObservation has no leftEyeOpenness — that's ARKit only
        let openness = (aspectOpenness(landmarks.leftEye) + aspectOpenness(landmarks.rightEye)) / 2.0

        return classify(dx: avgX, dy: avgY, eyeOpenness: openness)
    }

    // Estimates openness [0,1] from eye height/width ratio.
    // Open eye h/w ≈ 0.30; squinting h/w < 0.15
    private static func aspectOpenness(_ eye: VNFaceLandmarkRegion2D?) -> CGFloat {
        guard let eye, eye.pointCount > 0 else { return 1.0 }
        let pts = eye.normalizedPoints
        let h = (pts.map { $0.y }.max()! - pts.map { $0.y }.min()!)
        let w = (pts.map { $0.x }.max()! - pts.map { $0.x }.min()!)
        guard w > 0.001 else { return 1.0 }
        return min(h / w / 0.30, 1.0)   // normalise: 1.0 = fully open
    }

    // Returns pupil offset from eye centroid, normalised by eye WIDTH.
    // Using the same denominator for both axes prevents Y over-amplification
    // (eye height << eye width → dividing by height exaggerates vertical).
    private static func eyeOffset(
        pupil: VNFaceLandmarkRegion2D?,
        eye:   VNFaceLandmarkRegion2D?
    ) -> CGPoint? {
        guard let eye, eye.pointCount > 0 else { return nil }
        guard let pupil, pupil.pointCount > 0 else { return nil }  // no fallback to centroid

        let eyePts = eye.normalizedPoints

        // Eye centroid (more stable than bounding-box centre)
        let cx = eyePts.map { $0.x }.reduce(0, +) / CGFloat(eyePts.count)
        let cy = eyePts.map { $0.y }.reduce(0, +) / CGFloat(eyePts.count)

        // Eye width (stable even when eye is squinting)
        let minX = eyePts.map { $0.x }.min()!
        let maxX = eyePts.map { $0.x }.max()!
        let eyeWidth = maxX - minX
        guard eyeWidth > 0.005 else { return nil }

        let pts = pupil.normalizedPoints
        let px  = pts.map { $0.x }.reduce(0, +) / CGFloat(pts.count)
        let py  = pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count)

        // Both axes normalised by eye WIDTH → same scale
        return CGPoint(x: (px - cx) / eyeWidth,
                       y: (py - cy) / eyeWidth)
    }

    // dx > 0 → pupil right in image → person looking LEFT  (non-mirrored camera)
    // dy > 0 → pupil up in Vision   → person looking UP
    private static func classify(dx: CGFloat, dy: CGFloat, eyeOpenness: CGFloat) -> GazeDirection {
        let absX = abs(dx)
        let absY = abs(dy)

        if absY > yThreshold && absY >= absX {
            if dy > 0 {
                // UP: gate with openness — squinting looks identical to looking up
                return eyeOpenness > minEyeOpen ? .up : .center
            } else {
                // DOWN: upper lid droops naturally when looking down → do NOT gate
                return .down
            }
        } else if absX > xThreshold {
            return dx > 0 ? .left : .right
        } else {
            return .center
        }
    }
}

// MARK: - GazeSmoother

// Sliding-window mode filter — returns the most frequent direction
// in the last `size` frames to reduce jitter.
struct GazeSmoother {
    private var buffer: [GazeDirection] = []
    private let size: Int

    init(size: Int = 6) { self.size = size }

    mutating func add(_ direction: GazeDirection) -> GazeDirection {
        buffer.append(direction)
        if buffer.count > size { buffer.removeFirst() }

        return Dictionary(grouping: buffer, by: { $0 })
            .max(by: { $0.value.count < $1.value.count })?
            .key ?? direction
    }

    mutating func reset() { buffer.removeAll() }
}
