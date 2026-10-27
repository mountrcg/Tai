import CoreData
import SwiftUI
import Swinject

extension Adjustments {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State var isEditing = false
        @State var showOverrideCreationSheet = false
        @State var showTempTargetCreationSheet = false
        @State var showingDetail = false
        @State var showOverrideCheckmark: Bool = false
        @State var showTempTargetCheckmark: Bool = false
        @State var selectedOverridePresetID: String?
        @State var selectedTempTargetPresetID: String?
        @State var selectedOverride: OverrideStored?
        @State var selectedTempTarget: TempTargetStored?
        @State var overrideToDelete: OverrideStored?
        @State var tempTargetToDelete: TempTargetStored?
        @State var isPromptPresented = false
        @State var isRemoveAlertPresented = false
        @State var removeAlert: Alert?
        @State var isEditingTT = false
        @State var showCancelOverrideConfirmDialog = false
        @State var showCancelTempTargetConfirmDialog = false
        @State var pendingPresetActivation: PendingPresetActivation?

        private var shouldDisplayStickyOverrideStopButton: Bool {
            state.isOverrideEnabled && state.activeOverrideName.isNotEmpty
        }

        private var shouldDisplayStickyTempTargetStopButton: Bool {
            state.isTempTargetEnabled && state.activeTempTargetName.isNotEmpty
        }

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        func formattedGlucose(glucose: Decimal) -> String {
            let formattedValue: String
            if state.units == .mgdL {
                formattedValue = Formatter.glucoseFormatter(for: state.units)
                    .string(from: glucose as NSDecimalNumber) ?? "\(glucose)"
            } else {
                formattedValue = glucose.formattedAsMmolL
            }
            return "\(formattedValue) \(state.units.rawValue)"
        }

        var body: some View {
            tempTargetDeleteConfirmation(overrideDeleteConfirmation(mainContent))
        }

