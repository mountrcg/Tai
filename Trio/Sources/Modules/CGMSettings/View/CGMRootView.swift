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
        @State private var shouldShowSmoothingAlgorithmChangeDialog: Bool = false
        @State private var selectedVerboseHint: AnyView? = nil
        @State private var hintLabel: String? = nil

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var cgmSelectionButtons: some View {
            ForEach(cgmOptions, id: \.name) { option in
                if let cgm = state.listOfCGM.first(where: option.predicate) {
                    Button(option.name) {
                        state.addCGM(cgm: cgm)
                    }
                }
            }
        }

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
                                    Spacer()
                                    Button(
                                        action: {
                                            shouldDisplayHint1.toggle()
                                        },
                                        label: {
                                            HStack {
                                                Image(systemName: "questionmark.circle")
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
                booleanValue: $state.smoothGlucose,
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
                        "This feature smooths your CGM readings to reduce noise and make them easier to read. 2 Algorithms can be used, exponential smoothing is the method used in stock AndroidAPS (AAPS). Alternatively, a more sophisticated method using UKF is adopted from the AAPS Tsunami branch."
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
                }
            )
        }

        var smoothingAlgorithmSection: some View {
            Section(
                header: Text("Smoothing Algorithm"),
                content: {
                    VStack {
                        Picker(
                            selection: $state.smoothingAlgorithm,
                            label: Text("Algorithm Selection").multilineTextAlignment(.leading)
                        ) {
                            ForEach(GlucoseSmoothingAlgorithm.allCases) { algorithm in
                                Text(algorithm.displayName).tag(algorithm)
                            }
                        }
                        .padding(.top)
                        .onChange(of: state.smoothingAlgorithm) { oldValue, newValue in
                            if oldValue != newValue {
                                state.smoothGlucose = false
                                shouldShowSmoothingAlgorithmChangeDialog = true
                            }
                        }

                        HStack(alignment: .center) {
                            Text(
                                "Choose which smoothing algorithm shall be applied."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
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
                    }.padding(.bottom)
                }
            ).listRowBackground(Color.chart)
        }

        var body: some View {
            NavigationView {
                Form {
                    cgmIntegrationSection

                    if state.cgmCurrent.type == .plugin && state.cgmCurrent.id.contains("Libre") {
                        Section {
                            NavigationLink(
                                destination: Calibrations.RootView(resolver: resolver),
                                label: { Text("Libre Calibrations") }
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
                .navigationBarItems(leading: displayClose ? Button("Close", action: state.hideModal) : nil)
                .sheet(isPresented: $state.shouldDisplayCGMSetupSheet) {
                    switch state.cgmCurrent.type {
                    case .enlite,
                         .nightscout,
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
                                "• Dexcom G5\n" +
                                "• Dexcom G6 / ONE\n" +
                                "• Dexcom G7 / ONE+\n" +
                                "• Dexcom Share\n" +
                                "• Freestyle Libre\n" +
                                "• Freestyle Libre Demo\n" +
                                "• Glucose Simulator\n" +
                                "• Medtronic Enlite\n" +
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
                            "Available smoothing algorithms:\n\n" +
                                "• Second Order Exponential\n" +
                                "• Tsunami Unscented Kalman Filter\n\n" +
                                "Default: Exponential\n\n" +
                                "Second-Order Exponential Smoothing\n\n" +
                                "Benefit: provides a simple, fast filter that smooths CGM values and captures approximately linear trends with minimal computation.\n\n" +
                                "Second-order exponential smoothing (Holt's linear method) tracks both the level and the trend of a time series with two recursive updates.\n\n" +
                                "Unscented Kalman Filter (UKF)\n\n" +
                                "Benefit: adapts automatically to changing sensor quality and outliers while preserving real glucose dynamics with less lag.\n\n" +
                                "The UKF maintains a state vector xₜ = [Gₜ, Ġₜ]ᵀ (glucose Gₜ and its rate of change Ġₜ) and a covariance matrix Pₜ that represent both the estimate and its uncertainty.\n\n" +
                                "Each step predicts the state with a nonlinear process model, then fuses the new CGM value zₜ using a measurement-noise term Rₜ and the innovation νₜ = zₜ − ẑₜ.\n\n" +
                                "In the Tsunami adaptation, Rₜ is learned online from recent νₜ values using dual-rate updates (fast and slow), and suspicious points are handled softly by inflating an effective Rₑ instead of discarding them.\n\n" +
                                "A Rauch–Tung–Striebel (RTS) smoother then runs backward over each segment, using a smoothing gain Cₜ = Pₜ · Fₜᵀ · (P̂ₜ)⁻¹ to reduce lag and sharpen the final smoothed glucose curve."
                        ),
                        sheetTitle: String(localized: "Help", comment: "Help sheet title")
                    )
                }
                .sheet(isPresented: $shouldDisplayHint) {
                    SettingInputHintView(
                        hintDetent: $hintDetent,
                        shouldDisplayHint: $shouldDisplayHint,
                        hintLabel: hintLabel ?? "",
                        hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                        sheetTitle: String(localized: "Help", comment: "Help sheet title")
                    )
                }

                .confirmationDialog("CGM Model", isPresented: $showCGMSelection) {
                    cgmSelectionButtons
                } message: {
                    Text("Select CGM Model")
                }
                .confirmationDialog("Smoothing Algorithm Changed", isPresented: $shouldShowSmoothingAlgorithmChangeDialog) {
                    Button("Resume Smoothing") {
                        state.smoothGlucose = true
                    }
                } message: {
                    Text(
                        "Smoothing has been disabled to clear old smoothed values. Toggle smoothing back on to apply the new algorithm to all glucose readings."
                    )
                }
            }
        }
    }
}
