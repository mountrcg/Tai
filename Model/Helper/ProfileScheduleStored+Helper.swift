import CoreData
import Foundation

/// Decoded view of a `ProfileScheduleStored` row plus next-fire computation. Kept separate from
/// the managed-object class so the math is unit-testable without a Core Data stack — callers pass
/// a plain `ProfileScheduleRule` struct to `nextFire(after:calendar:)`.

/// In-memory struct form of a stored schedule. Built from the managed object; the math lives here
/// so tests don't need Core Data.
struct ProfileScheduleRule: Hashable, Sendable {
    var repeatRule: ProfileSchedule.Repeat
    /// 1–2 times of day that the schedule fires at. For `.once` this is ignored (the full timestamp
    /// is encoded in the `.once(Date)` associated value).
    var firesAt: [ProfileSchedule.TimeOfDay]
}

// MARK: - NSPredicate helpers

extension NSPredicate {
    static var enabledSchedule: NSPredicate {
        NSPredicate(format: "enabled == %@", true as NSNumber)
    }

    static func schedulesForProfile(_ id: UUID) -> NSPredicate {
        NSPredicate(format: "profileID == %@", id as CVarArg)
    }

    static func scheduleByID(_ id: UUID) -> NSPredicate {
        NSPredicate(format: "id == %@", id as CVarArg)
    }
}

// MARK: - Managed-object convenience

extension ProfileScheduleStored {
    static func fetch(
        _ predicate: NSPredicate,
        ascending: Bool = true,
        fetchLimit: Int? = nil
    ) -> NSFetchRequest<ProfileScheduleStored> {
        let request = ProfileScheduleStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: ascending)]
        request.predicate = predicate
        if let fetchLimit = fetchLimit {
            request.fetchLimit = fetchLimit
        }
        return request
    }

    /// Decoded repeat rule. Nil if unset or decode fails.
    var repeatRule: ProfileSchedule.Repeat? {
        get {
            guard let data = repeatRuleJSON else { return nil }
            return try? JSONCoding.decoder.decode(ProfileSchedule.Repeat.self, from: data)
        }
        set {
            repeatRuleJSON = newValue.flatMap { try? JSONCoding.encoder.encode($0) }
        }
    }

    /// Decoded list of fire times (1–2 per schedule).
    var firesAt: [ProfileSchedule.TimeOfDay] {
        get {
            guard let data = firesAtJSON else { return [] }
            return (try? JSONCoding.decoder.decode([ProfileSchedule.TimeOfDay].self, from: data)) ?? []
        }
        set {
            firesAtJSON = (try? JSONCoding.encoder.encode(newValue))
        }
    }

    /// Decoded duration.
    var duration: ProfileSchedule.Duration? {
        get {
            guard let data = durationJSON else { return nil }
            return try? JSONCoding.decoder.decode(ProfileSchedule.Duration.self, from: data)
        }
        set {
            durationJSON = newValue.flatMap { try? JSONCoding.encoder.encode($0) }
        }
    }

    /// Plain-Swift view of the schedule for use with `nextFire(after:calendar:)`. Returns nil if
    /// the stored repeatRule failed to decode.
    var rule: ProfileScheduleRule? {
        guard let repeatRule else { return nil }
        return ProfileScheduleRule(repeatRule: repeatRule, firesAt: firesAt)
    }
}

extension ProfileScheduleRule {
    /// Soonest future fire strictly after `from`. Returns nil if the rule will never fire again
    /// (e.g. `.once` with a past date, or an empty weekday/monthlyDays set, an `everyDays` interval
    /// outside 1…365, or a `firesAt` that is empty for the recurring cases).
    ///
    /// Uses `.strict` matching so `monthlyDays(31)` skips months without a 31st rather than
    /// snapping to the last valid day.
    func nextFire(after from: Date, calendar: Calendar = .current) -> Date? {
        switch repeatRule {
        case let .once(date):
            return date > from ? date : nil

        case let .weekdays(days) where !days.isEmpty:
            return earliestMatch(from: from) { time in
                days.compactMap { weekday in
                    var comp = DateComponents()
                    comp.weekday = weekday.rawValue
                    comp.hour = time.hour
                    comp.minute = time.minute
                    return calendar.nextDate(after: from, matching: comp, matchingPolicy: .nextTime)
                }
            }

        case let .monthlyDays(days) where !days.isEmpty:
            return earliestMatch(from: from) { time in
                days.compactMap { day in
                    var comp = DateComponents()
                    comp.day = day
                    comp.hour = time.hour
                    comp.minute = time.minute
                    return calendar.nextDate(after: from, matching: comp, matchingPolicy: .strict)
                }
            }

        case let .everyDays(intervalDays, anchor):
            guard intervalDays >= 1, intervalDays <= 365 else { return nil }
            return earliestMatch(from: from) { time in
                everyDaysCandidates(
                    anchor: anchor, intervalDays: intervalDays, time: time,
                    after: from, calendar: calendar
                )
            }

        default:
            return nil
        }
    }

    /// For each entry in `firesAt`, compute candidate fire dates via `perTime`, then return the
    /// earliest across all combinations. Empty `firesAt` means the recurring rule can't fire.
    private func earliestMatch(
        from _: Date,
        perTime: (ProfileSchedule.TimeOfDay) -> [Date]
    ) -> Date? {
        guard !firesAt.isEmpty else { return nil }
        return firesAt.flatMap(perTime).min()
    }

    /// First grid day at or after `from`'s day, placed at `time`; one step further if that wall
    /// time already passed.
    private func everyDaysCandidates(
        anchor: Date, intervalDays: Int, time: ProfileSchedule.TimeOfDay,
        after from: Date, calendar: Calendar
    ) -> [Date] {
        let anchorDay = calendar.startOfDay(for: anchor)
        let elapsed = calendar.dateComponents(
            [.day], from: anchorDay, to: calendar.startOfDay(for: from)
        ).day ?? 0
        let base = max(0, elapsed / intervalDays)
        for step in base ... (base + 1) {
            guard let day = calendar.date(byAdding: .day, value: step * intervalDays, to: anchorDay),
                  let candidate = calendar.date(
                      bySettingHour: time.hour, minute: time.minute, second: 0, of: day
                  )
            else { return [] }
            if candidate > from { return [candidate] }
        }
        return []
    }
}
