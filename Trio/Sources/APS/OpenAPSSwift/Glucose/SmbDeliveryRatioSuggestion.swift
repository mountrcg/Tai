import Foundation

enum SmbDeliveryRatioSuggestion {
    enum Field: CaseIterable {
        case fixed, minimum, maximum

        var bounds: ClosedRange<Decimal> {
            switch self {
            case .fixed: return 0.1 ... 1.5
            case .minimum: return 0.1 ... 1
            case .maximum: return 0.1 ... 1.2
            }
        }
    }

    enum Result: Equatable {
        case invalid
        case keepCurrent
        case suggestion(value: Decimal, lowerBoundLimited: Bool)
    }

    /// A nominal configuration heuristic, not an insulin-delivery or clinical-equivalence guarantee.
    static func suggestion(current: Decimal, field: Field, smbInterval: Decimal) -> Result {
        guard !current.isNaN, field.bounds.contains(current),
              let interval = GlucoseCadence.validInteger(smbInterval, range: 1 ... 10)
        else { return .invalid }
        guard current < 1, interval < 5 else { return .keepCurrent }

        // whole-minute S intentionally excludes the gate's six-second tolerance; L does not limit intermediate SMBs
        let target = power(1 - current, NSDecimalNumber(decimal: interval).intValue)
        let step: Decimal = 0.05
        // compare fifth powers on the picker grid to floor the inverse without root-approximation drift
        let candidate = (0 ... 20).map { Decimal($0) * step }
            .last { power(1 - $0, 5) >= target } ?? 0
        let bounded = min(current, min(field.bounds.upperBound, max(field.bounds.lowerBound, candidate)))
        return .suggestion(value: bounded, lowerBoundLimited: target > power(1 - field.bounds.lowerBound, 5))
    }

    static func validEndpoints(minimum: Decimal, maximum: Decimal) -> Bool {
        !minimum.isNaN && !maximum.isNaN && Field.minimum.bounds.contains(minimum) &&
            Field.maximum.bounds.contains(maximum) && minimum <= maximum
    }

    private static func power(_ value: Decimal, _ exponent: Int) -> Decimal {
        (0 ..< exponent).reduce(Decimal(1)) { result, _ in result * value }
    }
}
