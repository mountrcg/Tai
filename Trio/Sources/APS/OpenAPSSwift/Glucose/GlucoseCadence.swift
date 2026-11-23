import Foundation
import Observation

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

/// Loop cadence shown on the settings page and in the settings export. The loop runs on every
/// reading, so with sub-5-minute loops on this is the detected CGM interval.
enum LoopFrequency: Equatable {
    case regular
    case detected(Int)
    /// Detection still running: a 1-minute CGM is assumed so the scaling chart is usable right away.
    case assumed(Int)

    static func current(enabled: Bool, detectedMinutes: Int?) -> Self {
        guard enabled else { return .regular }
        return detectedMinutes.map { .detected($0) } ?? .assumed(1)
    }

    var minutes: Int {
        switch self {
        case .regular: 5
        case let .assumed(minutes),
             let .detected(minutes): minutes
        }
    }

    var displayText: String {
        switch self {
        case .regular: String(localized: "5 min")
        case let .detected(minutes): String(localized: "\(minutes) min (detected)")
        case let .assumed(minutes): String(localized: "\(minutes) min (assumed, detecting…)")
        }
    }
}

/// Pending "check your SMB delivery ratios" notice, shown on the Home panel until the user taps it.
/// Raised when sub-5-minute loops are switched or the detected CGM interval changes, because the
/// ratio applies per SMB and SMBs can now be given more or less often.
@Observable final class SmbRatioReviewNotice {
    struct Pending: Codable, Equatable {
        /// true: readings now come more often than every 5 minutes (review on the sub-5-minute page);
        /// false: back to 5-minute readings (review the regular SMB delivery ratio setting).
        let toDense: Bool
        /// Detected CGM interval, nil when not yet known.
        let cgmMinutes: Int?
        /// New SMB period when the notice was raised by an SMB Interval change.
        var smbPeriodMinutes: Double? = nil
    }

    /// Minutes between SMBs: the loop runs once per CGM reading, SMBs are further limited by the SMB Interval.
    static func smbPeriod(cgmMinutes: Int, smbInterval: Decimal) -> Double {
        max(Double(cgmMinutes), NSDecimalNumber(decimal: smbInterval).doubleValue)
    }

    static let shared = SmbRatioReviewNotice()
    private static let defaultsKey = "smbRatioReviewNotice"

    private(set) var pending: Pending?

    private init() {
        pending = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(Pending.self, from: $0) }
    }

    func post(toDense: Bool, cgmMinutes: Int?, smbPeriodMinutes: Double? = nil) {
        set(Pending(toDense: toDense, cgmMinutes: cgmMinutes, smbPeriodMinutes: smbPeriodMinutes))
    }

    func clear() {
        set(nil)
    }

    private func set(_ value: Pending?) {
        DispatchQueue.main.async {
            self.pending = value
            if let value, let data = try? JSONEncoder().encode(value) {
                UserDefaults.standard.set(data, forKey: Self.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            }
        }
    }
}
