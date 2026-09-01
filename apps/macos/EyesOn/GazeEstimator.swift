import CoreGraphics

// MARK: - GazeDirection

/// Discrete gaze direction, used only for the on-screen indicator.
/// The correction itself uses the continuous vectors from `GazePipeline`.
///
/// Directions are in camera/image space (non-mirrored, viewer's perspective).
enum GazeDirection: Equatable {
    case center
    case left    // person looking to their left  (iris shifts right in the image)
    case right   // person looking to their right (iris shifts left in the image)
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

/// Classifies a continuous iris offset into a discrete direction for the UI.
///
/// The measurement itself now lives in `Core/IrisGazeEstimator.swift`, which works on
/// the landmark-source-agnostic `FaceGeometry` rather than on Vision types directly.
enum GazeEstimator {

    static let xThreshold: CGFloat = 0.10
    static let yThreshold: CGFloat = 0.08
    static let minEyeOpen: CGFloat = 0.35

    /// - Parameters:
    ///   - dx: normalised horizontal iris offset; > 0 means the iris sits right of centre
    ///   - dy: normalised vertical iris offset (CIImage space, y up); > 0 means above centre
    ///   - eyeOpenness: 0…1, used to suppress a false "up" reading on a squinting eye
    static func classify(dx: CGFloat, dy: CGFloat, eyeOpenness: CGFloat) -> GazeDirection {
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

/// Majority filter over the last N discrete directions.
///
/// Kept for the UI indicator only. The correction path uses EMA smoothing on
/// continuous values instead — see `Core/EMAFilter.swift`.
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
