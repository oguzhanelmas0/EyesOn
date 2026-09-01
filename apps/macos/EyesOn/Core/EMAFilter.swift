import CoreGraphics
import Foundation

// Exponential moving average filters.
// Ported from `reference/gaze-corrector/smoothing.py` (MIT).
//
//     value ← α · new + (1 − α) · value
//
// Higher α = more responsive, less smooth.

/// EMA over a scalar.
struct ScalarEMA {
    let alpha: Double
    private var value: Double?

    init(alpha: Double) { self.alpha = alpha }

    mutating func update(_ new: Double) -> Double {
        let next = value.map { alpha * new + (1 - alpha) * $0 } ?? new
        value = next
        return next
    }

    mutating func reset() { value = nil }
    var current: Double? { value }
}

/// EMA over a 2D point.
struct PointEMA {
    let alpha: CGFloat
    private var value: CGPoint?

    init(alpha: CGFloat) { self.alpha = alpha }

    mutating func update(_ new: CGPoint) -> CGPoint {
        guard let old = value else { value = new; return new }
        let next = CGPoint(x: alpha * new.x + (1 - alpha) * old.x,
                           y: alpha * new.y + (1 - alpha) * old.y)
        value = next
        return next
    }

    mutating func reset() { value = nil }
}

/// EMA over a landmark point array.
///
/// Resets automatically when the point count changes — a different count means a
/// different detection, and blending across them would produce nonsense geometry.
struct PointsEMA {
    let alpha: CGFloat
    private var value: [CGPoint]?

    init(alpha: CGFloat) { self.alpha = alpha }

    mutating func update(_ new: [CGPoint]) -> [CGPoint] {
        guard let old = value, old.count == new.count else {
            value = new
            return new
        }
        let next = zip(old, new).map { o, n in
            CGPoint(x: alpha * n.x + (1 - alpha) * o.x,
                    y: alpha * n.y + (1 - alpha) * o.y)
        }
        value = next
        return next
    }

    mutating func reset() { value = nil }
}

/// Smooths every landmark of a face between frames.
///
/// This is what removes the frame-to-frame jitter that makes a correction look alive
/// in a bad way. Applied *before* gaze estimation so the estimate inherits the stability.
struct FaceGeometrySmoother {
    private var leftContour: PointsEMA
    private var rightContour: PointsEMA
    private var leftIris: PointEMA
    private var rightIris: PointEMA
    private var yaw: ScalarEMA
    private var pitch: ScalarEMA
    private var roll: ScalarEMA

    init(alpha: CGFloat = CorrectionConfig.landmarkAlpha) {
        leftContour  = PointsEMA(alpha: alpha)
        rightContour = PointsEMA(alpha: alpha)
        leftIris     = PointEMA(alpha: alpha)
        rightIris    = PointEMA(alpha: alpha)
        yaw   = ScalarEMA(alpha: Double(alpha))
        pitch = ScalarEMA(alpha: Double(alpha))
        roll  = ScalarEMA(alpha: Double(alpha))
    }

    mutating func smooth(_ face: FaceGeometry) -> FaceGeometry {
        let l = EyeGeometry.make(
            contour: leftContour.update(face.leftEye.contour),
            irisCenter: leftIris.update(face.leftEye.irisCenter)
        ) ?? face.leftEye

        let r = EyeGeometry.make(
            contour: rightContour.update(face.rightEye.contour),
            irisCenter: rightIris.update(face.rightEye.irisCenter)
        ) ?? face.rightEye

        let pose = HeadPose(
            yawDeg:   yaw.update(face.headPose.yawDeg),
            pitchDeg: pitch.update(face.headPose.pitchDeg),
            rollDeg:  roll.update(face.headPose.rollDeg)
        )

        return FaceGeometry(leftEye: l, rightEye: r, headPose: pose, imageSize: face.imageSize)
    }

    mutating func reset() {
        leftContour.reset(); rightContour.reset()
        leftIris.reset();    rightIris.reset()
        yaw.reset();         pitch.reset();       roll.reset()
    }
}

extension EyeGeometry {
    /// Builds an eye from a contour, deriving centroid and bounds.
    static func make(contour: [CGPoint], irisCenter: CGPoint) -> EyeGeometry? {
        guard !contour.isEmpty else { return nil }
        let n = CGFloat(contour.count)
        let center = CGPoint(x: contour.reduce(0) { $0 + $1.x } / n,
                             y: contour.reduce(0) { $0 + $1.y } / n)
        let xs = contour.map(\.x), ys = contour.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return EyeGeometry(contour: contour, center: center,
                           irisCenter: irisCenter, bounds: bounds)
    }
}
