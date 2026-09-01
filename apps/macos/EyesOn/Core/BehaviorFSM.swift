import Foundation

// Natural-behaviour state machine.
// Ported from `reference/gaze-corrector/behavior_fsm.py` (MIT).
//
// This is the single most important piece for making the product feel natural.
// If the user is genuinely looking at their notes, the correction must withdraw;
// when they come back, it must return smoothly. Forcing permanent eye contact is
// unsettling — worse than not correcting at all.
//
//      gaze near                gaze away
//    ┌──────────┐            ┌──────────────┐
//    │ ENGAGED  │───────────►│ DISENGAGING  │──── 0.4 s ────► ┌────────────┐
//    │ blend=1  │◄───────────│  (fading)    │                 │ DISENGAGED │
//    └──────────┘            └──────────────┘                 │  blend=0   │
//          ▲                                                  └─────┬──────┘
//          │                  ┌──────────────┐                      │
//          └──── 0.2 s ───────│ RE_ENGAGING  │◄──── gaze near ──────┘
//                             │  (fading in) │
//                             └──────────────┘

enum BehaviorState: String {
    case engaged     = "ENGAGED"
    case disengaging = "DISENGAGING"
    case disengaged  = "DISENGAGED"
    case reEngaging  = "RE_ENGAGING"
}

/// Decides *whether* and *how much* correction to apply, based on user behaviour.
///
/// Returns a single number: `blend ∈ [0, 1]`, which scales the correction magnitude.
/// The clock is injected so the transitions can be unit-tested deterministically.
struct BehaviorFSM {

    private(set) var state: BehaviorState = .engaged
    private var transitionStart: TimeInterval = 0

    /// Head turned or tilted far enough that correction is never appropriate.
    private func forcesDisengage(_ pose: HeadPose) -> Bool {
        abs(pose.yawDeg)   > CorrectionConfig.headYawThresholdDeg ||
        abs(pose.pitchDeg) > CorrectionConfig.headPitchThresholdDeg
    }

    private func gazeIsAway(_ angleDeg: Double) -> Bool {
        angleDeg > CorrectionConfig.disengageThresholdDeg
    }

    private func gazeIsNear(_ angleDeg: Double) -> Bool {
        angleDeg < CorrectionConfig.engageThresholdDeg
    }

    /// Advances the machine one frame and returns the blend factor.
    ///
    /// - Parameters:
    ///   - gazeAngleDeg: current gaze deviation from the camera, in degrees
    ///   - pose: current head orientation
    ///   - now: monotonic time (`CACurrentMediaTime()` in the app, injectable in tests)
    mutating func update(gazeAngleDeg: Double, pose: HeadPose, now: TimeInterval) -> Double {
        let forceAway = forcesDisengage(pose)

        switch state {
        case .engaged:
            if forceAway || gazeIsAway(gazeAngleDeg) {
                state = .disengaging
                transitionStart = now
            }
            return 1.0

        case .disengaging:
            let elapsed = now - transitionStart
            if !forceAway && gazeIsNear(gazeAngleDeg) {
                // Came back quickly — snap back to engaged rather than finishing the fade.
                state = .engaged
                return 1.0
            }
            if elapsed >= CorrectionConfig.disengageDuration {
                state = .disengaged
                return 0.0
            }
            return max(0.0, 1.0 - elapsed / CorrectionConfig.disengageDuration)

        case .disengaged:
            if !forceAway && gazeIsNear(gazeAngleDeg) {
                state = .reEngaging
                transitionStart = now
            }
            return 0.0

        case .reEngaging:
            let elapsed = now - transitionStart
            if forceAway || gazeIsAway(gazeAngleDeg) {
                state = .disengaged
                return 0.0
            }
            if elapsed >= CorrectionConfig.reEngageDuration {
                state = .engaged
                return 1.0
            }
            return min(1.0, elapsed / CorrectionConfig.reEngageDuration)
        }
    }

    /// Called when tracking is lost, so the next detection starts clean.
    mutating func reset() {
        state = .engaged
        transitionStart = 0
    }
}
