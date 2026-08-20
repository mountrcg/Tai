import Foundation

enum TempBasalFunctionError: LocalizedError, Equatable {
    case invalidBasalRateOnProfile

    var errorDescription: String? {
        switch self {
        case .invalidBasalRateOnProfile:
            return "The currentBasal, maxBasal, or maxDailyBasal wasn't set on Profile"
        }
    }
}

enum TempBasalFunctions {
    /// Rounds basal rates to match the basal increment for the pump as the basal rate increases.
    /// Rounds basal rates to the increment the pump delivers in. Diverges from JS
    /// `round-basal.js`, which hardcodes 20 and forces 40 for Medtronic x23/x54: that constant is
    /// in pump units, while the rate here is in U100 units, so it only holds at U100.
    /// `bolus_increment` already carries the concentration, and for an x23/x54 it resolves to 40
    /// at U100 anyway.
    static func roundBasal(profile: Profile, basalRate: Decimal) -> Decimal {
        var lowestRateScale: Decimal = 20
        if profile.bolusIncrement > 0 {
            lowestRateScale = 1 / profile.bolusIncrement
        }

        let roundedBasal: Decimal
        if basalRate < 1 {
            roundedBasal = (basalRate * lowestRateScale).jsRounded() / lowestRateScale
        } else if basalRate < 10 {
            roundedBasal = (basalRate * 20).jsRounded() / 20
        } else {
            roundedBasal = (basalRate * 10).jsRounded() / 10
        }

        return roundedBasal
    }

    /// defines the max safe basal rate given a profile
    static func getMaxSafeBasalRate(profile: Profile) throws -> Decimal {
        // use default values if either of these are NaN
        let maxDailySafetyMultiplier = profile.maxDailySafetyMultiplier.isNaN ? 3 : profile.maxDailySafetyMultiplier
        let currentBasalSafetyMultiplier = profile.currentBasalSafetyMultiplier.isNaN ? 4 : profile.currentBasalSafetyMultiplier

        guard let currentBasal = profile.currentBasal, let maxDailyBasal = profile.maxDailyBasal,
              let maxBasal = profile.maxBasal
        else {
            throw TempBasalFunctionError.invalidBasalRateOnProfile
        }

        return min(
            maxBasal,
            maxDailySafetyMultiplier * maxDailyBasal,
            currentBasalSafetyMultiplier * currentBasal
        )
    }

    static func setTempBasal(
        rate: Decimal,
        duration: Decimal,
        profile: Profile,
        determination: Determination,
        currentTemp: TempBasal,
        iobInputs: KetoProtect.IobInputs = .empty
    ) throws -> Determination {
        var determination = determination
        let maxSafeBasal = try getMaxSafeBasalRate(profile: profile)

        var rate = rate
        if rate < 0 {
            rate = 0
        } else if rate > maxSafeBasal {
            rate = maxSafeBasal
        }

        var suggestedRate = roundBasal(profile: profile, basalRate: rate)

        let keto = KetoProtect.apply(
            rate: suggestedRate,
            profile: profile,
            iobInputs: iobInputs
        )
        suggestedRate = keto.rate
        if !keto.reason.isEmpty {
            determination.reason = keto.reason + determination.reason
        }

        if Decimal(currentTemp.duration) > (duration - 10),
           currentTemp.duration <= 120,
           suggestedRate <= currentTemp.rate * 1.2,
           suggestedRate >= currentTemp.rate * 0.8,
           duration > 0
        {
            determination
                .reason += " \(currentTemp.duration)m left and \(currentTemp.rate) ~ req \(suggestedRate)U/hr: no temp required"
            return determination
        }

        if suggestedRate == profile.currentBasal {
            if profile.skipNeutralTemps {
                if currentTemp.duration > 0 {
                    determination
                        .reason = determination.reason +
                        ". Suggested rate is same as profile rate, a temp basal is active, canceling current temp"
                    determination.duration = 0
                    determination.rate = 0
                    return determination
                } else {
                    determination
                        .reason = determination.reason +
                        ". Suggested rate is same as profile rate, no temp basal is active, doing nothing"
                    return determination
                }
            } else {
                determination.reason = determination.reason + ". Setting neutral temp basal of \(profile.currentBasal ?? 0)U/hr"
                determination.duration = duration
                determination.rate = suggestedRate
                return determination
            }
        } else {
            determination.duration = duration
            determination.rate = suggestedRate
            return determination
        }
    }
}
