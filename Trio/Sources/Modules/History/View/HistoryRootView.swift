import CoreData
import SwiftUI
import Swinject

extension History {
    struct RootView: BaseView {
        let resolver: Resolver

        @State var state = StateModel()
        @State private var deletionTarget: History.DeletionTarget?
        @State private var showFutureEntries: Bool = false
        @State private var showManualGlucose: Bool = false
        @State private var isAmountUnconfirmed: Bool = true
        @State private var showTreatmentTypeFilter = false
        @State private var selectedTreatmentTypes: Set<TreatmentType> = Set(TreatmentType.allCases)
        @State private var filterPopoverAnchor: CGRect = .zero

        @Environment(\.colorScheme) var colorScheme
        @Environment(\.managedObjectContext) var context
        @Environment(AppState.self) var appState

        @FetchRequest(
            entity: GlucoseStored.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
            predicate: NSPredicate.predicateForOneDayAgo,
            animation: .bouncy
        ) var glucoseStored: FetchedResults<GlucoseStored>

        @FetchRequest(
            entity: PumpEventStored.entity(),
            sortDescriptors: [NSSortDescriptor(key: "timestamp", ascending: false)],
            predicate: NSPredicate.pumpHistoryLast24h,
            animation: .bouncy
        ) var pumpEventStored: FetchedResults<PumpEventStored>

