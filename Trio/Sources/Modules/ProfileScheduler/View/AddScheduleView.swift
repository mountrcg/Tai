import SwiftUI

extension ProfileScheduler {
    /// New-schedule picker. Sections in order: Summary, Profile, Duration, Repeat, and a
    /// context-dependent Config that switches based on the chosen repeat kind (once / daily /
    /// weekdays / weekends / custom weekly / custom monthly / every N days). Default kind is
    /// `.once` so the simplest case is one tap away.
    struct AddScheduleView: View {
        @Bindable var state: StateModel
        let onDismiss: () -> Void

        // Duration
        @State private var durationMode: DurationMode = .indefinite
        @State private var durationHours: Int = 6
        @State private var durationMinutes: Int = 0
        @State private var showDurationPicker = false

        // Repeat
        @State private var selectedKind: RepeatKind = .once
        @State private var onceDate: Date = nextQuarterHour()
        @State private var weekdaySelection: Set<ProfileSchedule.Weekday> = []
        @State private var monthDaySelection: Set<Int> = []
        @State private var intervalDays: Int = 28
        @State private var anchorDay: Date = Calendar.current.startOfDay(for: Date())
        @State private var showTimePicker = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        enum DurationMode: String, CaseIterable, Identifiable {
            case indefinite = "Indefinite Profile"
            case temporary = "Temporary Profile"
            var id: String { rawValue }
        }

        enum RepeatKind: String, CaseIterable, Identifiable {
            case once = "Once"
            case daily = "Every day"
            case weekdays = "Every weekday"
            case weekends = "Every weekend"
            case customWeekly = "Custom weekly"
            case customMonthly = "Custom monthly"
            case everyNDays = "Every N days"
            var id: String { rawValue }
        }

