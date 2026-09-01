import CoreGraphics
import Foundation

/// Every tunable constant for the gaze-correction system, in one place.
///
/// Ported from the reference projects (both MIT licensed):
///  - `reference/gaze-corrector/config.py`            (dkohn1337/gaze-corrector)
///  - `reference/deepwarp-cam/model_managers/gaze_corrector_v1.py`
///    (WangWilly/gaze-correction-cam, after Hsu et al., ACM TOMM 15(2), 2019)
///
/// These values are calibrated, not arbitrary. When changing one, record why in
/// `.ai/EXPERIMENTS.md` and update `docs/EYE_CONTACT.md`.
enum CorrectionConfig {

    // MARK: - Gaze estimation

    /// Vertical correction is deliberately halved. A person looking at a screen
    /// naturally sits slightly eyes-down; fully correcting that looks artificial.
    /// This is the single most subtle constant in the system.
    static let verticalDamping: CGFloat = 0.5

    /// Empirical mapping from normalised iris offset magnitude to degrees.
    /// A full-range offset (1.0) is treated as roughly 30° of gaze.
    static let gazeAngleScale: Double = 30.0

    // MARK: - Correction magnitude

    /// Default correction strength. Full correction (1.0) looks artificial on most faces.
    static let defaultStrength: CGFloat = 0.7

    /// Hard cap on per-axis displacement, as a fraction of eye width.
    /// Resolution-independent replacement for the reference's fixed 20 px cap —
    /// a face close to the camera has a wider eye and tolerates a larger shift.
    /// 0.45 leaves room for a hard side glance (iris at the corner needs to travel
    /// roughly a third of the eye width back to centre).
    static let maxShiftFraction: CGFloat = 0.45

    /// ROI padding around the eye bounding box, as a fraction of eye width —
    /// must accommodate the dilated, feathered mask.
    static let roiPadFraction: CGFloat = 0.70

    /// Blend-mask feather radius as a fraction of eye width. The reference uses a fixed
    /// 15 px Gaussian; scaling with eye width keeps it right at any distance.
    static let featherFraction: CGFloat = 0.22

    /// How far the blend mask is grown beyond the eye contour, as a fraction of eye
    /// width. Large enough that the mask holds full weight over an iris sitting at an
    /// eye corner — otherwise the feather band ghosts the original iris there.
    static let maskDilateFraction: CGFloat = 0.20


    // MARK: - Behaviour FSM

    /// Gaze below this angle → re-engage correction.
    static let engageThresholdDeg: Double = 15.0
    /// Gaze above this angle → start disengaging.
    /// The 15–25° gap is the hysteresis band that prevents flicker.
    static let disengageThresholdDeg: Double = 25.0
    /// Head turned more than this → disengage immediately.
    static let headYawThresholdDeg: Double = 20.0
    /// Head tilted more than this → disengage immediately.
    static let headPitchThresholdDeg: Double = 15.0

    /// Fade-out is deliberately twice as slow as fade-in: correction that
    /// vanishes abruptly is noticeable, correction that arrives abruptly is not.
    static let disengageDuration: TimeInterval = 0.4
    static let reEngageDuration: TimeInterval = 0.2

    // MARK: - Smoothing (EMA: value ← α·new + (1−α)·value)

    /// Higher = more responsive, less smooth. Landmarks must stay responsive
    /// or the correction feels laggy.
    static let landmarkAlpha: CGFloat = 0.6
    /// Lower = smoother. The blend factor should move imperceptibly.
    static let blendAlpha: Double = 0.3

    // MARK: - 3D geometry (Method B)

    /// Camera focal length in pixels. Calibrate: place the face ~50 cm away, then
    /// focalLength = ipdPixels × 50 / ipdCm.
    static let defaultFocalLengthPx: CGFloat = 650.0

    /// Inter-pupillary distance in cm — the human average.
    static let defaultIPDcm: CGFloat = 6.3

    /// Camera position relative to screen centre, in cm.
    /// y = −21 means "camera sits 21 cm above the screen centre" — a typical laptop.
    static let defaultCameraOffsetCm = CameraOffset(x: 0, y: -21, z: -1)

    /// Human eyeball radius. Used to convert a gaze angle into an on-image
    /// iris displacement: shift ≈ radius × sin(angle).
    static let eyeballRadiusCm: CGFloat = 1.2

    // MARK: - Validation

    /// Eye aspect ratio of a fully open eye, used to normalise the openness score.
    static let openEyeAspectRatio: CGFloat = 0.30

    struct CameraOffset {
        var x: CGFloat
        var y: CGFloat
        var z: CGFloat
    }
}
