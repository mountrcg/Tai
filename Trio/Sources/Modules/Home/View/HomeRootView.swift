import CoreData
import LoopKitUI
import SpriteKit
import SwiftDate
import SwiftUI
import Swinject

extension Home {
    struct RootView: BaseView {
        let resolver: Resolver

        @Environment(\.managedObjectContext) var moc
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        @State var state = StateModel()

        @State var settingsPath = NavigationPath()
        @State var settingsSearchHighlight = SettingsSearchHighlight()
        @State var isStatusPopupPresented = false
        @State private var statusTitlePopup: String = ""
        @State var showCancelAlert = false
        @State var showCancelConfirmDialog = false
        @State var isConfirmStopOverrideShown = false
        @State var isConfirmStopOverridePresented = false
        @State var isConfirmStopTempTargetShown = false
        @State var isConfirmRevertProfilePresented = false
        @State var isMenuPresented = false
        @State var showTreatments = false
        @State var selectedTab: Int = 0
        @State var lastRealTab: Int = 0
        // measured x-distance of the dead slot's center from screen center
        @State var treatmentSlotOffsetX: CGFloat = 0
        @State var showQuickPickTreatmentsPicker = false
        @State var showQuickPickTreatmentsNoHistory = false
        @State var showPumpSelection: Bool = false
        @State var showCGMSelection: Bool = false
        @State var pendingPump: PumpCatalogEntry?
        @State var pendingCGM: CGMCatalogEntry?
        @State var showSnoozeSheet: Bool = false
        @State var alarmsSnoozeUntil: Date = .distantPast
        @State var showManualGlucose: Bool = false
        @State var showReleaseNotes: Bool = false
        @State var notificationsDisabled = false
        @ObservedObject var releaseNotesService = ReleaseNotesService.shared

        // Pull-down-to-force-loop (see HomeRootView+Refresh.swift)
        @State var pullOffset: CGFloat = 0
        @State var isRefreshArmed = false
        @State var isForcingLoop = false

        @FetchRequest(fetchRequest: OverrideStored.fetch(
            NSPredicate.lastActiveOverride,
            ascending: false,
            fetchLimit: 1
        )) var latestOverride: FetchedResults<OverrideStored>

        @FetchRequest(fetchRequest: TempTargetStored.fetch(
            NSPredicate.lastActiveTempTarget,
            ascending: false,
            fetchLimit: 1
        )) var latestTempTarget: FetchedResults<TempTargetStored>

        @FetchRequest(fetchRequest: ProfileStored.fetch(
            NSPredicate.activeProfile,
            ascending: false,
            fetchLimit: 1
        )) var activeProfile: FetchedResults<ProfileStored>

        @ViewBuilder func mainChart(geo: GeometryProxy) -> some View {
            let chartHeight = max(
                geo.size.height - HomeLayout.headerTopPadding - HomeLayout.headerHeight - HomeLayout.mealSlotHeight
                    - HomeLayout.bottomZoneHeight - 2 * HomeLayout.chartVerticalPadding,
                HomeLayout.chartMinHeight
            )
            ZStack {
                MainChartView(
                    geo: geo,
                    chartHeight: chartHeight,
                    units: state.units,
                    highGlucose: state.highGlucose,
                    lowGlucose: state.lowGlucose,
                    currentGlucoseTarget: state.currentGlucoseTarget,
                    glucoseColorScheme: state.glucoseColorScheme,
                    displayXgridLines: state.displayXgridLines,
                    displayYgridLines: state.displayYgridLines,
                    thresholdLines: state.thresholdLines,
                    state: state,
                    showCobIobChart: state.showCobIobChart
                )
            }
            .overlay(alignment: .bottomTrailing) {
                chartInfoButton
                    // lifted above the hour labels on the x-axis
                    .offset(x: 0, y: -28)
            }
            .padding(.vertical, HomeLayout.chartVerticalPadding)
        }

