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
    /// Rounds a basal rate to the nearest rate the paired pump can deliver.
    ///
    /// Nearest, not floored as `PumpManager.roundToSupportedBasalRate` does: on a uniform grid it
    /// reproduces JS `round-basal.js`, which rounds half up. Zero seeds the search because every
    /// pump can hold a zero temp, and a pod's table starts at 0.05 without listing one.
    static func roundBasal(profile: Profile, basalRate: Decimal) -> Decimal {
        // no pump paired: leave the rate alone beyond keeping reason strings readable. 5 dp, not
        // the 3 a pump rate needs, because a U10 rate carries two digits further
        guard !profile.supportedBasalRates.isEmpty else {
            return basalRate.rounded(scale: 5, roundingMode: .down)
        }

        return profile.supportedBasalRates.reduce(0) { nearest, rate in
            let distance = abs(rate - basalRate)
            let nearestDistance = abs(nearest - basalRate)
            return distance < nearestDistance || (distance == nearestDistance && rate > nearest) ? rate : nearest
        }
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
