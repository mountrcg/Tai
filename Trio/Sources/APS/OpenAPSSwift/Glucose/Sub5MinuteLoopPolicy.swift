import Foundation

enum Sub5MinuteLoopPolicy {
    /// Only applies to optional events in opted-in, qualified dense processing.
    static func shouldSkipIntermediateRun(
        now: Date,
        lastRegularRun: Date?,
        loopInterval: Decimal,
        lastBolus: Date?,
        SMBInterval: Decimal
    ) -> Bool {
        guard now.timeIntervalSince1970.isFinite,
              let lastRegularRun, lastRegularRun.timeIntervalSince1970.isFinite,
              lastRegularRun <= now,
              let interval = GlucoseCadence.validInteger(loopInterval, range: 1 ... 10),
              let smbDue = SmbIntervalGate.dueDate(lastBolusTime: lastBolus, intervalMinutes: SMBInterval, now: now)
        else { return false }
        // regular cadence never replaces Config.loopInterval's short re-entry guard
        let nextRegular = lastRegularRun.addingTimeInterval(NSDecimalNumber(decimal: interval).doubleValue * 60)
        return now < nextRegular && now < smbDue && smbDue < nextRegular
    }
}