        /// Chart-legend button pinned to the chart's lower-right; the chart
        /// frame is fixed, so it stays put with the COB/IOB pane on or off.
        @ViewBuilder private var chartInfoButton: some View {
            Button {
                state.isLegendPresented.toggle()
            } label: {
                // styled to match the alarm bell pill in the meal row
                Image(systemName: "info")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.4), lineWidth: 2)
                    )
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .padding(.bottom, 6)
            .padding(.trailing, 8)
        }

        @ViewBuilder func mainViewElements(_ geo: GeometryProxy) -> some View {
            // Viewport-sized content: rubber-bands for the pull-down, never scrolls.
            ScrollView(.vertical, showsIndicators: false) {
                dashboardContent(geo)
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(
                                key: HomePullOffsetKey.self,
                                value: g.frame(in: .named("homeScroll")).minY
                            )
                        }
                    )
            }
            .coordinateSpace(name: "homeScroll")
            .scrollBounceBehavior(.always, axes: [.vertical])
            .modifier(HomePullOffsetReader(onChange: handlePullChange))
            .onPreferenceChange(HomePullOffsetKey.self) { handlePullChange($0) }
            .overlay(alignment: .top) { pullToRefreshIndicator }
            // Safe-area inset: the tab bar can never cover the controls.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomControls()
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onReceive(
                resolver.resolve(AlertPermissionsChecker.self)!.$notificationsDisabled,
                perform: {
                    if notificationsDisabled != $0 {
                        notificationsDisabled = $0
                        if notificationsDisabled {
                            debug(.default, "notificationsDisabled")
                        }
                    }
                }
            )
        }

        @ViewBuilder private func dashboardContent(_ geo: GeometryProxy) -> some View {
            VStack(spacing: 0) {
                ZStack {
                    if let apsManager = state.apsManager, let bluetoothManager = apsManager.bluetoothManager,
                       bluetoothManager.bluetoothAuthorization != .authorized
                    {
                        BluetoothRequiredView()
                    } else {
                        /// right panel with loop status and evBG
                        HStack {
                            Spacer()
                            rightHeaderPanel()
                        }.padding(.trailing, 20)

                        /// glucose bobble
                        glucoseView

                        /// left panel with meal related info
                        HStack {
                            leftHeaderPanel()
                            Spacer()
                        }.padding(.leading, 20)
                    }
                }
                // Fixed slot: every header state renders centered, no reflow below.
                .frame(height: HomeLayout.headerHeight)
                .padding(.top, HomeLayout.headerTopPadding)

                horizontalPumpView
                    .frame(height: HomeLayout.mealSlotHeight)

                mainChart(geo: geo)
            }
            .frame(maxWidth: .infinity)
        }

        @ViewBuilder func mainView() -> some View {
            GeometryReader { geo in
                mainViewElements(geo)
            }
            // no inline text input here; a stale keyboard inset must never shrink the zone budget
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onAppear {
                configureView()
                refreshAlarmsSnooze()
            }
            .task {
                await releaseNotesService.load()
            }
            .navigationTitle("Home")
            .navigationBarHidden(true)
            .blur(radius: state.isLoopStatusPresented ? 3 : 0)
//            .sheet(isPresented: $state.isLoopStatusPresented) {
//                LoopStatusView(state: state)
//            }
            .popup(isPresented: state.isStatusPopupPresented, alignment: .top, direction: .top) {
                VStack {
                    Rectangle().opacity(0).frame(height: 200)
                    popup
                        .padding(8)
                        .glassPanel()
                        .gesture(
                            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                                .onEnded { value in
                                    if value.translation.height < 0 {
                                        state.isStatusPopupPresented = false
                                    }
                                }
                        )
                }
            }
            .sheet(isPresented: $state.isLegendPresented) {
                ChartLegendView(state: state)
            }
            .sheet(isPresented: $showSnoozeSheet) {
                SnoozeAlertsSheetView(resolver: resolver, isPresented: $showSnoozeSheet)
            }
            // UserDefaults changes don't invalidate views; refresh on sheet dismissal
            .onChange(of: showSnoozeSheet) {
                if !showSnoozeSheet { refreshAlarmsSnooze() }
            }
            .sheet(isPresented: $showReleaseNotes) {
                if let notes = releaseNotesService.notes {
                    ReleaseNotesSheetView(notes: notes) {
                        releaseNotesService.acknowledge()
                    }
                }
            }
            .sheet(isPresented: $showManualGlucose) {
                ManualGlucoseEntryView(units: state.units, isPresented: $showManualGlucose) { amount in
                    state.addManualGlucose(amount)
                }
            }
            // DEVICE SELECTION (pump + CGM)
            .devicePickers(
                showPumpSelection: $showPumpSelection,
                showCGMSelection: $showCGMSelection,
                pendingPump: $pendingPump,
                pendingCGM: $pendingCGM,
                state: state
            )
            .sheet(isPresented: $state.shouldDisplayPumpSetupSheet) {
                if let pumpManager = state.provider.apsManager.pumpManager
                {
                    PumpConfig.PumpSettingsView(
                        pumpManager: pumpManager,
                        bluetoothManager: state.provider.apsManager.bluetoothManager!,
                        completionDelegate: state,
                        setupDelegate: state
                    )
                } else if let pumpEntry = state.setupPumpEntry {
                    PumpConfig.PumpSetupView(
                        pumpEntry: pumpEntry,
                        pumpInitialSettings: state.pumpInitialSettings,
                        bluetoothManager: state.provider.apsManager.bluetoothManager!,
                        completionDelegate: state,
                        setupDelegate: state
                    )
                }
            }
            // CGM RELATED
            .sheet(isPresented: $state.shouldDisplayCGMSetupSheet) {
                switch state.cgmCurrent.type {
                case .nightscout,
                     .none,
                     .simulator,
                     .xdrip:
                    CGMSettings.CustomCGMOptionsView(
                        resolver: self.resolver,
                        state: state.cgmStateModel,
                        cgmCurrent: state.cgmCurrent,
                        deleteCGM: state.deleteCGM
                    )
                case .plugin:
                    if let fetchGlucoseManager = state.fetchGlucoseManager,
                       let cgmManager = fetchGlucoseManager.cgmManager,
                       state.cgmCurrent.type == fetchGlucoseManager.cgmGlucoseSourceType,
                       state.cgmCurrent.id == fetchGlucoseManager.cgmGlucosePluginId
                    {
                        CGMSettings.CGMSettingsView(
                            cgmManager: cgmManager,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            unit: state.settingsManager.settings.units,
                            completionDelegate: state
                        )
                    } else {
                        CGMSettings.CGMSetupView(
                            CGMType: state.cgmCurrent,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            unit: state.settingsManager.settings.units,
                            completionDelegate: state,
                            setupDelegate: state,
                            pluginCGMManager: self.state.pluginCGMManager
                        )
                    }
                }
            }
        }

        @ViewBuilder func tabBar() -> some View {
            if #available(iOS 26.0, *) {
                modernTabBar()
            } else {
                legacyTabBar()
            }
        }

        /// Tai layout on the iOS 26 glass bar: five slots like the legacy bar,
        /// the middle one disabled so the system cannot select it — the Tai
        /// treatment button overlays that gap. Belt and braces: if a selection
        /// of the dead slot ever sneaks through, it bounces to the last real
        /// tab and counts as a treatment-button press.
        @available(iOS 26.0, *)
        @ViewBuilder private func modernTabBar() -> some View {
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                    let carbsRequiredBadge: String? = carbsRequiredBadgeValue

                    NavigationStack { mainView() }
                        .tabItem { Label("", systemImage: "chart.xyaxis.line") }
                        .badge(carbsRequiredBadge).tag(0)
                        .accessibilityLabel(Text("Main"))

                    NavigationStack { History.RootView(resolver: resolver) }
                        .tabItem { Label("", systemImage: "list.bullet") }.tag(1)
                        .accessibilityLabel(Text("History"))

                    Color.clear
                        // nbsp title + empty image: invisible item that still
                        // holds a full-width slot under the overlaid button
                        .tabItem { Label {
                            Text(String(repeating: "\u{00A0}", count: 12))
                        } icon: {
                            Image(uiImage: UIImage())
                        } }
                        .tag(2)
                        .disabled(true)

                    NavigationStack { Adjustments.RootView(resolver: resolver) }
                        .tabItem {
                            Label(
                                "",
                                systemImage: "slider.horizontal.2.gobackward"
                            ) }.tag(3)
                        .accessibilityLabel(Text("Adjustments"))

                    NavigationStack(path: self.$settingsPath) {
                        Settings.RootView(resolver: resolver) }
                        .environment(settingsSearchHighlight)
                        .tabItem { Label(
                            "",
                            systemImage: "gear"
                        ) }.tag(4)
                        .accessibilityLabel(Text("Settings"))
                }
                .tint(Color.tabBar)

                treatmentButton
                    // measured slot center; stays at screen center if the probe finds nothing.
                    // The glass bar dips into the home-indicator inset, so the
                    // vertical center lies slightly BELOW the safe-area edge.
                    .offset(x: treatmentSlotOffsetX, y: 6)
            }
            .background(TabBarSlotProbe { treatmentSlotOffsetX = $0 })
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .blur(radius: state.waitForSuggestion ? 8 : 0)
            .onChange(of: selectedTab) { _, newValue in
                if newValue == 2 {
                    // dead-slot selection slipped past .disabled: treat as a
                    // treatment press and bounce to the last real tab
                    state.showModal(for: .treatmentView)
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        selectedTab = lastRealTab
                    }
                    return
                }
                lastRealTab = newValue
                if newValue != 4, !settingsPath.isEmpty {
                    settingsPath = NavigationPath()
                }
            }
        }

        private var treatmentButton: some View {
            Image(.taiCircledNoBackground)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
                .padding(.vertical, 2)
                .shadow(color: Color.white.opacity(0.1), radius: 5, x: 0, y: 0)
                .contentShape(Rectangle())
                .onTapGesture {
                    state.showModal(for: .treatmentView)
                }
                .onLongPressGesture(minimumDuration: 0.5) {
                    guard state.enableQuickPickTreatments else { return }
                    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                    impactHeavy.impactOccurred()
                    Task {
                        await state.loadQuickPickTreatmentSuggestions()
                        if state.quickPickBolusSuggestions.isEmpty, state.quickPickCarbSuggestions.isEmpty {
                            showQuickPickTreatmentsNoHistory = true
                        } else {
                            showQuickPickTreatmentsPicker = true
                        }
                    }
                }
                .accessibilityLabel(Text("Add Treatment"))
        }

        private var carbsRequiredBadgeValue: String? {
            guard let carbsRequired = state.enactedAndNonEnactedDeterminations.first?.carbsRequired,
                  state.showCarbsRequiredBadge
            else {
                return nil
            }
            let carbsRequiredDecimal = Decimal(carbsRequired)
            if carbsRequiredDecimal > state.settingsManager.settings.carbsRequiredThreshold {
                let numberAsNSNumber = NSDecimalNumber(decimal: carbsRequiredDecimal)
                return (Formatter.decimalFormatterWithTwoFractionDigits.string(from: numberAsNSNumber) ?? "") + " g"
            }
            return nil
        }

        @ViewBuilder private func legacyTabBar() -> some View {
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                    let carbsRequiredBadge: String? = {
                        guard let carbsRequired = state.enactedAndNonEnactedDeterminations.first?.carbsRequired,
                              state.showCarbsRequiredBadge
                        else {
                            return nil
                        }
                        let carbsRequiredDecimal = Decimal(carbsRequired)
                        if carbsRequiredDecimal > state.settingsManager.settings.carbsRequiredThreshold {
                            let numberAsNSNumber = NSDecimalNumber(decimal: carbsRequiredDecimal)
                            return (Formatter.decimalFormatterWithTwoFractionDigits.string(from: numberAsNSNumber) ?? "") + " g"
                        }
                        return nil
                    }()

                    NavigationStack { mainView() }
                        .tabItem { Label("Main", systemImage: "chart.xyaxis.line") }
                        .badge(carbsRequiredBadge).tag(0)

                    NavigationStack { History.RootView(resolver: resolver) }
                        .tabItem { Label("History", systemImage: "list.bullet") }.tag(1)

                    // Tag-2 placeholder for the central "+" button slot. iOS divides the
                    // bar into 5 equal slots; without an explicit tag here, the strips of
                    // this slot to the left/right of the 42pt "+" icon route taps to an
                    // untagged Spacer and surface an empty view (black screen). Tagging
                    // lets `onChange(of: selectedTab)` intercept the tap and treat it as
                    // a "+" press. Mirrors nightscout/Trio PR #764.
                    Color.clear
                        .tabItem {}
                        .tag(2)

                    NavigationStack { Adjustments.RootView(resolver: resolver) }
                        .tabItem {
                            Label(
                                "Adjustments",
                                systemImage: "slider.horizontal.2.gobackward"
                            ) }.tag(3)

                    NavigationStack(path: self.$settingsPath) {
                        Settings.RootView(resolver: resolver) }
                        .environment(settingsSearchHighlight)
                        .tabItem { Label(
                            "Settings",
                            systemImage: "gear"
                        ) }.tag(4)
                }
                .tint(Color.tabBar)

                Image(.taiCircledNoBackground)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 42, height: 42)
                    .padding(.vertical, 2)
                    .shadow(color: Color.white.opacity(0.1), radius: 5, x: 0, y: 0)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        state.showModal(for: .treatmentView)
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        guard state.enableQuickPickTreatments else { return }
                        let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                        impactHeavy.impactOccurred()
                        Task {
                            await state.loadQuickPickTreatmentSuggestions()
                            if state.quickPickBolusSuggestions.isEmpty, state.quickPickCarbSuggestions.isEmpty {
                                showQuickPickTreatmentsNoHistory = true
                            } else {
                                showQuickPickTreatmentsPicker = true
                            }
                        }
                    }
            }.ignoresSafeArea(.keyboard, edges: .bottom).blur(radius: state.waitForSuggestion ? 8 : 0)
                .onChange(of: selectedTab) { oldValue, newValue in
                    // Tag-2 is the placeholder slot under the central "+". If a tap lands
                    // on the strips around the 42pt "+" icon, treat it as a "+" press:
                    // open the Treatment sheet, then bounce selection back. The 1s delay
                    // lets the modal animation start before SwiftUI flips the tab —
                    // immediate revert can race the sheet presentation. Same pattern as
                    // nightscout/Trio PR #764.
                    if newValue == 2 {
                        state.showModal(for: .treatmentView)
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            selectedTab = oldValue
                        }
                        return
                    }
                    // Don't clear settingsPath when bouncing back from the placeholder.
                    if oldValue != 2, !settingsPath.isEmpty {
                        settingsPath = NavigationPath()
                    }
                }
        }

        var body: some View {
            ZStack(alignment: .center) {
                tabBar()

                if state.waitForSuggestion {
                    CustomProgressView(text: String(localized: "Updating IOB...", comment: "Progress text when updating IOB"))
                }
            }
            .sheet(isPresented: $showQuickPickTreatmentsPicker) {
                QuickPickTreatmentsView(
                    bolusSuggestions: state.quickPickBolusSuggestions,
                    carbSuggestions: state.quickPickCarbSuggestions,
                    onEnact: { bolusAmount, carbAmount in
                        await state.enactQuickPickTreatment(bolusAmount: bolusAmount, carbAmount: carbAmount)
                    },
                    isPresented: $showQuickPickTreatmentsPicker
                )
            }
            .alert(
                String(
                    localized: "No treatment history yet",
                    comment: "Alert title when no quick-pick treatments history exists"
                ),
                isPresented: $showQuickPickTreatmentsNoHistory
            ) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(String(
                    localized: "Quick-Pick Treatments learns from your manual boluses and carb entries over time. Once you've logged a few, it will suggest amounts based on what you typically enter at this time of day.",
                    comment: "Alert body explaining that quick-pick treatments history is empty"
                ))
            }
        }

        private var popup: some View {
            // Directly calculate the status title in the view
            let popupTitle: String = {
                let determination = getMostRecentDetermination()

                if determination == nil {
                    return String(
                        localized: "No Algorithm result",
                        comment: "Home status popup title when no determination is available"
                    )
                }

                let dateFormatter = DateFormatter()
                dateFormatter.timeStyle = .short

                // Check if the determination is from suggested or enacted source
                if state.determinationsFromSuggestion.first?.objectID == determination?.objectID {
                    var title = String(localized: "Algorithm suggested at", comment: "Headline in suggested popup") +
                        " " + dateFormatter.string(from: determination?.deliverAt ?? Date())

                    // Add warning if the loop is not closed or if it's a manual temp basal
                    if state.manualTempBasal || !state.closedLoop {
                        title += String(
                            localized: " - not enacted!",
                            comment: "Suffix appended to Home status popup title when the suggestion was not enacted"
                        )
                    }
                    return title
                } else {
                    return String(localized: "Algorithm enacted at", comment: "Headline in enacted popup") +
                        " " + dateFormatter.string(from: determination?.deliverAt ?? Date())
                }
            }()

            return VStack(alignment: .leading, spacing: 4) {
                Text(popupTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.bottom, 4)

                if let errorMessage = state.errorMessage, let date = state.errorDate {
                    Group {
                        Text("Error During Algorithm Run at \(Formatter.dateFormatter.string(from: date))").font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(errorMessage).font(.caption).fixedSize(horizontal: false, vertical: true)
                    }.foregroundColor(.loopRed)
                }

                // Determine which data to show based on most recent date
                let determinationToShow = getMostRecentDetermination()

                if let determination = determinationToShow {
                    if determination.glucose == 400 {
                        Text("Invalid CGM reading (HIGH).")
                            .bold()
                            .padding(.top)
                            .foregroundStyle(Color.loopRed)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("SMBs and Non-Zero Temp. Basal Rates are disabled.")
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        let tags = !state.isSmoothingEnabled ? determination.reasonParts : determination
                            .reasonParts +
                            [String(
                                localized: "Smoothing: On",
                                comment: "Tag chip in Home status popup — glucose smoothing is enabled"
                            )]
                        TagCloudView(
                            tags: tags,
                            shouldParseToMmolL: state.units == .mmolL
                        )
                        .animation(.none, value: false)
                        Text("Algorithm reasoning").font(.headline).foregroundColor(.primary)
                            .padding(.vertical, 4)
                        Text(parseReasonConclusion(determination.reasonConclusion, isMmolL: state.units == .mmolL))
                            .font(.subheadline).foregroundColor(.primary)
                    }
                } else {
                    Text("No Algorithm result").font(.body).foregroundColor(.primary)
                }

                Button {
                    state.isStatusPopupPresented = false
                } label: {
                    Text("Got it!")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .buttonStyle(.bordered)
                .padding(.top)
            }
        }

        // Modified setStatusTitlePopup method that now returns the current title string
        private func setStatusTitlePopup() -> String {
            let determination = getMostRecentDetermination()

            if determination == nil {
                statusTitlePopup = String(
                    localized: "No Algorithm result",
                    comment: "Home status popup title fallback when no determination exists"
                )
                return statusTitlePopup
            }

            let dateFormatter = DateFormatter()
            dateFormatter.timeStyle = .short

            // Check if the determination is from suggested or enacted source
            if state.determinationsFromSuggestion.first?.objectID == determination?.objectID {
                statusTitlePopup =
                    String(localized: "Algorithm suggested at", comment: "Headline in suggested popup") +
                    " " + dateFormatter.string(from: determination?.deliverAt ?? Date())

                // Add warning if the loop is not closed or if it's a manual temp basal
                if state.manualTempBasal || !state.closedLoop {
                    statusTitlePopup += String(
                        localized: " - not enacted!",
                        comment: "Suffix appended to Home status popup title when the suggestion was not enacted"
                    )
                }
            } else {
                statusTitlePopup = String(localized: "Algorithm enacted at", comment: "Headline in enacted popup") +
                    " " + dateFormatter.string(from: determination?.deliverAt ?? Date())
            }

            return statusTitlePopup
        }

        // Helper function to determine the most recent determination
        // TODO: Consolidate all mmol parsing methods (in TagCloudView, NightscoutManager and HomeRootView) to one central func
        private func parseReasonConclusion(_ reasonConclusion: String, isMmolL: Bool) -> String {
            let patterns = [
                "minGuardBG\\s*-?\\d+\\.?\\d*<-?\\d+\\.?\\d*", // minGuardBG x<y
                "Eventual BG\\s*-?\\d+\\.?\\d*\\s*>=\\s*-?\\d+\\.?\\d*", // Eventual BG x >= target
                "Eventual BG\\s*-?\\d+\\.?\\d*\\s*<\\s*-?\\d+\\.?\\d*", // Eventual BG x < target
                "(\\S+)\\s+(-?\\d+\\.?\\d*)\\s*>\\s*(\\d+)%\\s+of\\s+BG\\s+(-?\\d+\\.?\\d*)" // maxDelta x > y% of BG z
            ]
            let pattern = patterns.joined(separator: "|")
            let regex = try! NSRegularExpression(pattern: pattern)

            func convertToMmolL(_ value: String) -> String {
                if let glucoseValue = Double(value.replacingOccurrences(of: "[^\\d.-]", with: "", options: .regularExpression)) {
                    let mmolValue = Decimal(glucoseValue).asMmolL
                    return mmolValue.description
                }
                return value
            }

            let matches = regex.matches(
                in: reasonConclusion,
                range: NSRange(reasonConclusion.startIndex..., in: reasonConclusion)
            )
            var updatedConclusion = reasonConclusion

            for match in matches.reversed() {
                guard let range = Range(match.range, in: reasonConclusion) else { continue }
                let matchedString = String(reasonConclusion[range])

                if isMmolL {
                    if matchedString.contains("<"), matchedString.contains("Eventual BG"), !matchedString.contains("=") {
                        // Handle "Eventual BG x < target" pattern
                        let parts = matchedString.components(separatedBy: "<")
                        if parts.count == 2 {
                            let bgPart = parts[0].replacingOccurrences(of: "Eventual BG", with: "")
                                .trimmingCharacters(in: .whitespaces)
                            let targetValue = parts[1].trimmingCharacters(in: .whitespaces)
                            let formattedBGPart = convertToMmolL(bgPart)
                            let formattedTargetValue = convertToMmolL(targetValue)
                            let formattedString = "Eventual BG \(formattedBGPart)<\(formattedTargetValue)"
                            updatedConclusion.replaceSubrange(range, with: formattedString)
                        }
                    } else if matchedString.contains("<"), matchedString.contains("minGuardBG") {
                        // Handle "minGuardBG x<y" pattern
                        let parts = matchedString.components(separatedBy: "<")
                        if parts.count == 2 {
                            let firstValue = parts[0].trimmingCharacters(in: .whitespaces)
                            let secondValue = parts[1].trimmingCharacters(in: .whitespaces)
                            let formattedFirstValue = convertToMmolL(firstValue)
                            let formattedSecondValue = convertToMmolL(secondValue)
                            let formattedString = "minGuardBG \(formattedFirstValue)<\(formattedSecondValue)"
                            updatedConclusion.replaceSubrange(range, with: formattedString)
                        }
                    } else if matchedString.contains(">=") {
                        // Handle "Eventual BG x >= target" pattern
                        let parts = matchedString.components(separatedBy: " >= ")
                        if parts.count == 2 {
                            let firstValue = parts[0].replacingOccurrences(of: "Eventual BG", with: "")
                                .trimmingCharacters(in: .whitespaces)
                            let secondValue = parts[1].trimmingCharacters(in: .whitespaces)
                            let formattedFirstValue = convertToMmolL(firstValue)
                            let formattedSecondValue = convertToMmolL(secondValue)
                            let formattedString = "Eventual BG \(formattedFirstValue) >= \(formattedSecondValue)"
                            updatedConclusion.replaceSubrange(range, with: formattedString)
                        }
                    } else if let localMatch = regex.firstMatch(
                        in: matchedString,
                        range: NSRange(matchedString.startIndex..., in: matchedString)
                    ) {
                        // Handle "maxDelta 37 > 20% of BG 95" style
                        if match.numberOfRanges == 5 {
                            let metric = String(matchedString[Range(localMatch.range(at: 1), in: matchedString)!])
                            let firstValue = String(matchedString[Range(localMatch.range(at: 2), in: matchedString)!])
                            let percentage = String(matchedString[Range(localMatch.range(at: 3), in: matchedString)!])
                            let bgValue = String(matchedString[Range(localMatch.range(at: 4), in: matchedString)!])

                            let formattedFirstValue = convertToMmolL(firstValue)
                            let formattedBGValue = convertToMmolL(bgValue)

                            let formattedString = "\(metric) \(formattedFirstValue) > \(percentage)% of BG \(formattedBGValue)"
                            updatedConclusion.replaceSubrange(range, with: formattedString)
                        }
                    }
                } else {
                    // When isMmolL is false, ensure the original value is retained without duplication
                    updatedConclusion.replaceSubrange(range, with: matchedString)
                }
            }

            return updatedConclusion.capitalizingFirstLetter()
        }

        private func getMostRecentDetermination() -> OrefDetermination? {
            let enacted = state.determinationsFromPersistence.first
            let suggested = state.determinationsFromSuggestion.first

            // If only one is available, return it
            if enacted == nil { return suggested }
            if suggested == nil { return enacted }

            // Both are available - compare dates
            let enactedDate = enacted?.deliverAt ?? Date.distantPast
            let suggestedDate = suggested?.deliverAt ?? Date.distantPast

            // Return the most recent one
            return suggestedDate > enactedDate ? suggested : enacted
        }
    }
}