        @FetchRequest(
            entity: CarbEntryStored.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)],
            predicate: NSPredicate.carbsHistory,
            animation: .bouncy
        ) var carbEntryStored: FetchedResults<CarbEntryStored>

        @FetchRequest(
            entity: OverrideRunStored.entity(),
            sortDescriptors: [NSSortDescriptor(key: "startDate", ascending: false)],
            predicate: NSPredicate.overridesRunStoredFromOneDayAgo,
            animation: .bouncy
        ) var overrideRunStored: FetchedResults<OverrideRunStored>

        @FetchRequest(
            entity: TempTargetRunStored.entity(),
            sortDescriptors: [NSSortDescriptor(key: "startDate", ascending: false)],
            predicate: NSPredicate.tempTargetRunStoredFromOneDayAgo,
            animation: .bouncy
        ) var tempTargetRunStored: FetchedResults<TempTargetRunStored>

        @FetchRequest(
            entity: ProfileRunStored.entity(),
            sortDescriptors: [NSSortDescriptor(key: "startDate", ascending: false)],
            predicate: NSPredicate.profileRunStoredFromOneDayAgo,
            animation: .bouncy
        ) var profileRunStored: FetchedResults<ProfileRunStored>

        private func resolvedType(for event: PumpEventStored) -> String {
            if let bolus = event.bolus {
                if bolus.isSMB {
                    return String(localized: "SMB", comment: "Treatment history type label — SMB (super-microbolus)")
                } else { // for manual and external Boli
                    return String(localized: "Bolus", comment: "Treatment history type label — Bolus")
                }
            } else if event.tempBasal != nil {
                return String(localized: "Temp Basal", comment: "Treatment history type label — temporary basal")
            } else {
                // Group all other pump events (like Pump Suspended, Pump Resume, etc.) as "Pump State"
                return String(localized: "Pump State", comment: "Treatment history type label — pump state change")
            }
        }

        private var allTreatmentTypes: [String] {
            let filtered = pumpEventStored
                .filter { !showFutureEntries ? $0.timestamp ?? Date() <= Date() : true }
            let pumpTypes = filtered.map { resolvedType(for: $0) }

            // Add "Carbs" to the list if there are any carb entries
            var allTypes = Array(Set(pumpTypes)).sorted()
            if !carbEntryStored.isEmpty {
                allTypes.append(String(localized: "Carbs", comment: "Treatment history type label — carbohydrate entry"))
            }

            return allTypes.sorted()
        }

        private var manualGlucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mgdL {
                formatter.maximumIntegerDigits = 3
                formatter.maximumFractionDigits = 0
            } else {
                formatter.maximumIntegerDigits = 2
                formatter.minimumFractionDigits = 0
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        var body: some View {
            let toggleCustomPicker: Bool = state.autoisf

            ZStack(alignment: .center, content: {
                VStack {
                    if toggleCustomPicker {
                        let textHeight: CGFloat = UIFont.preferredFont(forTextStyle: .footnote).lineHeight
                        HStack(spacing: 2) {
                            HStack {
                                Text(History.Mode.treatments.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .layoutPriority(1)
                            }
                            .layoutPriority(1)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(state.mode == .treatments ? Color.loopGray.opacity(0.4) : Color.clear)
                            .cornerRadius(8)
                            .onTapGesture {
                                withAnimation {
                                    state.mode = .treatments
                                }
                            }
                            //                            Divider().frame(height: textHeight + 4).background(Color.secondary)
                            //                            HStack {
                            //                                Text(History.Mode.meals.name)
                            //                                    .font(.subheadline)
                            //                                    .lineLimit(1)
                            //                                    .minimumScaleFactor(0.5)
                            //                            }
                            //                            .padding(.vertical, 6)
                            //                            .padding(.horizontal, 8)
                            //                            .background(state.mode == .meals ? Color.loopGray.opacity(0.4) : Color.clear)
                            //                            .cornerRadius(8)
                            //                            .onTapGesture {
                            //                                withAnimation {
                            //                                    state.mode = .meals
                            //                                }
                            //                            }
                            Divider().frame(height: textHeight + 4).background(Color.secondary)
                            HStack {
                                Text(History.Mode.glucose.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .layoutPriority(1)
                            }
                            .layoutPriority(1)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(state.mode == .glucose ? Color.loopGray.opacity(0.4) : Color.clear)
                            .cornerRadius(8)
                            .onTapGesture {
                                withAnimation {
                                    state.mode = .glucose
                                }
                            }
                            Divider().frame(height: textHeight + 4).background(Color.secondary)
                            HStack {
                                Text(History.Mode.adjustments.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .layoutPriority(1)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(state.mode == .adjustments ? Color.loopGray.opacity(0.4) : Color.clear)
                            .cornerRadius(8)
                            .onTapGesture {
                                withAnimation {
                                    state.mode = .adjustments
                                }
                            }
                            Divider().frame(height: textHeight + 4).background(Color.secondary)
                            HStack(spacing: 2) {
                                Text("autoISF")
                                    .font(.subheadline)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                    .layoutPriority(2)
                                Image(systemName: "list.bullet.rectangle")
                                    .foregroundColor(Color.uam)
                                    .font(.subheadline)
                            }

                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(Color.clear)
                            .cornerRadius(8)
                            .onTapGesture {
                                state.showModal(for: .autoISFHistory)
                            }
                        }
                        .font(.footnote)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                        .padding(.horizontal)
                    } else {
                        Picker("Mode", selection: $state.mode) {
                            // Meals are listed within the treatments list, so no separate mode.
                            ForEach(Mode.allCases.filter { $0 != .meals }) { item in
                                Text(item.name).tag(item)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                    }

                    Form {
                        switch state.mode {
                        case .treatments: treatmentsList
                        case .glucose: glucoseList
                        case .meals: mealsList
                        case .adjustments: adjustmentsList
                        }
                    }.scrollContentBackground(.hidden)
                        .background(appState.trioBackgroundColor(for: colorScheme))
                }.blur(radius: state.waitForSuggestion ? 8 : 0)

                if state.waitForSuggestion && state.isGlucoseDataFresh(glucoseStored.first?.date) {
                    CustomProgressView(text: progressText.displayName)
                }
            })
                .background(appState.trioBackgroundColor(for: colorScheme))
                .onAppear(perform: configureView)
                .onAppear(perform: state.updateAutoisf)
                .onDisappear {
                    state.carbEntryDeleted = false
                    state.insulinEntryDeleted = false
                }
                .navigationTitle("History")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    // fallback pathway: the home panel's stats face can be
                    // displaced by higher-priority states
                    ToolbarItem(placement: .topBarLeading, content: {
                        Button(
                            action: {
                                appState.statSelectedViewType = .glucose
                                appState.statSelectedInsulinTimeInterval = .day
                                state.showModal(for: .statistics)
                            },
                            label: {
                                HStack {
                                    Image(systemName: "chart.bar.xaxis.ascending.badge.clock", variableValue: 0.5)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(
                                            Color.tabBar.opacity(0.7), // first layer: the bars
                                            Color.tabBar.opacity(0.9),
                                            Color.tabBar // second layer: the clock badge
                                        )
                                        .scaleEffect(x: -1)
                                    Text("Statistics")
                                }
                            }
                        )
                    })
                    ToolbarItem(placement: .topBarTrailing, content: {
                        addButton({
                            showManualGlucose = true
                            state.manualGlucose = 0
                        })
                    })
                }
                .sheet(isPresented: $showManualGlucose) {
                    addGlucoseView()
                }
                .sheet(isPresented: $state.showCarbEntryEditor) {
                    if let carbEntry = state.carbEntryToEdit {
                        CarbEntryEditorView(state: state, carbEntry: carbEntry)
                    }
                }
                .glassActionSheet(
                    Text(deletionTarget?.title(units: state.units) ?? ""),
                    message: deletionTarget.map { Text($0.message(units: state.units)) },
                    isPresented: Binding(
                        get: { deletionTarget != nil },
                        set: { if !$0 { deletionTarget = nil } }
                    ),
                    actions: [
                        GlassSheetAction("Delete", role: .destructive) {
                            switch deletionTarget {
                            case let .glucose(glucose):
                                state.invokeGlucoseDeletionTask(glucose.objectID)
                            case let .insulin(pumpEvent):
                                state.invokeInsulinDeletionTask(pumpEvent.objectID)
                            case let .carbs(carbEntry):
                                state.invokeCarbDeletionTask(
                                    carbEntry.objectID,
                                    isFpuOrComplexMeal: deletionTarget?.isFpuOrComplexMeal ?? false
                                )
                            case .none:
                                break
                            }
                        }
                    ]
                )
        }

        @ViewBuilder func addButton(_ action: @escaping () -> Void) -> some View {
            Button(
                action: action,
                label: {
                    HStack {
                        Text("Add Glucose")
                        Image(systemName: "plus")
                            .font(.title2)
                    }
                }
            )
        }

        private var progressText: ProgressText {
            switch (state.carbEntryDeleted, state.insulinEntryDeleted) {
            case (true, false):
                return .updatingCOB
            case(false, true):
                return .updatingIOB
            default:
                return .updatingHistory
            }
        }

        private var logGlucoseButton: some View {
            Button(
                action: {
                    showManualGlucose = true
                    state.manualGlucose = 0
                },
                label: {
                    Text("Log Glucose")
                        .foregroundColor(Color.accentColor)
                    Image(systemName: "plus")
                        .foregroundColor(Color.accentColor)
                }
            ).buttonStyle(.borderless)
        }

        private var mealsList: some View {
            List {
                HStack {
                    Text("Type").foregroundStyle(.secondary)
                    Spacer()
                    filterEntriesButton
                }
                if !carbEntryStored.isEmpty {
                    ForEach(carbEntryStored.filter({ !showFutureEntries ? $0.date ?? Date() <= Date() : true })) { item in
                        mealView(item)
                    }
                } else {
                    ContentUnavailableView(
                        "No data.",
                        systemImage: "syringe"
                    )
                }
            }
            .listRowBackground(Color.chart)
        }

        private var combinedTreatments: [TreatmentItem] {
            // Convert Pump Events to TreatmentItem with filtering
            let treatments = pumpEventStored.compactMap { event -> TreatmentItem? in
                guard let id = event.objectID as NSManagedObjectID? else {
                    print("🚨 PumpEventStored has nil objectID") // Debugging
                    return nil
                }

                // Apply date filter
                let passesDateFilter = showFutureEntries || (event.timestamp ?? Date() <= Date())
                guard passesDateFilter else { return nil }

                // Apply treatment type filter
                let passesTreatmentFilter: Bool
                if let bolus = event.bolus {
                    if bolus.isSMB {
                        passesTreatmentFilter = selectedTreatmentTypes.contains(.smb)
                    } else if bolus.isExternal {
                        passesTreatmentFilter = selectedTreatmentTypes.contains(.externalBolus)
                    } else {
                        passesTreatmentFilter = selectedTreatmentTypes.contains(.bolus)
                    }
                } else if event.tempBasal != nil {
                    passesTreatmentFilter = selectedTreatmentTypes.contains(.tempBasal)
                } else if event.type == "PumpSuspend" {
                    passesTreatmentFilter = selectedTreatmentTypes.contains(.suspend)
                } else {
                    passesTreatmentFilter = selectedTreatmentTypes.contains(.other)
                }

                guard passesTreatmentFilter else { return nil }

                return TreatmentItem(
                    id: id,
                    timestamp: event.timestamp ?? Date(),
                    isMeal: false,
                    pumpEvent: event,
                    carbEntry: nil
                )
            }

            // Convert Carb Entries to TreatmentItem with filtering
            let meals = carbEntryStored.compactMap { meal -> TreatmentItem? in
                guard let id = meal.objectID as NSManagedObjectID? else {
                    print("🚨 CarbEntryStored has nil objectID") // Debugging
                    return nil
                }

                // Apply date filter
                let passesDateFilter = showFutureEntries || (meal.date ?? Date() <= Date())
                guard passesDateFilter else { return nil }

                // Apply treatment type filter for carbs
                guard selectedTreatmentTypes.contains(.carbs) else { return nil }

                return TreatmentItem(
                    id: id,
                    timestamp: meal.date ?? Date(),
                    isMeal: true,
                    pumpEvent: nil,
                    carbEntry: meal
                )
            }

            // Merge and sort chronologically
            let combined = (treatments + meals).sorted { $0.timestamp > $1.timestamp }

            return combined
        }

        private var treatmentsHeader: some View {
            HStack {
                filterTreatmentsButton
                Spacer()
                filterFutureEntriesButton
                Spacer()
                Text("Time").foregroundStyle(.secondary)
            }
        }

        private var filterTreatmentsButton: some View {
            Button(action: {
                showTreatmentTypeFilter.toggle()
            }) {
                HStack {
                    Text("Filter")
                    Image(
                        systemName: selectedTreatmentTypes.count == TreatmentType.allCases.count
                            ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
                    )
                    if selectedTreatmentTypes.count < TreatmentType.allCases.count {
                        Text(verbatim: "(\(selectedTreatmentTypes.count)/\(TreatmentType.allCases.count))")
                    }
                }.foregroundColor(Color.accentColor)
            }
            .popover(isPresented: $showTreatmentTypeFilter, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 20) {
                    Button(action: {
                        if selectedTreatmentTypes.count == TreatmentType.allCases.count {
                            // Deselect all - keep at least one selected
                            selectedTreatmentTypes = []
                        } else {
                            // Select all
                            selectedTreatmentTypes = Set(TreatmentType.allCases)
                        }
                    }) {
                        HStack(spacing: 20) {
                            Image(
                                systemName: selectedTreatmentTypes.count == TreatmentType.allCases.count
                                    ? "checkmark.square.fill" : "square"
                            )
                            .frame(width: 20)
                            .foregroundColor(Color.accentColor)
                            Text(
                                selectedTreatmentTypes.count == TreatmentType.allCases
                                    .count ? String(
                                        localized: "Deselect All",
                                        comment: "Toggle button in History filter popover — deselects every treatment type"
                                    ) : String(
                                        localized: "Select All",
                                        comment: "Toggle button in History filter popover — selects every treatment type"
                                    )
                            )
                            .foregroundColor(Color.primary)
                        }.padding(4)
                    }
                    .buttonStyle(.borderless)

                    Divider()

                    ForEach(TreatmentType.allCases, id: \.rawValue) { treatmentType in
                        Button(action: {
                            toggleTreatmentType(treatmentType)
                        }) {
                            HStack(spacing: 20) {
                                Image(
                                    systemName: selectedTreatmentTypes
                                        .contains(treatmentType) ? "checkmark.square.fill" : "square"
                                )
                                .frame(width: 20)
                                .foregroundColor(Color.accentColor)
                                Text(treatmentType.displayName)
                                    .foregroundColor(Color.primary)
                            }.padding(4)
                        }
                        .buttonStyle(.borderless)
                    }

                    Divider()

                    Button("Done") {
                        showTreatmentTypeFilter = false
                    }
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderless)
                }
                .padding()
                .presentationCompactAdaptation(.popover)
                .background(Color.chart)
            }
        }

        private var filterFutureEntriesButton: some View {
            Button(
                action: {
                    showFutureEntries.toggle()
                },
                label: {
                    HStack {
                        Text(
                            showFutureEntries ?
                                String(
                                    localized: "Hide Future",
                                    comment: "Toggle button in History — hide entries with future timestamps"
                                ) : String(
                                    localized: "Show Future",
                                    comment: "Toggle button in History — show entries with future timestamps"
                                )
                        )
                        .foregroundColor(Color.accentColor)
                        Image(systemName: showFutureEntries ? "eye.slash" : "eye")
                            .foregroundColor(Color.accentColor)
                    }
                }
            ).buttonStyle(.borderless)
        }

        private func toggleTreatmentType(_ type: TreatmentType) {
            if selectedTreatmentTypes.contains(type) {
                selectedTreatmentTypes.remove(type)
            } else {
                selectedTreatmentTypes.insert(type)
            }
        }

        private var treatmentsList: some View {
            List {
                treatmentsHeader
                    .listRowSeparator(.hidden)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .frame(height: 1.5)
                            .foregroundColor(Color.secondary.opacity(0.3))
                            .offset(y: 6)
                    }
                if !combinedTreatments.isEmpty {
                    // Use combinedTreatments which now includes filtering
                    ForEach(combinedTreatments) { item in
                        if item.isMeal, let meal = item.carbEntry {
                            mealView(meal)
                        } else if let pumpEvent = item.pumpEvent {
                            treatmentView(pumpEvent)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        String(localized: "No data.", comment: "Empty-state text on History Treatments list"),
                        systemImage: "syringe"
                    )
                }
            }
            .listRowBackground(Color.chart)
        }

        private var adjustmentsList: some View {
            List {
                HStack {
                    Text("Adjustment").foregroundStyle(.secondary)
                    Spacer()
                }
                if !combinedAdjustments.isEmpty {
                    ForEach(combinedAdjustments) { item in
                        adjustmentView(for: item)
                    }
                } else {
                    ContentUnavailableView(
                        String(localized: "No data.", comment: "Empty-state text on History Adjustments list"),
                        systemImage: "clock.arrow.2.circlepath"
                    )
                }
            }
            .listRowBackground(Color.chart)
        }

        private func profileAdjustmentItem(_ run: ProfileRunStored) -> AdjustmentItem {
            let summary = ProfileSummaryLabel.shortStrings(
                appliedPercent: run.profile?.appliedPercent?.decimalValue,
                dailyBasalRate: run.profile?.therapy?.basalProfile.totalDailyBasal
            )
            return AdjustmentItem(
                id: run.objectID,
                name: run.name ?? String(
                    localized: "Profile",
                    comment: "Fallback name on History Adjustments list when a profile run has no name"
                ),
                startDate: run.startDate ?? Date(),
                endDate: run.endDate ?? Date(),
                target: nil,
                type: .profile,
                wasIndefinite: run.wasIndefinite,
                profileSummary: summary
            )
        }

        @ViewBuilder private func adjustmentIcon(for item: AdjustmentItem) -> some View {
            switch item.type {
            case .override:
                Image(systemName: "clock.arrow.2.circlepath")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(
                        Color.primary,
                        Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569)
                    )
            case .tempTarget:
                Image(systemName: "arrow.up.circle.badge.clock")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.primary, Color.loopGreen)
            case .profile:
                if item.wasIndefinite {
                    Image(systemName: "person.2", variableValue: 0.58)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.blue, Color.white, Color.white)
                        .font(.system(size: 10, weight: .regular))
                        .frame(width: 17, height: 17)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.blue, lineWidth: 1.3)
                        )
                } else {
                    Image(systemName: "person.2.arrow.trianglehead.counterclockwise")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.primary, Color.blue)
                        .font(.system(size: 18))
                }
            }
        }

        private func formatAdjustmentDuration(from start: Date, to end: Date) -> String {
            let totalSeconds = max(0, Int(end.timeIntervalSince(start)))
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            if hours > 0 {
                return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
            }
            return minutes > 0 ? "\(minutes)m" : "<1m"
        }

        private var combinedAdjustments: [AdjustmentItem] {
            let overrides = overrideRunStored.map { override -> AdjustmentItem in
                AdjustmentItem(
                    id: override.objectID,
                    name: override.name ?? String(
                        localized: "Override",
                        comment: "Fallback name on History Adjustments list when an override run has no name"
                    ),
                    startDate: override.startDate ?? Date(),
                    endDate: override.endDate ?? Date(),
                    target: override.target?.decimalValue,
                    type: .override
                )
            }

            let tempTargets = tempTargetRunStored.map { tempTarget -> AdjustmentItem in
                AdjustmentItem(
                    id: tempTarget.objectID,
                    name: tempTarget.name ?? String(
                        localized: "Temp Target",
                        comment: "Fallback name on History Adjustments list when a temp target run has no name"
                    ),
                    startDate: tempTarget.startDate ?? Date(),
                    endDate: tempTarget.endDate ?? Date(),
                    target: tempTarget.target?.decimalValue,
                    type: .tempTarget
                )
            }

            let profiles = profileRunStored.map(profileAdjustmentItem)

            let combined = overrides + tempTargets + profiles
            return combined.sorted {
                if $0.startDate == $1.startDate {
                    return $0.endDate > $1.endDate
                }
                return $0.startDate > $1.startDate
            } }

        private struct AdjustmentItem: Identifiable {
            let id: NSManagedObjectID
            let name: String
            let startDate: Date
            let endDate: Date
            let target: Decimal?
            let type: AdjustmentType
            var wasIndefinite: Bool = false
            var profileSummary: [String] = []
        }

        private enum AdjustmentType {
            case override
            case tempTarget
            case profile

            var symbolName: String {
                switch self {
                case .override:
                    return "clock.arrow.2.circlepath"
                case .tempTarget:
                    return "arrow.up.circle.badge.clock"
                case .profile:
                    return "person.crop.circle.badge.clock"
                }
            }

            var symbolColor: Color {
                switch self {
                case .override:
                    return .orange
                case .tempTarget:
                    return .blue
                case .profile:
                    return .teal
                }
            }
        }

        @ViewBuilder private func adjustmentView(for item: AdjustmentItem) -> some View {
            let formattedDates =
                "\(Formatter.timeFormatter.string(from: item.startDate)) - \(Formatter.timeFormatter.string(from: item.endDate))"

            let durationString = formatAdjustmentDuration(from: item.startDate, to: item.endDate)

            let targetLabel: String? = item.target.map { "\($0) \(state.units.rawValue)" }

            let labels: [String] = ([targetLabel].compactMap { $0 } + item.profileSummary + [durationString, formattedDates])
                .filter { !$0.isEmpty }

            let iconRotation: Double = item.type == .tempTarget ? 90 : 0

            ZStack(alignment: .trailing) {
                HStack {
                    VStack(alignment: .leading) {
                        HStack {
                            adjustmentIcon(for: item)
                                .rotationEffect(.degrees(iconRotation))
                            Text(item.name)
                                .font(.headline)
                            Spacer()
                        }
                        HStack(spacing: 5) {
                            ForEach(labels, id: \.self) { label in
                                Text(label)
                                if label != labels.last {
                                    Divider()
                                }
                            }
                            Spacer()
                        }
                        .padding(.top, 2)
                        .foregroundColor(.secondary)
                        .font(.caption)
                    }
                    .contentShape(Rectangle())
                }
            }
            .padding(.vertical, 8)
        }

        private var glucoseList: some View {
            List {
                HStack {
                    Text("Values")
                    Spacer()
                    Text("Time")
                }.foregroundStyle(.secondary)

                if !glucoseStored.isEmpty {
                    ForEach(glucoseStored) { glucose in
                        HStack {
                            Text(formatGlucose(Decimal(glucose.glucose), isManual: glucose.isManual))
                            if glucose.isManual {
                                Image(systemName: "drop.fill").symbolRenderingMode(.monochrome).foregroundStyle(.red)
                            } else {
                                Text("\(glucose.directionEnum?.symbol ?? "--")")
                            }

                            if state.settingsManager.settings.smoothGlucose, !glucose.isManual,
                               let smoothedGlucose = glucose.smoothedGlucose, smoothedGlucose != 0
                            {
                                let smoothedGlucoseForDisplay = state.units == .mgdL ? smoothedGlucose
                                    .description : smoothedGlucose.decimalValue
                                    .formattedAsMmolL

                                (
                                    Text("(") +
                                        Text(Image(systemName: "sparkles")) +
                                        Text(" ") +
                                        Text("\(smoothedGlucoseForDisplay)") +
                                        Text(")")
                                ).foregroundStyle(.secondary)
                                    .padding(.leading, 10)
                            }

                            Spacer()
                            Text(Formatter.dateFormatter.string(from: glucose.date ?? Date()))
                        }.swipeActions {
                            Button(
                                "Delete",
                                systemImage: "trash.fill",
                                role: .none,
                                action: { deletionTarget = .glucose(glucose) }
                            ).tint(.red)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        String(localized: "No data.", comment: "Empty-state text on History Glucose list"),
                        systemImage: "drop.fill"
                    )
                }
            }.listRowBackground(Color.chart)
        }

        @ViewBuilder private func addGlucoseView() -> some View {
            let limitLow: Decimal = state.units == .mgdL ? Decimal(14) : 14.asMmolL
            let limitHigh: Decimal = state.units == .mgdL ? Decimal(720) : 720.asMmolL

            NavigationView {
                VStack {
                    Form {
                        Section {
                            HStack {
                                Text("New Glucose")
                                TextFieldWithToolBar(
                                    text: $state.manualGlucose,
                                    placeholder: " ... ",
                                    keyboardType: state.units == .mgdL ? .numberPad : .decimalPad,
                                    numberFormatter: manualGlucoseFormatter,
                                    initialFocus: true,
                                    unitsText: state.units.rawValue
                                )
                            }
                        }.listRowBackground(Color.chart)

                        Section {
                            HStack {
                                Button {
                                    state.addManualGlucose()
                                    isAmountUnconfirmed = false
                                    showManualGlucose = false
                                    state.mode = .glucose
                                }
                                label: { Text("Save") }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .disabled(state.manualGlucose < limitLow || state.manualGlucose > limitHigh)
                            }
                        }
                        .listRowBackground(
                            state.manualGlucose < limitLow || state
                                .manualGlucose > limitHigh ? Color(.systemGray4) : Color(.systemBlue)
                        )
                        .tint(.white)
                    }.scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
                }
                .onAppear(perform: configureView)
                .navigationTitle("Add Glucose")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            showManualGlucose = false
                        }
                    }
                }
            }
        }

        private var filterEntriesButton: some View {
            Button(action: { showFutureEntries.toggle() }, label: {
                HStack {
                    Text(showFutureEntries ? String(
                        localized: "Hide Future",
                        comment: "Toggle button on History Carb Entries view — hide entries with future timestamps"
                    ) : String(
                        localized: "Show Future",
                        comment: "Toggle button on History Carb Entries view — show entries with future timestamps"
                    ))
                        .foregroundColor(Color.secondary)
                    Image(systemName: showFutureEntries ? "calendar.badge.minus" : "calendar.badge.plus")
                }.frame(maxWidth: .infinity, alignment: .center)
            }).buttonStyle(.borderless)
        }

        @ViewBuilder private func treatmentView(_ item: PumpEventStored) -> some View {
            HStack {
                if let bolus = item.bolus, let amount = bolus.amount {
                    if bolus.isSMB {
                        Image(systemName: "triangle.fill")
                            .foregroundColor(Color.insulin) // Color the triangle as you need
                            .rotationEffect(.degrees(180)) // Rotate the triangle
                            .scaleEffect(x: 0.8, y: 0.9) // Distort the triangle to fit
                            .overlay(
                                // White outline for the triangle using stroke
                                Image(systemName: "triangle")
                                    .foregroundColor(Color.primary) // White outline
                                    .rotationEffect(.degrees(180))
                                    .scaleEffect(x: 0.8, y: 0.9)
                            )
                    } else if bolus.isExternal {
                        Image(systemName: "diamond.fill")
                            .foregroundColor(Color.purple) // Color the rhombus as you need
                            .scaleEffect(x: 0.75, y: 0.9) // Distort the rhombus
                            .overlay(
                                // White outline for the rhombus using stroke
                                Image(systemName: "diamond")
                                    .foregroundColor(Color.primary) // White outline
                                    .scaleEffect(x: 0.75, y: 0.9)
                            )
                    } else {
                        Image(systemName: "circle.fill")
                            .foregroundColor(Color.teal) // Default to circle
                            .overlay(
                                // White outline for the circle using stroke
                                Circle()
                                    .stroke(Color.primary, lineWidth: 1)
                                    .padding(2)
                            )
                    }

                    Text(
                        bolus
                            .isSMB ? String(localized: "SMB", comment: "Treatment row label — SMB") :
                            (
                                item
                                    .type ??
                                    String(
                                        localized: "Bolus",
                                        comment: "Treatment row label — fallback when event type is missing"
                                    )
                            )
                    )
                    Text(
                        (Formatter.insulinFormatterToIncrement(for: state.bolusIncrement).string(from: amount) ?? "0") +
                            String(localized: " U", comment: "Insulin unit")
                    )
                    .foregroundColor(.secondary)
                    if bolus.isExternal {
                        Text(String(localized: "External", comment: "External Insulin")).foregroundColor(.secondary)
                    }
                } else if let tempBasal = item.tempBasal, let rate = tempBasal.rate {
                    Image(systemName: "circle.fill").foregroundColor(Color.insulin.opacity(0.4))
                    Text("Temp Basal")
                    Text(
                        (Formatter.insulinFormatterToIncrement(for: state.bolusIncrement).string(from: rate) ?? "0") +
                            String(localized: " U/hr", comment: "Unit insulin per hour")
                    )
                    .foregroundColor(.secondary)
                    if tempBasal.duration > 0 {
                        Text("\(tempBasal.duration.string) min").foregroundColor(.secondary)
                    }
                } else {
                    Image(systemName: "circle.fill").foregroundColor(Color.loopGray)
                    Text(
                        item
                            .type ??
                            String(
                                localized: "Pump Event",
                                comment: "Treatment row label — fallback when pump event type is missing"
                            )
                    )
                }
                Spacer()
                Text(Formatter.timeFormatter.string(from: item.timestamp ?? Date())).moveDisabled(true)
            }
            .swipeActions {
                if item.bolus != nil {
                    Button(
                        "Delete",
                        systemImage: "trash.fill",
                        role: .none,
                        action: { deletionTarget = .insulin(item) }
                    ).tint(.red)
                }
            }
        }

        @ViewBuilder private func mealView(_ meal: CarbEntryStored) -> some View {
            let isFPU = meal.isFPU

            VStack {
                HStack {
                    if meal.isFPU {
                        Image(systemName: "circle.fill").foregroundColor(Color.orange.opacity(0.5))
                        Text("Fat / Protein")
                        Text(
                            (Formatter.decimalFormatterWithTwoFractionDigits.string(for: meal.carbs) ?? "0") +
                                String(localized: " g", comment: "gram of carbs")
                        )
                    } else {
                        Image(systemName: "circle.fill").foregroundColor(Color.loopYellow)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary, lineWidth: 1)
                                    .padding(2)
                            )
                        Text("Carbs")
                        Text(
                            (Formatter.decimalFormatterWithTwoFractionDigits.string(for: meal.carbs) ?? "0") +
                                String(localized: " g", comment: "gram of carb equilvalents")
                        )
                    }
                    Spacer()
                    Text(Formatter.dateFormatter.string(from: meal.date ?? Date()))
                        .moveDisabled(true)
                }
                if let note = meal.note, note != "" {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text(note)
                        Spacer()
                    }.padding(.top, 5).foregroundColor(.secondary)
                }
            }
            .swipeActions {
                Button(
                    "Delete",
                    systemImage: "trash.fill",
                    role: .none,
                    action: { deletionTarget = .carbs(meal) }
                ).tint(.red)

                Button(
                    "Edit",
                    systemImage: "pencil",
                    role: .none,
                    action: {
                        state.carbEntryToEdit = meal
                        state.showCarbEntryEditor = true
                    }
                )
                .tint(!state.useFPUconversion && isFPU ? Color(.systemGray4) : Color.blue)
                .disabled(!state.useFPUconversion && isFPU)
            }
        }

        private func formatGlucose(_ value: Decimal, isManual: Bool) -> String {
            let formatter = isManual ? manualGlucoseFormatter : Formatter.glucoseFormatter(for: state.units)
            let glucoseValue = state.units == .mmolL ? value.asMmolL : value
            let formattedValue = formatter.string(from: glucoseValue as NSNumber) ?? "--"
            return formattedValue
        }
    }

    /// A unified struct that can represent either a pump event or a carb entry
    private struct TreatmentItem: Identifiable {
        let id: NSManagedObjectID
        let timestamp: Date
        let isMeal: Bool
        let pumpEvent: PumpEventStored?
        let carbEntry: CarbEntryStored?

        // Provide a fallback for timestamp to avoid nil crashes
        init(id: NSManagedObjectID, timestamp: Date?, isMeal: Bool, pumpEvent: PumpEventStored?, carbEntry: CarbEntryStored?) {
            self.id = id
            self.timestamp = timestamp ?? Date() // Prevents nil timestamp crashes
            self.isMeal = isMeal
            self.pumpEvent = pumpEvent
            self.carbEntry = carbEntry
        }
    }
}
