import LoopKitUI
import SwiftUI
import Swinject

extension CGMSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        let bluetoothManager: BluetoothStateManager
        @StateObject var state = StateModel()
        @State private var shouldDisplayHint: Bool = false
        @State private var shouldDisplayHint1: Bool = false
        @State private var shouldDisplayHint2: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State var showCGMSelection: Bool = false
        @State private var selectedVerboseHint: AnyView? = nil
        @State private var hintLabel: String? = nil
        @State private var pendingCGM: CGMCatalogEntry?

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var cgmIntegrationSection: some View {
            Section(
                header: Text("CGM Integration to Trio"),
                content: {
                    if bluetoothManager.bluetoothAuthorization != .authorized {
                        HStack {
                            Spacer()
                            BluetoothRequiredView()
                            Spacer()
                        }
                    } else {
                        let cgmState = state.cgmCurrent
                        if cgmState.type != .none {
                            Button {
                                state.shouldDisplayCGMSetupSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                                    Text(cgmState.displayName)
                                }
                                .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
                                .font(.title2)
                            }.padding()
                        } else {
                            VStack {
                                Button {
                                    showCGMSelection.toggle()
                                } label: {
                                    Text("Add CGM")
                                        .font(.title3) }
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .buttonStyle(.bordered)

                                HStack(alignment: .center) {
                                    Text(
                                        "Pair your CGM with Trio. See hint for compatible devices."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                    Spacer()
                                    Button(
                                        action: {
                                            shouldDisplayHint1.toggle()
                                        },
                                        label: {
                                            HStack {
                                                Image(systemName: "questionmark.circle")
                                                    .accessibilityLabel(Text("More information"))
                                            }
                                        }
                                    ).buttonStyle(BorderlessButtonStyle())
                                }.padding(.top)
                            }.padding(.vertical)
                        }
                    }
                }
            )
            .listRowBackground(Color.chart)
        }

        var smoothGlucoseSection: some View {
            SettingInputSection(
                decimalValue: $decimalPlaceholder,
                booleanValue: state.isSmoothingLocked ? .constant(true) : $state.smoothGlucose,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = String(localized: "Smooth Glucose Value", comment: "Smooth Glucose Value")
                    }
                ),
                units: state.units,
                type: .boolean,
                label: String(localized: "Smooth Glucose Value", comment: "Smooth Glucose Value"),
                miniHint: String(
                    localized: "Smooth CGM readings to reduce noise.",
                    comment: "Mini hint for smooth glucose value"
                ),
                verboseHint: VStack(alignment: .leading, spacing: 10) {
                    Text("Default: OFF").bold()

                    Text(
                        "This feature smooths your CGM readings to reduce noise and make them easier to read. Smoothing is either off or uses Adaptive UKF Smoothing; there is no other algorithm."
                    )

                    Text(
                        "Adaptive UKF Smoothing is mandatory while sub-5-minute loops are on: smoothing stays enabled and cannot be switched off until sub-5-minute loops are turned off."
                    )

                    Text(
                        "Trio will always display values based on your actual (raw) CGM readings. Smoothing does not change your real values or alerts."
                    )

                    Text("When this feature is enabled:")

                    VStack(alignment: .leading) {
                        Text(
                            "• The main chart and treatment chart show a light gray trend line for the smoothed values. The glucose dots always show your original CGM readings."
                        )

                        Text("• In Trio history, you will see the smoothed value next to the original reading.")

                        Text("• When you long-press a chart, the pop-up will show both the original and smoothed values.")
                    }

                    Text(
                        "This helps Trio make more stable dosing decisions by avoiding over-reactions to small or short-term changes. Important trends are kept, while unreliable fluctuations are filtered out."
                    )
                },
                footerText: state.isSmoothingLocked ? smoothingLockedCaption : nil,
                isToggleDisabled: state.isSmoothingLocked
            )
        }

        private var smoothingLockedCaption: String {
            String(
                localized: "Required while sub-5-minute loops are on — cannot be changed.",
                comment: "Caption under the locked smoothing toggle and algorithm while sub-5-minute loops are on"
            )
        }

        var smoothingAlgorithmSection: some View {
            Section(
                header: Text("Smoothing Algorithm"),
                content: {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(GlucoseSmoothingAlgorithm.adaptiveUkf.displayName)
                            Spacer()
                            Button(
                                action: {
                                    shouldDisplayHint2.toggle()
                                },
                                label: {
                                    HStack {
                                        Image(systemName: "questionmark.circle")
                                    }
                                }
                            ).buttonStyle(BorderlessButtonStyle())
                        }.padding(.top)

                        Text(
                            state.isSmoothingLocked ? smoothingLockedCaption : String(
                                localized: "Adaptive UKF Smoothing is the only smoothing algorithm.",
                                comment: "Caption under the smoothing algorithm row"
                            )
                        )
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .padding(.top)
                    }.padding(.bottom)
                }
            ).listRowBackground(Color.chart)
        }

        var body: some View {
            List {
                cgmIntegrationSection

                if state.cgmCurrent.type == .plugin && state.cgmCurrent.id.contains("Libre") {
                    Section {
                        NavigationLink(
                            destination: Calibrations.RootView(resolver: resolver),
                            label: { Text("Libre Calibrations") }
                        )
                    }.listRowBackground(Color.chart)
                }

                if state.cgmCurrent.type == .plugin,
                   state.fetchGlucoseManager?.cgmManager != nil,
                   state.cgmCurrent.id == state.fetchGlucoseManager?.cgmGlucosePluginId
                {
                    Section {
                        LogShareRow(
                            title: "Share CGM Logs",
                            footnote: "Creates one file you can send when asking for help.",
                            kinds: [.cgm],
                            logExport: state.logExport
                        )
                    }.listRowBackground(Color.chart)
                }

                smoothGlucoseSection

                smoothingAlgorithmSection
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("CGM")
            .navigationBarTitleDisplayMode(.automatic)
            .settingsHighlightScroll()
            .sheet(isPresented: $state.shouldDisplayCGMSetupSheet) {
                switch state.cgmCurrent.type {
                case .nightscout,
                     .none,
                     .simulator,
                     .xdrip:

                    CustomCGMOptionsView(
                        resolver: self.resolver,
                        state: state,
                        cgmCurrent: state.cgmCurrent,
                        deleteCGM: state.deleteCGM
                    )

                case .plugin:
                    if let fetchGlucoseManager = state.fetchGlucoseManager,
                       let cgmManager = fetchGlucoseManager.cgmManager,
                       state.cgmCurrent.type == fetchGlucoseManager.cgmGlucoseSourceType,
                       state.cgmCurrent.id == fetchGlucoseManager.cgmGlucosePluginId
                    {
                        CGMSettingsView(
                            cgmManager: cgmManager,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            unit: state.settingsManager.settings.units,
                            completionDelegate: state
                        )
                    } else {
                        CGMSetupView(
                            CGMType: state.cgmCurrent,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            unit: state.settingsManager.settings.units,
                            completionDelegate: state,
                            setupDelegate: state,
                            pluginCGMManager: self.state.pluginCGMManager
                        ).onDisappear {
                            if state.fetchGlucoseManager.cgmGlucoseSourceType == .none {
                                state.cgmCurrent = cgmDefaultModel
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $shouldDisplayHint1) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint1,
                    hintLabel: "CGM Models",
                    hintText: Text(
                        "Current CGM Models Supported:\n\n" +
                            "• Accu-Chek SmartGuide\n" +
                            "• Dexcom G5\n" +
                            "• Dexcom G6 / ONE\n" +
                            "• Dexcom G7 / ONE+\n" +
                            "• Dexcom Share\n" +
                            "• Eversense E3/365\n" +
                            "• Freestyle Libre\n" +
                            "• Freestyle Libre Demo\n" +
                            "• Glucose Simulator\n" +
                            "• Nightscout\n" +
                            "• xDrip4iOS\n\n" +
                            "Note: The CGM Heartbeat can come from either a CGM or a pump to wake up Trio when phone is locked or in the background. If CGM is on the same phone as Trio and xDrip4iOS is configured to use the same AppGroup as Trio and the heartbeat feature is turned on in xDrip4iOS, then the CGM can provide a heartbeat to wake up Trio when phone is locked or app is in the background."
                    ),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            .sheet(isPresented: $shouldDisplayHint2) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint2,
                    hintLabel: "Smoothing Algorithms",
                    hintText: Text(
                        "Adaptive UKF Smoothing\n\n" +
                            "Benefit: an Unscented Kalman Filter (AAPS Boost variant) with a statistically corrected noise estimator, faster trend detection, and protection against sensor-compression lows.\n\n" +
                            "The filter maintains a state vector xₜ = [Gₜ, Ġₜ]ᵀ (glucose Gₜ and its rate of change Ġₜ) and a covariance matrix Pₜ that represent both the estimate and its uncertainty.\n\n" +
                            "It learns the measurement noise Rₜ by subtracting the predicted variance from the innovation statistics, ramps outlier down-weighting in gently from 2σ (Huber-style), and detects genuine fast moves with a 2-of-3 same-sign gate so it accelerates onto real trends sooner.\n\n" +
                            "A steep drop below 75 mg/dL with little insulin on board is treated as a probable sensor-compression low and heavily down-weighted for at most 3 readings — a real, insulin-driven low always passes through.\n\n" +
                            "Adaptive UKF Smoothing is mandatory while sub-5-minute loops are on."
                    ),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "Current CGM Models Supported:"
                            )
                            VStack(alignment: .leading) {
                                ForEach(DeviceCatalog.cgms.filter(\.isSelectableInPicker)) { cgm in
                                    Text("• \(cgm.hintLine)")
                                }
                            }
                            Text(
                                "Note: The CGM Heartbeat can come from either a CGM or a pump to wake up Trio when phone is locked or in the background. If CGM is on the same phone as Trio and xDrip4iOS is configured to use the same AppGroup as Trio and the heartbeat feature is turned on in xDrip4iOS, then the CGM can provide a heartbeat to wake up Trio when phone is locked or app is in the background."
                            )
                        }
                    ),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            // Selection is applied in onDismiss so the setup sheet is presented only once the picker is gone.
            .sheet(isPresented: $showCGMSelection, onDismiss: {
                if let entry = pendingCGM {
                    pendingCGM = nil
                    state.addCGM(cgm: CGMModel(entry))
                }
            }) {
                DevicePickerView(
                    title: String(localized: "Add CGM", comment: "The title of the CGM chooser in settings"),
                    entries: DeviceCatalog.cgms
                ) { entry in
                    pendingCGM = entry
                    showCGMSelection = false
                }
            }
        }
    }
}
