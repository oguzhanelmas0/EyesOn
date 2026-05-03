import Vision
import CoreGraphics

// MARK: - GazeDirection

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

// MARK: - GazeEstimate

/// Combines the discrete direction (for UI) with the continuous raw offset (for correction).
struct GazeEstimate {
    let direction: GazeDirection

    /// Pupil displacement from eye centroid, in eye-width-normalised units.
    /// dx > 0: pupil is RIGHT of centroid → person looking LEFT.
    /// dy > 0: pupil is above centroid   → person looking UP.
    let rawOffset: CGPoint
}

// MARK: - GazeEstimator

struct GazeEstimator {

    // ── Tuning ────────────────────────────────────────────────────────────
    static let xThreshold: CGFloat = 0.10
    static let yThreshold: CGFloat = 0.08
    static let minEyeOpen: CGFloat = 0.35
    // ──────────────────────────────────────────────────────────────────────

    static func estimate(from observation: VNFaceObservation) -> GazeEstimate? {
        guard let landmarks = observation.landmarks else { return nil }

        let leftOff  = eyeOffset(pupil: landmarks.leftPupil,  eye: landmarks.leftEye)
        let rightOff = eyeOffset(pupil: landmarks.rightPupil, eye: landmarks.rightEye)

        let available = [leftOff, rightOff].compactMap { $0 }
        guard !available.isEmpty else { return nil }

        let avgX = available.map { $0.x }.reduce(0, +) / CGFloat(available.count)
        let avgY = available.map { $0.y }.reduce(0, +) / CGFloat(available.count)

        let openness = (aspectOpenness(landmarks.leftEye) + aspectOpenness(landmarks.rightEye)) / 2.0
        let direction = classify(dx: avgX, dy: avgY, eyeOpenness: openness)

        return GazeEstimate(direction: direction, rawOffset: CGPoint(x: avgX, y: avgY))
    }

    // MARK: - Private

    private static func aspectOpenness(_ eye: VNFaceLandmarkRegion2D?) -> CGFloat {
        guard let eye, eye.pointCount > 0 else { return 1.0 }
        let pts = eye.normalizedPoints
        let h = (pts.map { $0.y }.max()! - pts.map { $0.y }.min()!)
        let w = (pts.map { $0.x }.max()! - pts.map { $0.x }.min()!)
        guard w > 0.001 else { return 1.0 }
        return min(h / w / 0.30, 1.0)
    }

    private static func eyeOffset(
        pupil: VNFaceLandmarkRegion2D?,
        eye:   VNFaceLandmarkRegion2D?
    ) -> CGPoint? {
        guard let eye, eye.pointCount > 0 else { return nil }
        guard let pupil, pupil.pointCount > 0 else { return nil }

        let eyePts = eye.normalizedPoints
        let cx = eyePts.map { $0.x }.reduce(0, +) / CGFloat(eyePts.count)
        let cy = eyePts.map { $0.y }.reduce(0, +) / CGFloat(eyePts.count)
        let minX = eyePts.map { $0.x }.min()!
        let maxX = eyePts.map { $0.x }.max()!
        let eyeWidth = maxX - minX
        guard eyeWidth > 0.005 else { return nil }

        let pts = pupil.normalizedPoints
        let px  = pts.map { $0.x }.reduce(0, +) / CGFloat(pts.count)
        let py  = pts.map { $0.y }.reduce(0, +) / CGFloat(pts.count)

        return CGPoint(x: (px - cx) / eyeWidth,
                       y: (py - cy) / eyeWidth)
    }

    private static func classify(dx: CGFloat, dy: CGFloat, eyeOpenness: CGFloat) -> GazeDirection {
        let absX = abs(dx)
        let absY = abs(dy)

        if absY > yThreshold && absY >= absX {
            if dy > 0 {
                return eyeOpenness > minEyeOpen ? .up : .center
            } else {
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

struct GazeSmoother {
    private var buffer: [GazeDirection] = []
    private let size: Int

    init(size: Int = 6) { self.size = size }

    mutating func add(_ direction: GazeDirection) -> GazeDirection {
        buffer.append(direction)
        if buffer.count > size { buffer.removeFirst() }
        return Dictionary(grouping: buffer, by: { $0 })
            .max(by: { $0.value.count < $1.value.count })?.key ?? direction
    }

    mutating func reset() { buffer.removeAll() }
}
