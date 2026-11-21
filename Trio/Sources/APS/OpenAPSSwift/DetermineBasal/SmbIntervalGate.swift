import Foundation

enum SmbIntervalGate {
    static func sanitizedInterval(_ minutes: Decimal) -> Decimal {
        GlucoseCadence.validInteger(minutes, range: 1 ... 10) ?? 3
    }

    static func dueDate(lastBolusTime: Date?, intervalMinutes: Decimal, now: Date) -> Date? {
        guard now.timeIntervalSince1970.isFinite,
              let lastBolusTime, lastBolusTime.timeIntervalSince1970.isFinite,
              lastBolusTime <= now
        else { return nil }
        return lastBolusTime.addingTimeInterval(
            NSDecimalNumber(decimal: sanitizedInterval(intervalMinutes)).doubleValue * 60 - 6
        )
    }

    /// Missing or invalid history cannot authorize automatic insulin.
    static func tooSoon(lastBolusTime: Date?, intervalMinutes: Decimal, now: Date) -> Bool {
        guard let due = dueDate(lastBolusTime: lastBolusTime, intervalMinutes: intervalMinutes, now: now) else {
            return true
        }
        return now < due
    }
}
