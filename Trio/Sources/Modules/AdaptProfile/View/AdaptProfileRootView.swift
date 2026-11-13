import SwiftUI
import Swinject

extension AdaptProfile {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var showAddProfile = false
        @State private var draftEditorState: DraftEditorStateModel?
        @State private var editDraftState: DraftEditorStateModel?
        @State private var selectedProfile: AdaptProfileListItem?
        @State private var isConfirmDeletePresented = false
        @State private var activationTarget: AdaptProfileListItem?
        @State private var isConfirmRevertPresented = false
        @State private var showProfileHint = false
        @State private var profileHintDetent = PresentationDetent.large
        @State private var showRenameActive = false
        @State private var activeRenameText: String = ""
        @State private var revertErrorMessage: String?

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        /// True when RootView is presented as a modal sheet (set in MainRootView's `.sheet(item:)`
        /// wrapper). False when pushed inside the Settings nav stack, where the parent stack
        /// already supplies a Back button. Drives whether we show an explicit Close button in the
        /// top-leading toolbar slot. We can't use SwiftUI's `\.isPresented` here because it also
        /// returns true for views pushed onto a NavigationStack — leading to "Back" + "Close"
        /// stacking in the toolbar.
        @Environment(\.isInModalSheet) private var isInModalSheet

        private static let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            return f
        }()

        private var activeItem: AdaptProfileListItem? {
            state.items.first(where: { $0.isActive })
        }

        private var inactiveItems: [AdaptProfileListItem] {
            state.items.filter { !$0.isActive }
        }

        /// The profile that will become active when a timed activation expires. Pinned to the top
        /// of the inactive list so the user can see (and easily switch back to) the fallback.
        private var pinnedRevertItem: AdaptProfileListItem? {
            guard let active = activeItem,
                  active.expiresAt != nil,
                  let prevID = active.previousProfileID
            else { return nil }
            return inactiveItems.first(where: { $0.id == prevID })
        }

        private var otherInactiveItems: [AdaptProfileListItem] {
            guard let pinned = pinnedRevertItem else { return inactiveItems }
            return inactiveItems.filter { $0.id != pinned.id }
        }

        var body: some View {
            List {
                if let active = activeItem {
                    currentActiveProfile(active)
                }

                if let pinned = pinnedRevertItem, let active = activeItem, let expiresAt = active.expiresAt {
                    revertToSection(pinned, activatesAt: expiresAt)
                }

                upcomingSection

                if otherInactiveItems.isEmpty, !state.isLoading, pinnedRevertItem == nil {
                    defaultText
                } else if !otherInactiveItems.isEmpty {
                    profilesSection
                }
            }
            .listSectionSpacing(10)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Profiles")
            .navigationBarTitleDisplayMode(.large)
            .refreshable { await state.refresh() }
            .onAppear {
                configureView()
                Task { await state.refresh() }
            }
            .toolbar {
                if isInModalSheet {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: state.hideModal) {
                            Text("Close").foregroundColor(.tabBar)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        state.startNewDraft()
                        showAddProfile = true
                    }, label: {
                        HStack {
                            Text("Add Profile")
                            Image(systemName: "plus")
                        }
                    })
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showProfileHint = true }) {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showProfileHint) {
                SettingInputHintView(
                    hintDetent: $profileHintDetent,
                    shouldDisplayHint: $showProfileHint,
                    hintLabel: String(localized: "About Profiles", comment: "Help hint label on the AdaptProfile list screen"),
                    hintText: AnyView(profileAbstractHint),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            .sheet(isPresented: $showAddProfile, onDismiss: { draftEditorState = nil }) {
                addProfileSheet
            }
            .sheet(item: $editDraftState) { draftState in
                NavigationStack {
                    DraftEditorRootView(
                        state: draftState,
                        onSaved: {
                            editDraftState = nil
                            Task { await state.refresh() }
                        }
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { editDraftState = nil }
                        }
                    }
                }
            }
            .sheet(item: $activationTarget) { item in
                ActivateProfileView(
                    profile: item,
                    state: state,
                    onDismiss: { activationTarget = nil }
                )
            }
            .alert(
                "Rename active Profile",
                isPresented: $showRenameActive
            ) {
                TextField("Name", text: $activeRenameText)
                    .textInputAutocapitalization(.words)
                Button("Save") {
                    guard let item = activeItem else { return }
                    let trimmed = activeRenameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    state.rename(item, to: trimmed)
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Only the name is editable here. The active Profile's therapy values (Basal Rate, ISF, CR, BG Targets) and Algorithm Settings are edited directly in Therapy and Algorithm Settings while this Profile is active."
                )
            }
            .alert(
                "Save basal of Profile \"\(state.pendingScheduledActivation?.profileName ?? "")\" to pump?",
                isPresented: Binding(
                    get: { state.pendingScheduledActivation != nil },
                    set: { if !$0 { state.pendingScheduledActivation = nil } }
                ),
                presenting: state.pendingScheduledActivation
            ) { req in
                Button("Save to pump") {
                    Task { await state.confirmScheduledActivation(request: req) }
                }
                Button("Cancel", role: .cancel) {
                    Task { await state.skipScheduledActivation(request: req) }
                }
            } message: { _ in
                Text(
                    "An indefinite activation updates the pump's scheduled basal to match this profile. The pump's basal schedule will be overwritten."
                )
            }
            .safeAreaInset(edge: .bottom) {
                if let active = activeItem,
                   active.expiresAt != nil,
                   active.previousProfileID != nil
                {
                    stickyStopTempProfileButton
                }
            }
            .alert(
                "Stopping the temp profile failed",
                isPresented: Binding(
                    get: { revertErrorMessage != nil },
                    set: { if !$0 { revertErrorMessage = nil } }
                )
            ) {
                Button("OK") { revertErrorMessage = nil }
            } message: {
                Text(revertErrorMessage ?? "")
            }
        }

        private var addProfileSheet: some View {
            NavigationStack {
                AddProfileForm(
                    state: state,
                    onCancel: { showAddProfile = false },
                    onNext: {
                        draftEditorState = DraftEditorStateModel(
                            provider: state.provider,
                            insulinConcentration: state.settingsManager.settings.insulinConcentration,
                            units: state.settingsManager.settings.units,
                            sourceProfileName: activeItem?.name ?? String(
                                localized: "Current",
                                comment: "Fallback source-profile name used in the draft editor when no profile is currently active"
                            ),
                            sourceProfileID: activeItem?.id,
                            from: state.draft
                        )
                    }
                )
                .navigationDestination(isPresented: Binding(
                    get: { draftEditorState != nil },
                    set: { if !$0 { draftEditorState = nil } }
                )) {
                    if let draftState = draftEditorState {
                        DraftEditorRootView(
                            state: draftState,
                            onSaved: {
                                showAddProfile = false
                                Task { await state.refresh() }
                            }
                        )
                    }
                }
            }
        }

        private var defaultText: some View {
            Section {} header: {
                Text("Add a Profile by tapping 'Add Profile +' in the top right-hand corner of the screen.")
                    .textCase(nil)
                    .foregroundStyle(.secondary)
            }
        }

        private func currentActiveProfile(_ item: AdaptProfileListItem) -> some View {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(item.name) is active")
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(.white)
                    }
                    if let expiresAt = item.expiresAt {
                        let minutesLeft = max(0, Int(expiresAt.timeIntervalSinceNow / 60))
                        Text(minutesLeft > 0 ? Duration.seconds(TimeInterval(minutesLeft) * 60).formattedTimeSpan(.largestTwoUnits) : String(
                            localized: "Expiring",
                            comment: "Countdown label shown on the active-profile banner when less than a minute of a timed activation remains"
                        ))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    activeRenameText = item.name
                    showRenameActive = true
                }
            }
            .listRowBackground(Color.blue)
        }

        private func revertToSection(_ item: AdaptProfileListItem, activatesAt: Date) -> some View {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                        Text("Activates at \(activatesAt, style: .time)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.uturn.backward.circle")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isConfirmRevertPresented = true
                }
            } header: {
                Text("Reverts to")
            }
            .listRowBackground(Color.chart)
        }

        private var stickyStopTempProfileButton: some View {
            ZStack {
                Rectangle()
                    .frame(width: UIScreen.main.bounds.width, height: 65)
                    .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                    .background(.thinMaterial)
                    .opacity(0.8)
                    .clipShape(Rectangle())

                Button(action: {
                    isConfirmRevertPresented = true
                }, label: {
                    Text("Stop Temp Profile")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(10)
                })
                    .frame(width: UIScreen.main.bounds.width * 0.9, height: 40, alignment: .center)
                    .background(Color(.systemRed))
                    .tint(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(5)
                    .confirmationDialog(
                        "Stop the temporary profile?",
                        isPresented: $isConfirmRevertPresented,
                        titleVisibility: .visible
                    ) {
                        if let prevID = activeItem?.previousProfileID {
                            Button("Stop", role: .destructive) {
                                Task {
                                    // Revert path: the anchor invariant guarantees the pump already
                                    // holds the target's basal, so skip the pump write — same
                                    // contract as revertActiveProfile() and the expiry sweep.
                                    let outcome = await state.activate(
                                        id: prevID,
                                        durationMinutes: nil,
                                        confirmedPumpSync: true,
                                        skipPumpSync: true
                                    )
                                    switch outcome {
                                    case .needsPumpConfirm,
                                         .success:
                                        break
                                    case let .failed(message),
                                         let .pumpSyncFailed(message):
                                        revertErrorMessage = message
                                    }
                                }
                            }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(
                            "Restores the previous indefinite profile — the one whose basal schedule is already on the pump. No pump change needed."
                        )
                    }
            }
        }

        @ViewBuilder private var profileAbstractHint: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("What is a Profile?").bold()
                Text(
                    "A Profile is a named snapshot of your full therapy and algorithm setup — basal rate, ISF, CR, BG targets, plus every Algorithm Settings toggle. You keep one baseline profile and build alternates (sick day, exercise, menstrual cycle, travel, test modes) from it. Switching profiles swaps the entire setup in one tap."
                )

                Text("Activation modes").bold()
                Text(
                    "Indefinite: becomes your new baseline. The basal schedule is written to the pump and everything else is applied immediately."
                )
                Text(
                    "Timed (up to 24 h): applied until the duration expires, then auto-reverts to the indefinite baseline. Trio and the pump manager deliver the timed profile's basal rates live — the pump's saved basal schedule is NOT changed. If pump connectivity drops, the pump falls back to its last saved schedule."
                )

                Text("Reverting").bold()
                Text(
                    "Stopping a temp profile (or waiting for it to expire) returns you to the indefinite profile whose basal is already on the pump. Revert always targets that anchor — chains of temps can never leave the pump in an unfamiliar state."
                )

                Text("Creating a new profile").bold()
                Text(
                    "Tap \"Add Profile\" to start from the currently active profile's settings. First pick a percentage to scale Basal, ISF and CR in one step, then fine-tune any individual setting in the editor that follows."
                )
            }
        }

        private static let upcomingFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "EEE, dd.MM. HH:mm"
            return f
        }()

        private var upcomingSection: some View {
            Section {
                ForEach(state.upcoming.prefix(2)) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.upcomingFormatter.string(from: item.nextFire))
                                .font(.body)
                                .foregroundColor(item.profileExists ? .primary : .red)
                            Text(item.profileExists ? item.profileName : "Profile missing")
                                .font(.caption)
                                .foregroundColor(item.profileExists ? .secondary : .red)
                        }
                        Spacer()
                        Text(durationLabel(item.duration))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            state.disableSchedule(item)
                        } label: {
                            Label("Delete", systemImage: "trash.fill")
                                .tint(.red)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Upcoming")
                    Spacer()
                    NavigationLink(destination: ProfileScheduler.RootView(resolver: resolver)) {
                        HStack(spacing: 4) {
                            Text("Schedules")
                            Image(systemName: "chevron.right")
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .textCase(nil)
                    }
                }
            }
            .listRowBackground(Color.chart)
        }

        private func durationLabel(_ duration: ProfileSchedule.Duration) -> String {
            switch duration {
            case let .minutes(m):
                let h = m / 60
                let mm = m % 60
                if h ==
                    0 { return String(localized: "for \(mm) min", comment: "Upcoming-schedule row duration — under one hour") }
                if mm == 0 { return String(localized: "for \(h) h", comment: "Upcoming-schedule row duration — whole hours") }
                return String(localized: "for \(h) h \(mm) min", comment: "Upcoming-schedule row duration — hours and minutes")
            case .indefinite,
                 .untilNext:
                return String(
                    localized: "until next change",
                    comment: "Upcoming-schedule row duration — indefinite or until-next activation"
                )
            }
        }

        private var profilesSection: some View {
            Section {
                ForEach(otherInactiveItems) { item in
                    profileRow(for: item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            swipeActions(for: item)
                        }
                }
                .onMove(perform: reorderOtherInactive)
                .confirmationDialog(
                    "Delete the Profile \"\(selectedProfile?.name ?? "")\"?",
                    isPresented: $isConfirmDeletePresented,
                    titleVisibility: .visible
                ) {
                    if let itemToDelete = selectedProfile {
                        Button("Delete", role: .destructive) {
                            state.delete(itemToDelete)
                            selectedProfile = nil
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        selectedProfile = nil
                    }
                } message: {
                    Text("Any schedules that activate this profile will also be removed.")
                }
                .listRowBackground(Color.chart)
            } header: {
                Text("Profiles")
            } footer: {
                HStack {
                    Image(systemName: "hand.draw.fill").foregroundStyle(.primary)
                    Text("Swipe left to edit or delete a profile. Hold, drag and drop to reorder.")
                }
            }
        }

        private func openEditor(for item: AdaptProfileListItem) {
            Task { @MainActor in
                guard let content = await state.provider.loadProfileContent(id: item.id) else { return }
                editDraftState = DraftEditorStateModel(
                    provider: state.provider,
                    insulinConcentration: state.settingsManager.settings.insulinConcentration,
                    units: state.settingsManager.settings.units,
                    editing: content
                )
            }
        }

        @ViewBuilder private func swipeActions(for item: AdaptProfileListItem) -> some View {
            Button(role: .none) {
                selectedProfile = item
                isConfirmDeletePresented = true
            } label: {
                Label("Delete", systemImage: "trash.fill")
                    .tint(.red)
            }
            Button {
                openEditor(for: item)
            } label: {
                Label("Edit", systemImage: "pencil")
                    .tint(.blue)
            }
        }

        private func profileRow(for item: AdaptProfileListItem) -> some View {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.name)
                        Spacer()
                    }
                    HStack(spacing: 5) {
                        ForEach(labels(for: item), id: \.self) { label in
                            Text(label)
                            if label != labels(for: item).last {
                                Divider().frame(width: 1, height: 14)
                            }
                        }
                        Spacer()
                    }
                    .padding(.top, 2)
                    .foregroundColor(.secondary)
                    .font(.caption)
                }
                Image(systemName: "line.3.horizontal")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                activationTarget = item
            }
        }

        private func labels(for item: AdaptProfileListItem) -> [String] {
            var out: [String] = []
            if let source = item.sourceProfileName {
                out.append(source)
            }
            out += ProfileSummaryLabel.strings(
                appliedPercent: item.appliedPercent,
                dailyBasalRate: item.totalDailyBasal,
                tuning: .init(
                    preferencesTuned: item.preferencesChangedFromSource,
                    targetsTuned: item.targetsChangedFromSource
                )
            )
            return out
        }

        /// Reorder only the non-pinned subset. Preserves the pinned revert-profile's position at
        /// the top of the inactive list when rewriting orderPositions.
        private func reorderOtherInactive(from source: IndexSet, to destination: Int) {
            var reorderedOthers = otherInactiveItems
            reorderedOthers.move(fromOffsets: source, toOffset: destination)

            var newItems: [AdaptProfileListItem] = []
            if let active = activeItem { newItems.append(active) }
            if let pinned = pinnedRevertItem { newItems.append(pinned) }
            newItems.append(contentsOf: reorderedOthers)
            state.items = newItems
            let ids = newItems.map(\.id)
            Task {
                await state.provider.applyOrdering(ids)
                await state.refresh()
            }
        }
    }
}
