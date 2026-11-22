import CoreData
import Foundation

enum ProfileScheduler {
    enum Config {}
}

/// Lightweight, ObservableObject-friendly view of a `ProfileScheduleStored` row. Decoupled from
/// Core Data object lifetime — SwiftUI lists render these, mutations go through
/// `ProfileSchedulerProvider`.
struct ProfileScheduleListItem: Identifiable, Hashable {
    let id: UUID
    let profileID: UUID
    let profileName: String
    let repeatRule: ProfileSchedule.Repeat
    let firesAt: [ProfileSchedule.TimeOfDay]
    let duration: ProfileSchedule.Duration
    let enabled: Bool
    let createdAt: Date
    /// Pre-computed next fire for list display. Nil if rule is invalid or can't fire again
    /// (e.g. a `.once` in the past).
    let nextFire: Date?
}

/// Target profile choice in the picker.
struct ProfilePickerChoice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let isActive: Bool
}

/// Shape of the draft being built in the new-schedule flow. Translated into a stored entity on save.
struct ProfileScheduleDraft {
    var profileID: UUID?
    var profileName: String = ""
    var repeatRule: ProfileSchedule.Repeat = .weekdays([])
    var firesAt: [ProfileSchedule.TimeOfDay] = [.init(hour: 8, minute: 0)]
    var duration: ProfileSchedule.Duration = .untilNext
    /// User-facing optional name ("Morning switch"). Empty string = no name.
    var name: String = ""

    /// Nil when the draft isn't ready to save.
    var validationError: String? {
        guard profileID != nil else { return "Pick a profile" }
        switch repeatRule {
        case let .weekdays(days):
            if days.isEmpty { return "Pick at least one weekday" }
        case let .monthlyDays(days):
            if days.isEmpty { return "Pick at least one day" }
        case let .once(date):
            if date <= Date() { return "Pick a future date" }
        case let .everyDays(intervalDays, _):
            if intervalDays < 1 { return "Interval must be at least 1 day" }
        }
        if firesAt.isEmpty, !isOnce { return "Pick a time" }
        return nil
    }

    private var isOnce: Bool {
        if case .once = repeatRule { return true }
        return false
    }
}

protocol ProfileSchedulerProvider: Provider {
    func fetchAllSchedules() async -> [ProfileScheduleListItem]
    func fetchProfiles() async -> [ProfilePickerChoice]
    func saveNewSchedule(_ draft: ProfileScheduleDraft) async -> UUID?
    func setEnabled(id: UUID, enabled: Bool) async
    func deleteSchedule(id: UUID) async
}