        private var mainContent: some View {
            VStack {
                HStack(spacing: 6) {
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.up.circle.badge.clock")
                            .rotationEffect(.degrees(90))
                            .font(.system(size: 20))
                            .foregroundStyle(Color.secondary, Color.loopGreen)
                        Text(Adjustments.Tab.tempTargets.name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .background(state.selectedTab == .tempTargets ? Color.loopGray.opacity(0.4) : Color.clear)
                    .cornerRadius(8)
                    .onTapGesture {
                        withAnimation {
                            state.selectedTab = .tempTargets
                        }
                    }
                    HStack {
                        Spacer()
                        Image(systemName: "clock.arrow.2.circlepath")
                            .font(.system(size: 20))
                            .foregroundStyle(Color.primary, Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569))
                        Text(Adjustments.Tab.overrides.name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .background(state.selectedTab == .overrides ? Color.loopGray.opacity(0.4) : Color.clear)
                    .cornerRadius(8)
                    .onTapGesture {
                        withAnimation {
                            state.selectedTab = .overrides
                        }
                    }
                    HStack {
                        Spacer()
                        Image(systemName: "person.2", variableValue: 0.58)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.blue, Color.white, Color.white)
                            .font(.system(size: 13, weight: .regular))
                            .frame(width: 22, height: 22)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.blue, lineWidth: 1.5)
                            )
                        Text(Adjustments.Tab.profiles.name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .background(state.selectedTab == .profiles ? Color.loopGray.opacity(0.4) : Color.clear)
                    .cornerRadius(8)
                    .onTapGesture {
                        withAnimation {
                            state.selectedTab = .profiles
                        }
                    }
                }
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .padding(.horizontal)

                Group {
                    switch state.selectedTab {
                    case .profiles:
                        // Embed the existing Profiles screen as the third tab. AdaptProfile.RootView
                        // owns its own List, toolbar, and "Profiles" navigation title — those take
                        // over while this tab is active. The Adjustments-side toolbar/title below is
                        // skipped on this tab to avoid stacking.
                        AdaptProfile.RootView(resolver: resolver)
                    case .overrides,
                         .tempTargets:
                        List {
                            switch state.selectedTab {
                            case .overrides: overrides()
                            case .tempTargets: tempTargets()
                            case .profiles: EmptyView()
                            }
                        }
                        .listSectionSpacing(10)
                        .safeAreaInset(
                            edge: .bottom,
                            spacing: shouldDisplayStickyOverrideStopButton || shouldDisplayStickyTempTargetStopButton ? 30 : 0
                        ) {
                            if shouldDisplayStickyOverrideStopButton, state.selectedTab == .overrides {
                                stickyStopOverrideButton
                            } else if shouldDisplayStickyTempTargetStopButton, state.selectedTab == .tempTargets {
                                stickyStopTempTargetButton
                            } else {
                                EmptyView()
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(appState.trioBackgroundColor(for: colorScheme))
                        .navigationBarTitle("Adjustments")
                        .navigationBarTitleDisplayMode(.large)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Group {
                                    switch state.selectedTab {
                                    case .overrides:
                                        Button(action: {
                                            showOverrideCreationSheet = true
                                        }, label: {
                                            HStack {
                                                Text("Add Override")
                                                Image(systemName: "plus")
                                            }
                                        })
                                    case .tempTargets:
                                        Button(action: {
                                            showTempTargetCreationSheet = true
                                        }, label: {
                                            HStack {
                                                Text("Add Temp Target")
                                                Image(systemName: "plus")
                                            }
                                        })
                                    case .profiles:
                                        EmptyView()
                                    }
                                }
                            }
                        }
                    }
                }
                .onAppear {
                    configureView()
                    // Banner-arrival path: let the view first render on the default tab so the
                    // NavigationStack chrome and List layout settle exactly the same way they
                    // would on any normal mount, then animate the swap to the requested tab.
                    // This makes the banner path go through the identical "tab switch" code
                    // path the user would trigger by tapping the pill manually — eliminating
                    // the layout mismatch we got from switching before/during first render.
                    if let raw = UserDefaults.standard.string(forKey: Adjustments.pendingTabKey),
                       let tab = Adjustments.Tab(rawValue: raw)
                    {
                        UserDefaults.standard.removeObject(forKey: Adjustments.pendingTabKey)
                        DispatchQueue.main.async {
                            withAnimation {
                                state.selectedTab = tab
                            }
                        }
                    }
                }
                .sheet(isPresented: $state.showOverrideEditSheet, onDismiss: {
                    Task {
                        await state.resetStateVariables()
                        state.showOverrideEditSheet = false
                    }

                }) {
                    if let override = selectedOverride {
                        EditOverrideForm(overrideToEdit: override, state: state)
                    }
                }
                .sheet(isPresented: $showOverrideCreationSheet, onDismiss: {
                    Task {
                        await state.resetStateVariables()
                        showOverrideCreationSheet = false
                    }
                }) {
                    AddOverrideForm(state: state)
                }
                .sheet(isPresented: $showTempTargetCreationSheet, onDismiss: {
                    Task {
                        await state.resetTempTargetState()
                        showTempTargetCreationSheet = false
                    }
                }) {
                    AddTempTargetForm(state: state)
                }
                .sheet(isPresented: $state.showTempTargetEditSheet, onDismiss: {
                    Task {
                        await state.resetTempTargetState()
                        state.showTempTargetEditSheet = false
                    }

                }) {
                    if let tempTarget = selectedTempTarget {
                        EditTempTargetForm(tempTargetToEdit: tempTarget, state: state)
                    }
                }
                .glassActionSheet(
                    "Override to Stop",
                    message: Text("Stop the Override \"\(state.currentActiveOverride?.name ?? "")\"?"),
                    isPresented: $showCancelOverrideConfirmDialog,
                    actions: [
                        GlassSheetAction("Stop", role: .destructive) {
                            Task {
                                // Save cancelled Override in OverrideRunStored Entity
                                // Cancel ALL active Override
                                info(.treatments, "Override stopped")
                                await state.disableAllActiveOverrides(createOverrideRunEntry: true)
                            }
                        }
                    ]
                )
                .glassActionSheet(
                    "Temp Target to Stop",
                    message: Text("Stop the Temp Target \"\(state.currentActiveTempTarget?.name ?? "")\"?"),
                    isPresented: $showCancelTempTargetConfirmDialog,
                    actions: [
                        GlassSheetAction("Stop", role: .destructive) {
                            Task {
                                // Save cancelled Temp Targets in TempTargetRunStored Entity
                                // Cancel ALL active Temp Targets
                                info(.treatments, "Temp target stopped")
                                await state.disableAllActiveTempTargets(createTempTargetRunEntry: true)
                                // Update View
                                state.updateLatestTempTargetConfiguration()
                            }
                        }
                    ]
                )
                .glassActionSheet(
                    "Activate Preset",
                    message: pendingPresetActivation.map { Text($0.confirmationMessage) },
                    isPresented: presetActivationConfirmationBinding,
                    actions: [
                        GlassSheetAction("Activate") {
                            if let activation = pendingPresetActivation {
                                activatePreset(activation)
                            }
                        }
                    ],
                    onCancel: {
                        state.shouldDisplayPresetStartConfirmDialog = false
                        pendingPresetActivation = nil
                    }
                )
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
        }

        var defaultText: some View {
            Group {
                switch state.selectedTab {
                case .overrides:
                    Section {} header: {
                        Text(
                            "Add Preset or Override by tapping 'Add Override +' in the top right-hand corner of the screen."
                        )
                        .textCase(nil)
                        .foregroundStyle(.secondary)
                    }
                case .tempTargets:
                    Section {} header: {
                        Text(
                            "Add Preset or Temp Target by tapping 'Add Temp Target +' in the top right-hand corner of the screen."
                        )
                        .textCase(nil)
                        .foregroundStyle(.secondary)
                    }
                case .profiles:
                    EmptyView()
                }
            }
        }

        @ViewBuilder var currentActiveAdjustment: some View {
            switch state.selectedTab {
            case .overrides:
                Section {
                    HStack {
                        Text("\(state.activeOverrideName) is running")

                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Color.primary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editActiveOverride()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(Text(String(localized: "Double tap to edit", comment: "Accessibility hint")))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { editActiveOverride() }
                }
                .listRowBackground(Color.purple.opacity(0.8))
            case .tempTargets:
                Section {
                    HStack {
                        Text("\(state.activeTempTargetName) is running")

                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Color.primary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editActiveTempTarget()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(Text(String(localized: "Double tap to edit", comment: "Accessibility hint")))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { editActiveTempTarget() }
                }
                .listRowBackground(Color.loopGreen.opacity(0.8))
            case .profiles:
                EmptyView()
            }
        }

        private func editActiveOverride() {
            Task {
                /// To avoid editing the Preset when a Preset-Override is running we first duplicate the Preset-Override as a non-Preset Override
                /// The currentActiveOverride variable in the State will update automatically via MOC notification
                await state.duplicateOverridePresetAndCancelPreviousOverride()

                /// selectedOverride is used for passing the chosen Override to the EditSheet so we have to set the updated currentActiveOverride to be the selectedOverride
                selectedOverride = state.currentActiveOverride

                /// Now we can show the Edit sheet
                state.showOverrideEditSheet = true
            }
        }

        private func editActiveTempTarget() {
            Task {
                /// To avoid editing the Preset when a Preset-TempTarget is running we first duplicate it as a non-Preset TempTarget
                await state.duplicateTempTargetPresetAndCancelPreviousTempTarget()

                selectedTempTarget = state.currentActiveTempTarget

                /// Now we can show the Edit sheet
                state.showTempTargetEditSheet = true
            }
        }

        @ViewBuilder var cancelAdjustmentButton: some View {
            switch state.selectedTab {
            case .overrides:
                Button(action: {
                    showCancelOverrideConfirmDialog = true
                }, label: {
                    Text("Stop Override")

                })
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!state.isOverrideEnabled)
                    .listRowBackground(!state.isOverrideEnabled ? Color(.systemGray4) : Color(.systemRed))
                    .tint(.white)
            case .tempTargets:
                Button(action: {
                    showCancelTempTargetConfirmDialog = true
                }, label: {
                    Text("Stop Temp Target")

                })
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!state.isTempTargetEnabled)
                    .listRowBackground(!state.isTempTargetEnabled ? Color(.systemGray4) : Color(.systemRed))
                    .tint(.white)
            case .profiles:
                EmptyView()
            }
        }

        func formattedTimeRemaining(_ timeInterval: TimeInterval) -> String {
            let totalSeconds = Int(timeInterval)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60

            if hours > 0 {
                return "\(hours)h \(minutes)m \(seconds)s"
            } else if minutes > 0 {
                return "\(minutes)m \(seconds)s"
            } else {
                return "<1m"
            }
        }
    }
}

// MARK: Preset Activation Handling

extension Adjustments.RootView: View {
    enum PendingPresetActivation {
        case override(objectID: NSManagedObjectID, presetID: String?, name: String)
        case tempTarget(objectID: NSManagedObjectID, presetID: String?, name: String)