extension UIDevice {
    public enum DeviceSize: CGFloat {
        case smallDevice = 667 // Height for 4" iPhone SE
        case largeDevice = 852 // Height for 6.1" iPhone 15 Pro
    }

    @usableFromInline static func adjustPadding(
        min: CGFloat? = nil,
        max: CGFloat? = nil
    ) -> CGFloat? {
        if UIScreen.screenHeight > UIDevice.DeviceSize.smallDevice.rawValue {
            if UIScreen.screenHeight >= UIDevice.DeviceSize.largeDevice.rawValue {
                return max
            } else {
                return min != nil ?
                    (max != nil ? max! * (UIScreen.screenHeight / UIDevice.DeviceSize.largeDevice.rawValue) : nil) : nil
            }
        } else {
            return min
        }
    }
}

extension UIScreen {
    static var screenHeight: CGFloat {
        UIScreen.main.bounds.height
    }

    static var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }
}

/// Checks if the device is using a 24-hour time format.
func is24HourFormat() -> Bool {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    let dateString = formatter.string(from: Date())

    return !dateString.contains("AM") && !dateString.contains("PM")
}

/// Converts a duration in minutes to a formatted string (e.g., "1 h 30 m").
func formatHrMin(_ durationInMinutes: Int) -> String {
    let hours = durationInMinutes / 60
    let minutes = durationInMinutes % 60

    switch (hours, minutes) {
    case let (0, m):
        return "\(m)\u{00A0}" + String(localized: "m", comment: "Abbreviation for Minutes")
    case let (h, 0):
        return "\(h)\u{00A0}" + String(localized: "h", comment: "h")
    default:
        return hours.description + "\u{00A0}" + String(localized: "h", comment: "h") + "\u{00A0}" + minutes
            .description + "\u{00A0}" + String(localized: "m", comment: "Abbreviation for Minutes")
    }
}