        var body: some View {
            NavigationStack {
                List {
                    previewSection
                    profileSection
                    durationSection
                    repeatSection
                    configSection
                    saveSection
                }
                .listSectionSpacing(10)
                .scrollContentBackground(.hidden)
                .background(appState.trioBackgroundColor(for: colorScheme))
                .navigationTitle("New Schedule")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel", action: onDismiss)
                    }
                }
                .onAppear { applyKindToDraft() }
                .onChange(of: selectedKind) { _, _ in applyKindToDraft() }
                .onChange(of: weekdaySelection) { _, _ in
                    if selectedKind == .customWeekly { applyKindToDraft() }
                }
                .onChange(of: monthDaySelection) { _, _ in
                    if selectedKind == .customMonthly { applyKindToDraft() }
                }
                .onChange(of: onceDate) { _, _ in
                    if selectedKind == .once { applyKindToDraft() }
                }
                .onChange(of: intervalDays) { _, _ in
                    if selectedKind == .everyNDays { applyKindToDraft() }
                }
                .onChange(of: anchorDay) { _, _ in
                    if selectedKind == .everyNDays { applyKindToDraft() }
                }
            }
        }

        // MARK: - Preview / Save

        private var previewSection: some View {
            Section {
                Text(previewSentence)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.vertical, 4)
            } header: {
                Text("Summary")
            } footer: {
                if let err = state.draft.validationError {
                    Text(err).foregroundColor(.orange)
                }
            }
            .listRowBackground(Color.chart)
        }

        private var previewSentence: String {
            let rule = ProfileScheduleSummary.repeatText(state.draft.repeatRule)
            let times = ProfileScheduleSummary.timesText(state.draft.firesAt, for: state.draft.repeatRule)
            let profile = state.draft.profileID == nil ? "(pick a profile)" : state.draft.profileName
            let dur = ProfileScheduleSummary.durationText(previewDuration)
            let head = times.isEmpty ? rule : "\(rule) \(times)"
            return "\(head), activate \(profile) \(dur)."
        }

        private var previewDuration: ProfileSchedule.Duration {
            switch durationMode {
            case .temporary:
                let total = durationHours * 60 + durationMinutes
                return .minutes(max(5, total))
            case .indefinite:
                return .indefinite
            }
        }

        private func commitDraft() {
            state.draft.duration = previewDuration
            applyKindToDraft()
        }

        /// Pushes `selectedKind` + local selections into `state.draft.repeatRule`.
        private func applyKindToDraft() {
            switch selectedKind {
            case .once:
                state.draft.repeatRule = .once(onceDate)
            case .daily:
                state.draft.repeatRule = .weekdays(Set(ProfileSchedule.Weekday.allCases))
            case .weekdays:
                state.draft.repeatRule = .weekdays([.monday, .tuesday, .wednesday, .thursday, .friday])
            case .weekends:
                state.draft.repeatRule = .weekdays([.saturday, .sunday])
            case .customWeekly:
                state.draft.repeatRule = .weekdays(weekdaySelection)
            case .customMonthly:
                state.draft.repeatRule = .monthlyDays(monthDaySelection)
            case .everyNDays:
                state.draft.repeatRule = .everyDays(
                    intervalDays: intervalDays,
                    anchor: Calendar.current.startOfDay(for: anchorDay)
                )
            }
        }

        // MARK: - Profile

        private var profileSection: some View {
            Section {
                if state.availableProfiles.isEmpty {
                    Text("No profiles — create one first.")
                        .foregroundColor(.secondary)
                } else {
                    Picker("Profile", selection: Binding(
                        get: { state.draft.profileID ?? state.availableProfiles.first?.id ?? UUID() },
                        set: { id in
                            state.draft.profileID = id
                            state.draft.profileName = state.availableProfiles
                                .first(where: { $0.id == id })?.name ?? ""
                        }
                    )) {
                        ForEach(state.availableProfiles) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .listRowBackground(Color.chart)
        }

        // MARK: - Duration (moved up, below Profile)

        private var durationSection: some View {
            Section {
                Picker("Activation", selection: $durationMode) {
                    ForEach(DurationMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)

                if durationMode == .temporary {
                    HStack {
                        Text("Runs for")
                        Spacer()
                        Text(formatHM(hours: durationHours, minutes: durationMinutes))
                            .foregroundColor(showDurationPicker ? .accentColor : .primary)
                            .onTapGesture { showDurationPicker.toggle() }
                    }
                    if showDurationPicker {
                        HStack {
                            Picker("Hours", selection: $durationHours) {
                                ForEach(0 ..< 25) { Text("\($0) hr").tag($0) }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)

                            Picker("Minutes", selection: $durationMinutes) {
                                ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) {
                                    Text("\($0) min").tag($0)
                                }
                            }
                            .pickerStyle(.wheel)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            } footer: {
                Text(
                    durationMode == .indefinite
                        ?
                        "Becomes the new baseline. The basal profile is saved to the pump."
                        :
                        "Runs for the chosen duration, then reverts. The pump's saved basal is not changed."
                )
            }
            .listRowBackground(Color.chart)
        }

        // MARK: - Repeat (single picker for all kinds)

        private var repeatSection: some View {
            Section {
                Picker("Repeat", selection: $selectedKind) {
                    ForEach(RepeatKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
            }
            .listRowBackground(Color.chart)
        }

        // MARK: - Context-dependent config

        @ViewBuilder private var configSection: some View {
            switch selectedKind {
            case .once:
                onceConfigSection
            case .daily,
                 .weekdays,
                 .weekends:
                timeConfigSection
            case .customWeekly:
                weekdayChipsSection
                timeConfigSection
            case .customMonthly:
                monthDayGridSection
                timeConfigSection
            case .everyNDays:
                everyNDaysConfigSection
                timeConfigSection
            }
        }

        private var everyNDaysConfigSection: some View {
            Section {
                Stepper(value: $intervalDays, in: 1 ... 90) {
                    Text(
                        intervalDays == 1
                            ? String(localized: "Every day", comment: "Schedule interval stepper label for a 1-day interval")
                            : String(
                                localized: "Every \(intervalDays) days",
                                comment: "Schedule interval stepper label — interpolated value is the interval in days"
                            )
                    )
                }
                DatePicker("Starting on", selection: $anchorDay, displayedComponents: .date)
            } header: {
                Text("Interval")
            } footer: {
                Text(
                    "Counted from the start date, so a late activation does not shift later ones. For a cycle, add two schedules with the same interval: one starting on cycle day 1 (follicular profile), one on the first luteal day (luteal profile)."
                )
            }
            .listRowBackground(Color.chart)
        }

        private var onceConfigSection: some View {
            Section {
                DatePicker(
                    "Activates at",
                    selection: $onceDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            } footer: {
                Text("Fires once at the chosen date and time, then the schedule is removed.")
            }
            .listRowBackground(Color.chart)
        }

        private var timeConfigSection: some View {
            Section {
                HStack {
                    Text("Activates at")
                    Spacer()
                    Text(timeLabel)
                        .foregroundColor(showTimePicker ? .accentColor : .primary)
                        .onTapGesture { showTimePicker.toggle() }
                }
                if showTimePicker {
                    CustomTimeOnlyPicker(
                        selection: Binding(
                            get: { dateFromTime(state.draft.firesAt.first ?? .init(hour: 8, minute: 0)) },
                            set: { state.draft.firesAt = [timeFromDate($0)] }
                        ),
                        // TODO: restore to 15 after live-testing firing. 1-min for fast test cycles.
                        minuteInterval: 1
                    )
                    .frame(height: 160)
                }
            }
            .listRowBackground(Color.chart)
        }

        private var weekdayChipsSection: some View {
            Section {
                HStack(spacing: 6) {
                    ForEach(orderedWeekdays, id: \.self) { day in
                        WeekdayChip(day: day, isOn: weekdaySelection.contains(day)) {
                            if weekdaySelection.contains(day) {
                                weekdaySelection.remove(day)
                            } else {
                                weekdaySelection.insert(day)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            } header: {
                Text("Weekdays")
            } footer: {
                Text("Pick any combination. Example: M/W/F fires three times a week.")
            }
            .listRowBackground(Color.chart)
        }

        private var monthDayGridSection: some View {
            Section {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(1 ... 31, id: \.self) { day in
                        MonthDayCell(day: day, isOn: monthDaySelection.contains(day)) {
                            if monthDaySelection.contains(day) {
                                monthDaySelection.remove(day)
                            } else {
                                monthDaySelection.insert(day)
                            }
                        }
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("Days of month")
            } footer: {
                Text("Days that don't exist in a given month (e.g. 31 in February) are skipped.")
            }
            .listRowBackground(Color.chart)
        }

        // MARK: - Save (pill section at bottom, Trio pattern)

        private var saveSection: some View {
            let invalid = state.draft.validationError != nil
            return Section {
                Button {
                    commitDraft()
                    Task {
                        if await state.saveDraft() { onDismiss() }
                    }
                } label: {
                    Text("Save Schedule")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .disabled(invalid)
                .tint(.white)
            }
            .listRowBackground(invalid ? Color(.systemGray4) : Color(.systemBlue))
        }

        // MARK: - Helpers

        private var timeLabel: String {
            guard let t = state.draft.firesAt.first else { return "Tap to set" }
            return String(format: "%02d:%02d", t.hour, t.minute)
        }

        private var orderedWeekdays: [ProfileSchedule.Weekday] {
            [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
        }

        private func formatHM(hours: Int, minutes: Int) -> String {
            if hours == 0, minutes == 0 { return "Tap to set" }
            if minutes == 0 { return "\(hours) hr" }
            if hours == 0 { return "\(minutes) min" }
            return "\(hours) hr \(minutes) min"
        }

        private func dateFromTime(_ t: ProfileSchedule.TimeOfDay) -> Date {
            var comp = DateComponents()
            comp.hour = t.hour
            comp.minute = t.minute
            return Calendar.current.date(from: comp) ?? Date()
        }

        private func timeFromDate(_ d: Date) -> ProfileSchedule.TimeOfDay {
            let comp = Calendar.current.dateComponents([.hour, .minute], from: d)
            return .init(hour: comp.hour ?? 0, minute: comp.minute ?? 0)
        }

        private static func nextQuarterHour() -> Date {
            let cal = Calendar.current
            let now = Date()
            guard let rounded = cal.nextDate(
                after: now,
                matching: DateComponents(minute: 0),
                matchingPolicy: .nextTime
            ) else { return now.addingTimeInterval(3600) }
            return rounded
        }
    }

    struct WeekdayChip: View {
        let day: ProfileSchedule.Weekday
        let isOn: Bool
        let toggle: () -> Void

        var body: some View {
            Button(action: toggle) {
                Text(ProfileScheduleSummary.singleLetter(day))
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(isOn ? Color.accentColor : Color.clear)
                    )
                    .overlay(
                        Circle().strokeBorder(isOn ? Color.accentColor : Color.secondary, lineWidth: 1)
                    )
                    .foregroundColor(isOn ? .white : .primary)
            }
            .buttonStyle(.plain)
        }
    }

    struct MonthDayCell: View {
        let day: Int
        let isOn: Bool
        let toggle: () -> Void

        var body: some View {
            Button(action: toggle) {
                Text("\(day)")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 6).fill(isOn ? Color.accentColor : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(isOn ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1)
                    )
                    .foregroundColor(isOn ? .white : .primary)
            }
            .buttonStyle(.plain)
        }
    }
}

/// Time-of-day UIDatePicker wrapper (no date component, fixed minute interval). Mirrors
/// `CustomDateTimePicker` but `.time` mode and no `maximumDate` — schedules are future-facing.
struct CustomTimeOnlyPicker: UIViewRepresentable {
    @Binding var selection: Date
    var minuteInterval: Int

    class Coordinator: NSObject {
        var parent: CustomTimeOnlyPicker
        init(_ parent: CustomTimeOnlyPicker) { self.parent = parent }
        @objc func dateChanged(_ sender: UIDatePicker) { parent.selection = sender.date }
    }

    func makeUIView(context: Context) -> UIDatePicker {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.minuteInterval = minuteInterval
        picker.preferredDatePickerStyle = .wheels
        picker.addTarget(context.coordinator, action: #selector(Coordinator.dateChanged(_:)), for: .valueChanged)
        return picker
    }

    func updateUIView(_ uiView: UIDatePicker, context _: Context) {
        uiView.date = selection
        uiView.minuteInterval = minuteInterval
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
}