        var name: String {
            switch self {
            case let .override(_, _, name),
                 let .tempTarget(_, _, name):
                return name
            }
        }

        var adjustmentType: String {
            switch self {
            case .override:
                return String(localized: "Override")
            case .tempTarget:
                return String(localized: "Temp Target")
            }
        }

        var confirmationMessage: String {
            String(localized: "Start the \(adjustmentType) \"\(name)\"?", comment: "Confirmation message for starting a preset")
        }
    }

    private var presetActivationConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                state.requireAdjustmentsConfirmation &&
                    state.shouldDisplayPresetStartConfirmDialog &&
                    pendingPresetActivation != nil
            },
            set: { isPresented in
                if !isPresented {
                    state.shouldDisplayPresetStartConfirmDialog = false
                    pendingPresetActivation = nil
                }
            }
        )
    }

    func requestPresetActivation(_ activation: PendingPresetActivation) {
        if state.requireAdjustmentsConfirmation {
            pendingPresetActivation = activation
            state.shouldDisplayPresetStartConfirmDialog = true
        } else {
            activatePreset(activation)
        }
    }

    func activatePreset(_ activation: PendingPresetActivation) {
        Task {
            switch activation {
            case let .override(objectID, presetID, _):
                await state.enactOverridePreset(withID: objectID)

                await MainActor.run {
                    state.hideModal()
                    selectedOverridePresetID = presetID
                    showOverrideCheckmark = true
                    state.shouldDisplayPresetStartConfirmDialog = false
                    pendingPresetActivation = nil
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showOverrideCheckmark = false
                }

            case let .tempTarget(objectID, presetID, _):
                await state.enactTempTargetPreset(withID: objectID)

                await MainActor.run {
                    selectedTempTargetPresetID = presetID
                    showTempTargetCheckmark = true
                    state.shouldDisplayPresetStartConfirmDialog = false
                    pendingPresetActivation = nil
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showTempTargetCheckmark = false
                }
            }
        }
    }
}
