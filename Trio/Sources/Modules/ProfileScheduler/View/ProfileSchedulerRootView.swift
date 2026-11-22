import SwiftUI
import Swinject

extension ProfileScheduler {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var showAddSchedule = false
        @State private var selectedForDelete: ProfileScheduleListItem?
        @State private var isConfirmDeletePresented = false
        @State private var showScheduleHint = false
        @State private var scheduleHintDetent = PresentationDetent.large

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private static let nextFireFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEE, dd.MM. HH:mm"
            return f
        }()

        var body: some View {
            List {
                if state.items.isEmpty, !state.isLoading {
                    emptyState
                } else {
                    schedulesSection
                }
            }
            .listSectionSpacing(10)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Schedules")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await state.refresh() }
            .onAppear(perform: configureView)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        state.startNewDraft()
                        showAddSchedule = true
                    }, label: {
                        HStack {
                            Text("Add Schedule")
                            Image(systemName: "plus")
                        }
                    })
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showScheduleHint = true }) {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showAddSchedule) {
                AddScheduleView(state: state, onDismiss: { showAddSchedule = false })
            }
            .sheet(isPresented: $showScheduleHint) {
                SettingInputHintView(
                    hintDetent: $scheduleHintDetent,
                    shouldDisplayHint: $showScheduleHint,
                    hintLabel: String(
                        localized: "About Schedules",
                        comment: "Help hint label on the Profile Scheduler list screen"
                    ),
                    hintText: AnyView(scheduleAbstractHint),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
        }

        @ViewBuilder private var scheduleAbstractHint: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("What is a Schedule?").bold()
                Text(
                    "A Schedule fires a profile activation at a future time — once, or on a repeating cadence. It lets you automate profile switches that follow a predictable pattern (sick days, night mode, workouts, menstrual cycle, travel)."
                )

                Text("Repeat options").bold()
                Text("Once: fires a single time at the picked date and time. The schedule auto-deletes after firing.")
                Text(
                    "Daily / Weekdays / Weekends / Custom weekly: fires at the chosen time on matching weekdays."
                )
                Text("Monthly: fires on the chosen day-of-month.")

                Text("Duration").bold()
                Text(
                    "Temporary (up to 24 h): runs for the chosen duration, then reverts to the anchor (your last indefinite profile). Trio and the pump manager deliver the profile's basal rates live — the pump's saved basal schedule is NOT changed. If pump connectivity drops, the pump falls back to its last saved schedule."
                )
                Text(
                    "Indefinite / until next: becomes your new baseline. The basal profile is saved to the pump and stays until you switch profiles again."
                )

                Text("Notifications").bold()
                Text(
                    "Temporary activation: an informational notification confirms the switch (\"Profile X activated — auto-reverts at hh:mm\"). No action required."
                )
                Text(
                    "Indefinite activation: an actionable notification (\"Save basal to pump?\") with Save to pump / Cancel buttons. Tapping the body re-opens an in-app confirmation dialog when you return to the app."
                )
                Text(
                    "Auto-revert: when a temp profile expires, you get a notification (\"Profile X expired — reverted to Y\")."
                )

                Text("Confirming pump writes").bold()
                Text(
                    "Only indefinite (and until-next) activations write a new basal schedule into the pump's memory. Schedules will NOT write to the pump automatically — confirm via Save to pump in the notification or the in-app dialog. Until you confirm, the previous saved schedule stays on the pump."
                )
                Text(
                    "Temporary activations don't overwrite the pump's saved schedule — Trio and the pump manager deliver the temp profile's rates live. That's what lets the temp auto-revert cleanly and also protects you if pump connectivity drops (the pump falls back to its last saved schedule)."
                )

                Text("Managing").bold()
                Text(
                    "Swipe left on a schedule row to enable, disable, or delete it. Disabled schedules sink to the bottom and don't fire. The Upcoming section on the Profiles screen shows the next two fires across all enabled schedules."
                )
            }
        }

        private var emptyState: some View {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No schedules yet")
                        .font(.headline)
                    Text("Tap + to schedule an automatic profile switch.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }
            .listRowBackground(Color.clear)
        }

        private var schedulesSection: some View {
            Section {
                ForEach(state.items) { item in
                    row(for: item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                selectedForDelete = item
                                isConfirmDeletePresented = true
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                                    .tint(.red)
                            }
                            Button {
                                state.toggleEnabled(item)
                            } label: {
                                if item.enabled {
                                    Label("Disable", systemImage: "pause.circle.fill")
                                        .tint(.blue)
                                } else {
                                    Label("Enable", systemImage: "play.circle.fill")
                                        .tint(.blue)
                                }
                            }
                        }
                }
                .confirmationDialog(
                    "Delete this schedule?",
                    isPresented: $isConfirmDeletePresented,
                    titleVisibility: .visible
                ) {
                    if let target = selectedForDelete {
                        Button("Delete", role: .destructive) {
                            state.delete(target)
                            selectedForDelete = nil
                        }
                    }
                    Button("Cancel", role: .cancel) { selectedForDelete = nil }
                }
                .listRowBackground(Color.chart)
            } header: {
                Text("Active schedules")
            } footer: {
                HStack {
                    Image(systemName: "hand.draw.fill").foregroundStyle(.primary)
                    Text(
                        "Swipe left to enable, disable, or delete. Enabled schedules are sorted by next fire; disabled ones sink to the bottom."
                    )
                }
            }
        }

        @ViewBuilder private func row(for item: ProfileScheduleListItem) -> some View {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(for: item))
                        .font(.body)
                        .foregroundColor(item.enabled ? .primary : .secondary)
                    Text(subline(for: item))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    if let next = item.nextFire {
                        Text(Self.nextFireFormatter.string(from: next))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if !item.enabled {
                        Text("Disabled")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .contentShape(Rectangle())
        }

        private func headline(for item: ProfileScheduleListItem) -> String {
            let repeatText = ProfileScheduleSummary.repeatText(item.repeatRule)
            let timeText = ProfileScheduleSummary.timesText(item.firesAt, for: item.repeatRule)
            if timeText.isEmpty { return repeatText }
            return "\(repeatText) • \(timeText)"
        }

        private func subline(for item: ProfileScheduleListItem) -> String {
            let profile = item.profileName
            let dur = ProfileScheduleSummary.durationText(item.duration)
            return "\(profile) • \(dur)"
        }
    }
}

