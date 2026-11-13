import CoreGraphics
import Foundation

extension Decimal {
    /// Rounds to a specified number of decimal places to prevent floating-point artifacts
    /// - Parameters:
    ///   - scale: Number of decimal places to round to
    ///   - mode: Rounding mode (default is .plain)
    /// - Returns: Rounded Decimal
    func precisionRounded(
        scale: Int = 3,
        mode: NSDecimalNumber.RoundingMode = .plain
    ) -> Decimal {
        var result = Decimal()
        var localCopy = self
        NSDecimalRound(&result, &localCopy, scale, mode)
        return result
    }

    /// Rounds the Decimal with optional increment and rounding mode
    /// - Parameters:
    ///   - increment: Optional increment to round to
    ///   - maxBolus: Optional maximum bolus value
    ///   - roundingMode: Rounding mode
    /// - Returns: Rounded Decimal
    func roundedWithIncrement(
        increment: Decimal? = nil,
        maxBolus: Decimal? = nil,
        roundingMode: NSDecimalNumber.RoundingMode = .plain
    ) -> Decimal {
        // First, precision round to remove floating-point artifacts
        let precisionRounded = self.precisionRounded()

        guard let increment = increment else { return precisionRounded }

        return precisionRounded.roundedToBolusIncrement(
            increment: increment,
            maxBolus: maxBolus,
            roundingMode: roundingMode
        )
    }

    /// Rounds to bolus increment using pure Decimal arithmetic to avoid floating-point precision issues
    /// - Parameters:
    ///   - increment: Increment to round to
    ///   - maxBolus: Optional maximum bolus value
    ///   - roundingMode: Rounding mode (default is .down)
    /// - Returns: Rounded Decimal value
    func roundedToBolusIncrement(
        increment: Decimal,
        maxBolus: Decimal? = nil,
        roundingMode: NSDecimalNumber.RoundingMode = .down
    ) -> Decimal {
        guard increment > 0 else { return self }

        // Use pure Decimal arithmetic to avoid floating-point precision issues
        // Calculate how many increments fit into the value
        let divided = self / increment

        // Round the quotient to get a whole number of increments
        var roundedQuotient = Decimal()
        var dividedCopy = divided
        // Scale 0 rounds to integer
        NSDecimalRound(&roundedQuotient, &dividedCopy, 0, roundingMode)

        // Multiply back by increment to get the final value
        let result = roundedQuotient * increment

        if let maxBolus = maxBolus {
            return min(result, maxBolus)
        }
        return result
    }

    /// Determines the maximum fraction digits based on bolus increment
    /// - Parameter increment: Bolus increment
    /// - Returns: Number of maximum fraction digits
    static func maxFractionDigits(for increment: Decimal) -> Int {
        switch increment {
        case 0.0025:
            return 4
        case 0.005:
            return 3
        case 0.01:
            return 2
        case 0.0125:
            return 4
        case 0.025:
            return 3
        case 0.05:
            return 2
        case 0.1:
            return 1
        default:
            // Fallback for any unexpected increment
            if increment < 0.005 {
                return 4
            } else if increment < 0.01 {
                return 3
            } else if increment < 0.1 {
                return 2
            } else {
                return 1
            }
        }
    }

    func roundedDouble(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (Double(self) * divisor).rounded() / divisor
    }

    /// The closest of `rates` to this value, ties resolved upward, with zero seeding the search so
    /// a value below every entry still resolves to a deliverable rate — the rule
    /// `TempBasalFunctions.roundBasal` applies to basal rates.
    func nearestSupportedBasalRate(in rates: [Decimal]) -> Decimal {
        rates.reduce(0) { nearest, rate in
            let distance = abs(rate - self)
            let nearestDistance = abs(nearest - self)
            return distance < nearestDistance || (distance == nearestDistance && rate > nearest) ? rate : nearest
        }
    }
}

// MARK: - Double Initializer for Decimal

extension Double {
    /// Initializes a Double from a Decimal.
    init(_ decimal: Decimal) {
        self.init(truncating: decimal as NSNumber)
    }

    /// Rounds the double to a specified number of decimal places
    func roundedDouble(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }

    /// Rounds insulin rates to a consistent precision (e.g., 2 decimal places)
    func roundedInsulinRate() -> Double {
        roundedDouble(toPlaces: 2)
    }
}

// MARK: - Int Initializer for Decimal

extension Int {
    /// Initializes an Int from a Decimal.
    init(_ decimal: Decimal) {
        self.init(Double(decimal))
    }
}

// MARK: - CGFloat Initializer for Decimal

extension CGFloat {
    /// Initializes a CGFloat from a Decimal.
    init(_ decimal: Decimal) {
        self.init(Double(decimal))
    }
}

// MARK: - Time Interval Conversion for Int16

extension Int16 {
    /// Converts Int16 minutes to a TimeInterval in seconds.
    var minutes: TimeInterval {
        TimeInterval(self) * 60
    }
}