// Helper function to convert a start and end hour to either 24-hour or AM/PM format
func formatTimeRange(start: String?, end: String?) -> String {
    guard let start = start, let end = end else {
        return ""
    }

    // Check if the format is 24-hour or AM/PM
    if is24HourFormat() {
        // Return the original 24-hour format
        return "\(start)-\(end)"
    } else {
        // Convert to AM/PM format using DateFormatter
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"

        if let startHour = Int(start), let endHour = Int(end) {
            let startDate = Calendar.current.date(bySettingHour: startHour, minute: 0, second: 0, of: Date()) ?? Date()
            let endDate = Calendar.current.date(bySettingHour: endHour, minute: 0, second: 0, of: Date()) ?? Date()

            // Customize the format to "2p" or "2a"
            formatter.dateFormat = "ha"
            let startFormatted = formatter.string(from: startDate).lowercased().replacingOccurrences(of: "m", with: "")
            let endFormatted = formatter.string(from: endDate).lowercased().replacingOccurrences(of: "m", with: "")

            return "\(startFormatted)-\(endFormatted)"
        } else {
            return ""
        }
    }
}

/// Locates the tab bar's middle button and reports how far its center sits
/// from screen center, so an overlay can be aligned to the real slot.
private struct TabBarSlotProbe: UIViewRepresentable {
    var onResolve: (CGFloat) -> Void

