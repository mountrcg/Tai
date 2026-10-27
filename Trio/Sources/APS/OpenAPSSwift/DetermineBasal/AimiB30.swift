import Foundation

/// Result from the B30 boost-basal evaluation.
struct B30Result {
    /// Whether B30 boost basal is currently active.
    let isActive: Bool
    /// Boosted basal rate (basal × b30Factor, pump-rounded). Only meaningful when isActive.
    let boostRate: Decimal
    /// Minutes remaining in the B30 window. Only meaningful when isActive.
    let remainingMinutes: Decimal
    /// Reason fragment for inclusion in the determination reason string.
    let reason: String
}

/// All dosing-engine values needed to evaluate B30 safety checks.
struct B30SafetyInputs {
    let currentGlucose: Decimal
    let minGuardGlucose: Decimal
    let iob: Decimal
    let minDelta: Decimal
    let expectedDelta: Decimal
    let threshold: Decimal
    let overrideFactor: Decimal
    let adjustedSensitivity: Decimal
    let targetGlucose: Decimal
    let eventualGlucose: Decimal
    let minGlucose: Decimal
    let maxGlucose: Decimal
    let carbsRequired: Decimal
    let naiveEventualGlucose: Decimal
    let glucoseStatus: GlucoseStatus
    let basal: Decimal
    let smbIsEnabled: Bool
    let minForecastGlucose: Decimal
    let maxIob: Decimal
    let currentTemp: TempBasal
    let profile: Profile
    let iobInputs: KetoProtect.IobInputs
}

/// Evaluates whether the autoISF B30 boost-basal should activate for this loop cycle.
///
/// Ported from oref0 determine-basal.js lines 788–848.
/// Activation requires all of:
///   - autoISF and B30 both enabled
///   - Last manual bolus ≥ iTime_Start_Bolus, within b30_duration minutes
///   - EatingSoon temp target active and equal to iTime_target
///   - Current BG < b30_upperBG and delta ≤ b30_upperdelta
enum AimiB30 {
    /// Pre-meal B30 safety guard for the "glucose falling faster than expected" branch in
    /// DosingEngine. With B30 active, IOB is intentionally high while BG is flat or
    /// rising, so the falling-faster branch (which keys off `minDelta < expectedDelta`)
    /// would otherwise fire spuriously and set a low temp. This guard requires `minDelta`
    /// to actually be negative — true "falling" — when B30 / autoISF is in play.
    /// With autoISF off the guard is a no-op.
    static func glucoseActuallyFalling(profile: Profile, minDelta: Decimal) -> Bool {
        guard profile.autoisf else { return true }
        return minDelta < 0
    }

    static func evaluate(
        profile: Profile,
        pumpHistory: [PumpHistoryEvent],
        currentTime: Date,
        targetBG: Decimal,
        currentBG: Decimal,
        bgDelta: Decimal,
        basal: Decimal
    ) -> B30Result {
        let inactive = B30Result(isActive: false, boostRate: basal, remainingMinutes: 0, reason: "")

        guard profile.enableB30, profile.autoisf else { return inactive }

        // Find the most recent manual bolus >= iTime_Start_Bolus (pumpHistory newest-first)
        let minBolus = profile.B30iTimeStartBolus
        var lastBolusAmount: Decimal = 0
        var lastBolusAge: Decimal = profile.B30iTime + 1 // default: outside window

        for event in pumpHistory {
            guard event.type == .bolus, !(event.isSMB ?? false),
                  let amount = event.amount, amount >= minBolus
            else { continue }
            lastBolusAmount = amount
            lastBolusAge = max(1, (Decimal(currentTime.timeIntervalSince(event.timestamp)) / 60).jsRounded(scale: 1))
            break
        }

        let b30Duration = profile.B30iTime
        let temptargetSet = profile.temptargetSet ?? false

        guard lastBolusAmount >= minBolus,
              lastBolusAge <= b30Duration,
              temptargetSet,
              targetBG == profile.B30iTimeTarget
        else { return inactive }

        let remainingMinutes = b30Duration - lastBolusAge

        guard bgDelta <= profile.B30upperDelta, currentBG < profile.B30upperLimit else {
            return B30Result(
                isActive: false,
                boostRate: basal,
                remainingMinutes: remainingMinutes,
                reason: "AIMI B30, cancelled, BG or Delta too high, "
            )
        }

        let rawBoost = basal * profile.B30basalFactor
        let cappedBoost = profile.maxBasal.map { min(rawBoost, $0) } ?? rawBoost
        let boostRate = TempBasalFunctions.roundBasal(profile: profile, basalRate: cappedBoost)
        let reason = " for \(remainingMinutes.jsRounded(scale: 0))m, "

        return B30Result(isActive: true, boostRate: boostRate, remainingMinutes: remainingMinutes, reason: reason)
    }