/// One-line summary helpers used by the list row + preview sentence in the picker.
enum ProfileScheduleSummary {
    static func repeatText(_ rule: ProfileSchedule.Repeat) -> String {
        switch rule {
        case let .weekdays(days):
            if days
                .count == 7 { return String(localized: "Every day", comment: "Schedule repeat summary — every day of the week") }
            if days ==
                [.monday, .tuesday, .wednesday, .thursday, .friday]
            {
                return String(localized: "Weekdays", comment: "Schedule repeat summary — Monday through Friday") }
            if days ==
                [.saturday, .sunday]
            {
                return String(localized: "Weekends", comment: "Schedule repeat summary — Saturday and Sunday") }
            if days
                .isEmpty
            {
                return String(
                    localized: "No days selected",
                    comment: "Schedule repeat summary when the weekday set is empty (error state)"
                ) }
            let sorted = days.sorted { $0.rawValue < $1.rawValue }
            return String(
                localized: "Weekly on \(sorted.map(shortName(_:)).joined(separator: ", "))",
                comment: "Schedule repeat summary prefix for a custom weekly pattern — interpolated list is comma-separated weekday abbreviations"
            )
        case let .monthlyDays(days):
            if days
                .isEmpty
            {
                return String(
                    localized: "No days selected",
                    comment: "Schedule repeat summary when the monthly day set is empty"
                ) }
            let sorted = days.sorted()
            return String(
                localized: "Monthly on \(sorted.map(String.init).joined(separator: ", "))",
                comment: "Schedule repeat summary for custom monthly days — interpolated list is comma-separated day numbers"
            )
        case let .once(date):
            let f = DateFormatter()
            f.dateFormat = "EEE, dd.MM.yyyy HH:mm"
            return String(
                localized: "Once on \(f.string(from: date))",
                comment: "Schedule repeat summary for a one-off fire — interpolated value is a localized date/time string"
            )
        case let .everyDays(intervalDays, anchor):
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .none
            let start = f.string(from: anchor)
            if intervalDays == 1 {
                return String(
                    localized: "Every day from \(start)",
                    comment: "Schedule repeat summary for a 1-day interval — interpolated value is the localized start date"
                )
            }
            return String(
                localized: "Every \(intervalDays) days from \(start)",
                comment: "Schedule repeat summary for an N-day interval — interpolated values are the interval and the localized start date"
            )
        }
    }

    static func timesText(_ times: [ProfileSchedule.TimeOfDay], for rule: ProfileSchedule.Repeat) -> String {
        if case .once = rule { return "" }
        if times.isEmpty { return "" }
        return String(
            localized: "at \(times.map { String(format: "%02d:%02d", $0.hour, $0.minute) }.joined(separator: " & "))",
            comment: "Schedule summary time prefix — interpolated list is two-digit HH:MM values joined with ' & '"
        )
    }

    static func durationText(_ duration: ProfileSchedule.Duration) -> String {
        switch duration {
        case let .minutes(m):
            let h = m / 60
            let mm = m % 60
            if h ==
                0
            {
                return String(
                    localized: "for \(mm) min",
                    comment: "Schedule duration summary — temporary activation under one hour"
                ) }
            if mm ==
                0
            {
                return String(
                    localized: "for \(h) h",
                    comment: "Schedule duration summary — temporary activation in whole hours"
                ) }
            return String(
                localized: "for \(h) h \(mm) min",
                comment: "Schedule duration summary — temporary activation in hours and minutes"
            )
        case .indefinite,
             .untilNext:
            return String(localized: "until next change", comment: "Schedule duration summary — indefinite/until-next activation")
        }
    }

    /// Locale-aware 3-letter weekday abbreviation (e.g. "Mon" / "Mo." / "月").
    static func shortName(_ w: ProfileSchedule.Weekday) -> String {
        let symbols = shortStandaloneWeekdaySymbols
        let index = w.rawValue - 1 // Calendar.weekday: Sunday=1
        return index >= 0 && index < symbols.count ? symbols[index] : "?"
    }

    /// Locale-aware single-letter weekday for chip buttons (e.g. "M" / "L" / "月").
    static func singleLetter(_ w: ProfileSchedule.Weekday) -> String {
        let symbols = veryShortStandaloneWeekdaySymbols
        let index = w.rawValue - 1
        return index >= 0 && index < symbols.count ? symbols[index] : "?"
    }

    private static var shortStandaloneWeekdaySymbols: [String] {
        let f = DateFormatter()
        f.locale = .current
        return f.shortStandaloneWeekdaySymbols ?? []
    }

    private static var veryShortStandaloneWeekdaySymbols: [String] {
        let f = DateFormatter()
        f.locale = .current
        return f.veryShortStandaloneWeekdaySymbols ?? []
    }
}
