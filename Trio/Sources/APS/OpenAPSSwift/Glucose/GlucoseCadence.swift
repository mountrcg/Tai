import Foundation

enum GlucoseCadence: Equatable {
    case legacy
    case dense(medianSpacing: TimeInterval)

    static func detect(_ readings: [BloodGlucose], trusted: Bool, enabled: Bool, now: Date) -> Self {
        guard trusted, enabled else { return .legacy }
        let dates = Array(Set(readings.filter {
            $0.mbg == nil && ($0.glucose ?? $0.sgv ?? 0) > 38 && $0.noise != 4 && $0.dateString <= now
        }.map(\.dateString))).sorted(by: >)
        guard let newest = dates.first, now.timeIntervalSince(newest) <= 7 * 60 else { return .legacy }
        var intervals: [TimeInterval] = []
        for (newer, older) in zip(dates, dates.dropFirst()).prefix(30) {
            let spacing = newer.timeIntervalSince(older)
            // a fresh contiguous window must qualify again after signal loss
            guard spacing <= 7 * 60 else { break }
            if spacing > 1 { intervals.append(spacing) }
        }
        guard intervals.count >= 5 else { return .legacy }
        intervals.sort()
        let middle = intervals.count / 2
        let median = intervals.count.isMultiple(of: 2)
            ? (intervals[middle - 1] + intervals[middle]) / 2 : intervals[middle]
        return median <= 3.5 * 60 ? .dense(medianSpacing: median) : .legacy
    }

    var isDense: Bool {
        if case .dense = self { return true }
        return false
    }

    func parabolaMinimum(override: Decimal?) -> Decimal {
        if let value = Self.validInteger(override, range: 5 ... 20) { return value }
        if case let .dense(spacing) = self, spacing < 90 { return 10 }
        return 15
    }

    static func validInteger(_ value: Decimal?, range: ClosedRange<Int>) -> Decimal? {
        guard let value, !value.isNaN, value >= Decimal(range.lowerBound), value <= Decimal(range.upperBound),
              value.rounded() == value else { return nil }
        return value
    }
}

/// Bounded pre-admission history lets singleton callbacks establish cadence without losing startup observations.
struct GlucoseCadenceCandidates {
    private(set) var readings: [BloodGlucose] = []
    private var epochID: UUID?

    mutating func append(_ incoming: [BloodGlucose], epochID: UUID, now: Date) {
        if self.epochID != epochID { readings.removeAll() }
        self.epochID = epochID
        var seen = Set<Date>()
        readings = Array((incoming + readings).filter {
            $0.mbg == nil && $0.dateString <= now && now.timeIntervalSince($0.dateString) <= 4 * 3600
        }.sorted { $0.dateString > $1.dateString }.filter { seen.insert($0.dateString).inserted }.prefix(64))
    }
}

/// Detects a lasting change of the CGM reading cadence (in whole minutes) so the user can be told to
/// review the SMB delivery ratios: SMBs may now be given more or less often than before.
struct CGMCadenceChangeMonitor: Codable, Equatable {
    /// A new cadence must hold this long before it counts, so signal loss or a backfill burst
    /// does not raise a notification.
    static let confirmationDwell: TimeInterval = 15 * 60

    struct Change: Equatable {
        let fromMinutes: Int
        let toMinutes: Int
    }

    private(set) var baselineMinutes: Int?
    private var baselineSince: Date?
    private var candidateMinutes: Int?
    private var candidateSince: Date?

    /// Reading spacing used for SMB timing: 5 for the regular cadence, otherwise the dense median rounded to minutes.
    static func minutes(for cadence: GlucoseCadence) -> Int {
        guard case let .dense(spacing) = cadence else { return 5 }
        return min(5, max(1, Int((spacing / 60).rounded())))
    }

    mutating func observe(_ cadence: GlucoseCadence, now: Date) -> Change? {
        let minutes = Self.minutes(for: cadence)
        guard let baseline = baselineMinutes else {
            baselineMinutes = minutes
            baselineSince = now
            return nil
        }
        guard minutes != baseline else {
            candidateMinutes = nil
            candidateSince = nil
            return nil
        }
        guard candidateMinutes == minutes, let since = candidateSince else {
            candidateMinutes = minutes
            candidateSince = now
            return nil
        }
        guard now.timeIntervalSince(since) >= Self.confirmationDwell else { return nil }
        // Right after sub-5-minute loops are switched on, cadence detection still settles
        // (it needs several readings); that start-up change is announced by the switch itself.
        let isWarmUp = baselineSince.map { since.timeIntervalSince($0) < Self.confirmationDwell } ?? false
        baselineMinutes = minutes
        baselineSince = now
        candidateMinutes = nil
        candidateSince = nil
        return isWarmUp ? nil : Change(fromMinutes: baseline, toMinutes: minutes)
    }

    mutating func reset() {
        self = CGMCadenceChangeMonitor()
    }
}