    /// Runs optional safety checks before the B30 boost activates.
    ///
    /// Progressive order: most critical → least. Set a flag to `true` to re-enforce
    /// that check for B30 (by default all are bypassed, matching JS aimiRateActivated behaviour).
    /// Returns `(suppressed: true, determination)` if a check fires and B30 should not activate.
    static func applySafetyChecks(
        inputs: B30SafetyInputs,
        determination: Determination
    ) throws -> (suppressed: Bool, determination: Determination) {
        // ── B30 safety-check overrides ────────────────────────────────────────────
        // Progressive order: most critical → least. Set `true` to re-enforce for B30.
        let enforce1ZeroTempSuspend = false // not enforced for B30: BG or minGuardBG < threshold → zero temp
        let enforce2LowEventualBG = false // not enforced for B30: eventualBG < min target → reduce/zero basal
        let enforce3GlucoseFallingFast = false // not enforced for B30: BG falling faster than expected
        let enforce4EventualForecastLow = false // not enforced for B30: eventual/forecast BG < max target
        let enforce5IobCap = false // not enforced for B30: IOB > maxIOB

        var det = determination

        debug(
            .algorithm,
            "B30 safety checks: BG \(inputs.currentGlucose) mg/dL, min guard BG \(inputs.minGuardGlucose) mg/dL, threshold \(inputs.threshold) mg/dL, eventual BG \(inputs.eventualGlucose) mg/dL, min BG \(inputs.minGlucose) mg/dL, min delta \(inputs.minDelta) mg/dL, expected delta \(inputs.expectedDelta) mg/dL, IOB \(inputs.iob) U"
        )

        if enforce1ZeroTempSuspend {
            let (fires, d) = try DosingEngine.lowGlucoseSuspend(
                currentGlucose: inputs.currentGlucose,
                minGuardGlucose: inputs.minGuardGlucose,
                iob: inputs.iob,
                minDelta: inputs.minDelta,
                expectedDelta: inputs.expectedDelta,
                threshold: inputs.threshold,
                overrideFactor: inputs.overrideFactor,
                profile: inputs.profile,
                adjustedSensitivity: inputs.adjustedSensitivity,
                targetGlucose: inputs.targetGlucose,
                currentTemp: inputs.currentTemp,
                determination: det,
                iobInputs: inputs.iobInputs
            )
            debug(.algorithm, "B30 zero temp suspend check \(fires ? "blocks" : "passes")")
            if fires {
                return (true, applyBlockedTag(d, blocker: "zeroTempSuspend"))
            }
            det = d
        }

        if enforce2LowEventualBG {
            let (fires, d) = try DosingEngine.handleLowEventualGlucose(
                eventualGlucose: inputs.eventualGlucose,
                minGlucose: inputs.minGlucose,
                targetGlucose: inputs.targetGlucose,
                minDelta: inputs.minDelta,
                expectedDelta: inputs.expectedDelta,
                carbsRequired: inputs.carbsRequired,
                naiveEventualGlucose: inputs.naiveEventualGlucose,
                glucoseStatus: inputs.glucoseStatus,
                currentTemp: inputs.currentTemp,
                basal: inputs.basal,
                profile: inputs.profile,
                determination: det,
                adjustedSensitivity: inputs.adjustedSensitivity,
                overrideFactor: inputs.overrideFactor,
                iobInputs: inputs.iobInputs
            )
            debug(.algorithm, "B30 low eventual BG check \(fires ? "blocks" : "passes")")
            if fires {
                return (true, applyBlockedTag(d, blocker: "lowEventualBG"))
            }
            det = d
        }

        if enforce3GlucoseFallingFast {
            let (fires, d) = try DosingEngine.glucoseFallingFasterThanExpected(
                eventualGlucose: inputs.eventualGlucose,
                minGlucose: inputs.minGlucose,
                minDelta: inputs.minDelta,
                expectedDelta: inputs.expectedDelta,
                glucoseStatus: inputs.glucoseStatus,
                currentTemp: inputs.currentTemp,
                basal: inputs.basal,
                smbIsEnabled: inputs.smbIsEnabled,
                profile: inputs.profile,
                determination: det,
                iobInputs: inputs.iobInputs
            )
            debug(.algorithm, "B30 falling glucose check \(fires ? "blocks" : "passes")")
            if fires {
                return (true, applyBlockedTag(d, blocker: "glucoseFallingFast"))
            }
            det = d
        }

        if enforce4EventualForecastLow {
            let (fires, d) = try DosingEngine.eventualOrForecastGlucoseLessThanMax(
                eventualGlucose: inputs.eventualGlucose,
                maxGlucose: inputs.maxGlucose,
                minForecastGlucose: inputs.minForecastGlucose,
                currentTemp: inputs.currentTemp,
                basal: inputs.basal,
                smbIsEnabled: inputs.smbIsEnabled,
                profile: inputs.profile,
                determination: det,
                iobInputs: inputs.iobInputs
            )
            debug(.algorithm, "B30 low eventual forecast check \(fires ? "blocks" : "passes")")
            if fires { return (true, d) }
            det = d
        }

        if enforce5IobCap {
            let (fires, d) = try DosingEngine.iobGreaterThanMax(
                iob: inputs.iob,
                maxIob: inputs.maxIob,
                currentTemp: inputs.currentTemp,
                basal: inputs.basal,
                profile: inputs.profile,
                determination: det,
                iobInputs: inputs.iobInputs
            )
            debug(.algorithm, "B30 IOB cap check \(fires ? "blocks" : "passes")")
            if fires { return (true, d) }
            det = d
        }

        debug(.algorithm, "B30 safety checks passed, boost will activate")
        return (false, det)
    }

    /// Prepends `AIMI B30, blocked by <name>, ` to the reason and strips the now-stale
    /// `SMB disabled:, B30 running` fragment (AutoISFsmb added it optimistically before
    /// safeguards ran — if they block, B30 isn't actually running, so the SMB-off tag
    /// doesn't belong). "AIMI B30" matches the existing exact-match rule in TagCloudView.
    private static func applyBlockedTag(_ determination: Determination, blocker: String) -> Determination {
        var blocked = determination
        var reason = blocked.reason
        reason = reason.replacingOccurrences(of: "SMB disabled:, B30 running, ", with: "")
        reason = reason.replacingOccurrences(of: "SMB disabled:, B30 running", with: "")
        blocked.reason = "AIMI B30, blocked by \(blocker), " + reason
        return blocked
    }
}
