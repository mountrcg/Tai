import Foundation

enum SmbDeliveryRatioSuggestion {
    struct Baseline: Equatable {
        var loopInterval: Decimal
        var smbInterval: Decimal
        var ratio: Decimal
    }

    enum Result: Equatable {
        case invalid
        case keepCurrent
        case suggestion(value: Decimal, lowerBoundLimited: Bool)
    }

    /// Advisory cadence heuristic; actual insulin delivery also depends on dosing constraints.
    static func suggestion(baseline: Baseline, loopInterval: Decimal, smbInterval: Decimal) -> Result {
        let current = baseline.ratio
        let intervals = [baseline.loopInterval, baseline.smbInterval, loopInterval, smbInterval]
        guard !current.isNaN, (Decimal(0.1) ... Decimal(1.5)).contains(current),
              intervals.allSatisfy({ !$0.isNaN && $0 > 0 && $0 <= 10 }),
              GlucoseCadence.validInteger(baseline.loopInterval, range: 1 ... 10) != nil,
              GlucoseCadence.validInteger(loopInterval, range: 1 ... 10) != nil
        else { return .invalid }
        let oldBasis = max(baseline.loopInterval, baseline.smbInterval)
        let newBasis = max(loopInterval, smbInterval)
        guard current < 1, newBasis < oldBasis else { return .keepCurrent }

        let raw = 1 - pow(
            1 - NSDecimalNumber(decimal: current).doubleValue,
            NSDecimalNumber(decimal: newBasis / oldBasis).doubleValue
        )
        // absorb floating-point noise at exact grid boundaries before flooring
        let candidate = Decimal(Int(floor(raw / 0.05 + 1E-12))) * Decimal(string: "0.05")!
        let bounded = min(current, min(1.5, max(0.1, candidate)))
        return .suggestion(value: bounded, lowerBoundLimited: raw < 0.1)
    }
}