    func makeUIView(context _: Context) -> ProbeView {
        let view = ProbeView()
        view.onResolve = onResolve
        return view
    }

    func updateUIView(_ uiView: ProbeView, context _: Context) {
        uiView.scheduleResolve()
    }

    final class ProbeView: UIView {
        var onResolve: ((CGFloat) -> Void)?
        private var attempts = 0
        // Measure exactly once: the iOS 26 bar minimizes and shifts during
        // use, and re-measuring made the overlaid button wander with it.
        private var hasResolved = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard !hasResolved else { return }
            attempts = 0
            scheduleResolve()
        }

        func scheduleResolve() {
            guard !hasResolved else { return }
            DispatchQueue.main.async { [weak self] in self?.resolve() }
        }

        private func resolve() {
            guard !hasResolved, let window else { return }
            guard let offset = Self.middleSlotOffset(in: window) else {
                // the bar may not be laid out yet; retry briefly
                attempts += 1
                if attempts < 10 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.resolve() }
                }
                return
            }
            hasResolved = true
            onResolve?(offset)
        }

        private static func middleSlotOffset(in window: UIWindow) -> CGFloat? {
            var buttons: [UIView] = []
            collectTabButtons(in: window, into: &buttons)
            guard buttons.count == 5 else { return nil }
            buttons.sort { $0.convert($0.bounds, to: window).minX < $1.convert($1.bounds, to: window).minX }
            let slotCenterX = buttons[2].convert(buttons[2].bounds, to: window).midX
            return slotCenterX - window.bounds.midX
        }

        private static func collectTabButtons(in view: UIView, into buttons: inout [UIView]) {
            // iOS 26 items are _UITabButton; the classic bar uses UITabBarButton
            if String(describing: type(of: view)).contains("TabButton") ||
                String(describing: type(of: view)).contains("TabBarButton")
            {
                buttons.append(view)
                return
            }
            for subview in view.subviews {
                collectTabButtons(in: subview, into: &buttons)
            }
        }
    }
}
