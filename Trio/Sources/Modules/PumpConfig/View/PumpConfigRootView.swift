import LoopKitUI
import SwiftUI
import Swinject

extension PumpConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        let displayClose: Bool
        let bluetoothManager: BluetoothStateManager
        @StateObject var state = StateModel()
        @State private var showConcentrationEditor = false
        @State private var showEditConcentrationWarning = false
        @State private var shouldDisplayHint: Bool = false
        @State private var shouldDisplayHintPump: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State var showPumpSelection: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            NavigationView {
                List {
                    Section(
                        content: {
                            VStack {
                                if state.pumpState == nil {
                                    HStack {
                                        Text("Current Concentration")
                                        Spacer()
                                        Text(
                                            "U\(Int(truncating: NSDecimalNumber(decimal: state.insulinConcentration * 100)))"
                                        )
                                    }
                                    .contentShape(Rectangle()) // Ensures full-row tappability
                                    .navigationLink(to: .insulinConcentration, from: self)
                                } else {
                                    HStack {
                                        Text("Current Concentration")
                                        Spacer()
                                        Text("U\(Int(truncating: NSDecimalNumber(decimal: state.insulinConcentration * 100)))")
                                    }.foregroundColor(.secondary)
                                        .onTapGesture { showEditConcentrationWarning = true }
                                }

                                HStack(alignment: .center) {
                                    Text(
                                        "The insulin concentration is given in Insulin Units per mL. The standard is U100 with 100 U/mL."
                                    )
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(nil)
                                    Spacer()
                                    Button(action: {
                                        shouldDisplayHint.toggle()
                                        selectedVerboseHint = AnyView(
                                            VStack(alignment: .leading, spacing: 10) {
                                                Text("Delete pump if you need to change Insulin Concentration")
                                                    .fontWeight(.bold)
                                                Text(
                                                    "The insulin concentration can only be changed if you change the insulin in your pump. To make that sure for every pump model, you will have to delete the current pump, change the Insulin Concentration and add your pump again."
                                                )
                                            }
                                        )
                                        hintLabel = String(
                                            localized:
                                            "Insulin Concentration",
                                            comment: "Insulin Concentration"
                                        )
                                    }) { HStack { Image(systemName: "questionmark.circle") }}
                                        .buttonStyle(BorderlessButtonStyle())
                                }.padding(.vertical)
                            }
                        },
                        header: { Text("Insulin Concentration") }
                    )
                    .listRowBackground(Color.chart)
                    .alert(isPresented: $showEditConcentrationWarning) {
                        Alert(
                            title: Text("Cannot change Concentration"),
                            message: Text("To edit insulin concentration, you must first remove the pump."),
                            dismissButton: .default(Text("Got it!"))
                        )
                    }

                    Section(
                        header: Text("Pump Integration to Trio"),
                        content: {
                            if bluetoothManager.bluetoothAuthorization != .authorized {
                                HStack {
                                    Spacer()
                                    BluetoothRequiredView()
                                    Spacer()
                                }
                            } else if let pumpState = state.pumpState {
                                Button {
                                    state.requestOpenPumpSettings()
                                } label: {
                                    HStack {
                                        Image(uiImage: pumpState.image ?? UIImage())
                                            .resizable()
                                            .scaledToFit()
                                            .frame(maxWidth: 100)
                                        Text(pumpState.name)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .center)
                                    .font(.title2)
                                }.padding()
                                if state.hasUnacknowledgedAlert {
                                    Spacer()
                                    Button("Acknowledge all alerts") { state.ack() }
                                }
                            } else {
                                VStack {
                                    Button {
                                        showPumpSelection.toggle()
                                    } label: {
                                        Text("Add Pump")
                                            .font(.title3) }
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .buttonStyle(.bordered)

                                    HStack(alignment: .center) {
                                        Text(
                                            "Pair your insulin pump with Trio. See hint for compatible devices."
                                        )
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                        .lineLimit(nil)
                                        Spacer()
                                        Button(
                                            action: {
                                                shouldDisplayHintPump.toggle()
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
                    )
                    .listRowBackground(Color.chart)

                    Section(
                        header: Text("Insulin Curve Parameters"),
                        content: {
                            SettingInputSection(
                                decimalValue: $state.insulinActionCurve,
                                booleanValue: $booleanPlaceholder,
                                shouldDisplayHint: $shouldDisplayHint,
                                selectedVerboseHint: Binding(
                                    get: { selectedVerboseHint },
                                    set: {
                                        selectedVerboseHint = $0.map { AnyView($0) }
                                        hintLabel = String(
                                            localized: "Duration of Insulin Action",
                                            comment: "Duration of Insulin Action"
                                        )
                                    }
                                ),
                                units: state.units,
                                type: .decimal("dia"),
                                label: String(localized: "Duration of Insulin Action", comment: "Duration of Insulin Action"),
                                miniHint: String(
                                    localized: "Number of hours insulin is active in your body.",
                                    comment: "Mini Hint for Duration of Insulin Action"
                                ),
                                verboseHint:
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Default: 10 hours").bold()
                                    Text(
                                        "The Duration of Insulin Action (DIA) defines how long your insulin continues to lower glucose readings after a dose."
                                    )
                                    Text(
                                        "This helps the system accurately track Insulin on Board (IOB), avoiding over- or under-corrections by considering the tail end of insulin's effect."
                                    )
                                    Text(
                                        "Tip: It is better to use Custom Peak Time rather than adjust your Duration of Insulin Action (DIA)."
                                    )
                                }
                            )

                            SettingInputSection(
                                decimalValue: $state.insulinPeakTime,
                                booleanValue: $state.useCustomPeakTime,
                                shouldDisplayHint: $shouldDisplayHint,
                                selectedVerboseHint: Binding(
                                    get: { selectedVerboseHint },
                                    set: {
                                        selectedVerboseHint = $0.map { AnyView($0) }
                                        hintLabel = String(localized: "Use Custom Peak Time", comment: "Use Custom Peak Time")
                                    }
                                ),
                                units: state.units,
                                type: .conditionalDecimal("insulinPeakTime"),
                                label: String(localized: "Use Custom Peak Time", comment: "Use Custom Peak Time"),
                                conditionalLabel: String(localized: "Insulin Peak Time", comment: "Insulin Peak Time"),
                                miniHint: "Set a custom time for peak insulin effect.",
                                verboseHint:
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Default: Set by Insulin Type").bold()
                                    Text(
                                        "Insulin Peak Time defines when insulin is most effective in lowering glucose, set in minutes after dosing."
                                    )
                                    Text(
                                        "This peak informs the system when to expect the most potent glucose-lowering effect, helping it predict glucose trends more accurately."
                                    )
                                    Text("System-Determined Defaults:").bold()
                                    Text("Ultra-Rapid: 55 minutes (permitted range 35-100 minutes)")
                                    Text("Rapid-Acting: 75 minutes (permitted range 50-120 minutes)")
                                }
                            )
                        }
                    )

                    Section(
                        header: Text("Concentration Settings"),
                        content: {
                            SettingInputSection(
                                decimalValue: $decimalPlaceholder,
                                booleanValue: $state.hideInsulinBadge,
                                shouldDisplayHint: $shouldDisplayHint,
                                selectedVerboseHint: Binding(
                                    get: { selectedVerboseHint },
                                    set: {
                                        selectedVerboseHint = $0.map { AnyView($0) }
                                        hintLabel = String(localized: "Hide Insulin Concentration badge", comment: "Hide Badge")
                                    }
                                ),
                                units: state.units,
                                type: .boolean,
                                label: String(localized: "Hide Insulin Concentration badge", comment: "Hide Badge"),
                                miniHint: "Hide the badge that displays the Insulin Concentration near between the Glucose bobble and the pump information.",
                                verboseHint:
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Default: Badge displayed").bold()
                                    Text(
                                        "U50 or other diluted insulins will lead to more insulin volume being pumped. So it is essential to be aware of the setting that concentrated or especially diluted insulin is used."
                                    )
                                    Text(
                                        "Having the U50 active but with U100 in the pump will be very dangerous. Don't hide the badge unless you do not change anything in the longterm - diluted insulins are shown in red, concentrated in yellow."
                                    )
                                }
                            )

                            SettingInputSection(
                                decimalValue: $decimalPlaceholder,
                                booleanValue: $state.allowDilution,
                                shouldDisplayHint: $shouldDisplayHint,
                                selectedVerboseHint: Binding(
                                    get: { selectedVerboseHint },
                                    set: {
                                        selectedVerboseHint = $0.map { AnyView($0) }
                                        hintLabel = String(localized: "Allow diluted Insulin", comment: "Allow diluted Insulin")
                                    }
                                ),
                                units: state.units,
                                type: .boolean,
                                label: String(localized: "Allow diluted Insulin", comment: "Allow diluted Insulin"),
                                miniHint: "Allow diluted insulin concentration settings.",
                                verboseHint:
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Default: OFF").bold()
                                    Text(
                                        "U50 or other diluted insulins will lead to more insulin volume being pumped. Using a diluted Insulin concentration will inject larger volumes. If not set correctly potential errors can lead to severe overdosing of insulin."
                                    )
                                }
                            )
                        }
                    )
                }
                .listSectionSpacing(sectionSpacing)
                .tint(Color.tabBar)
                .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
                .onAppear(perform: configureView)
                .onAppear {
                    state.insulinConcentration = state.settings.settings.insulinConcentration
                }
                .onDisappear {
                    state.saveIfChanged()
                }
                .navigationTitle("Pump & Concentration")
                .navigationBarTitleDisplayMode(.automatic)
                .navigationBarItems(leading: displayClose ? Button("Close", action: state.hideModal) : nil)
                .sheet(isPresented: $shouldDisplayHint) {
                    SettingInputHintView(
                        hintDetent: $hintDetent,
                        shouldDisplayHint: $shouldDisplayHint,
                        hintLabel: hintLabel ?? "",
                        hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                        sheetTitle: "Help"
                    )
                }
                .sheet(isPresented: $state.setupPump) {
                    if let pumpManager = state.provider.apsManager.pumpManager
                    {
                        PumpSettingsView(
                            pumpManager: pumpManager,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            completionDelegate: state,
                            setupDelegate: state
                        )
                    } else {
                        PumpSetupView(
                            pumpType: state.setupPumpType,
                            pumpInitialSettings: state.initialSettings,
                            bluetoothManager: state.provider.apsManager.bluetoothManager!,
                            completionDelegate: state,
                            setupDelegate: state
                        )
                    }
                }
                .confirmationDialog(
                    "Pump Settings Use U100 Units",
                    isPresented: $state.shouldDisplayPumpConcentrationWarning,
                    titleVisibility: .visible
                ) {
                    Button("Open Pump Settings Anyway", role: .destructive) {
                        state.setupPump = true
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "You're using U\(Int(truncating: NSDecimalNumber(decimal: state.insulinConcentration * 100))) insulin. The pump's built-in screens (basal, temp basal, bolus) only understand U100 — any insulin amount you enter there will be sent to the pump as a U100 value. The pump driver has no concept of concentration.\n\nUse Trio's Manual Temp Basal and Bolus buttons instead — those apply the concentration scaling correctly."
                    )
                }
                .sheet(isPresented: $shouldDisplayHintPump) {
                    SettingInputHintView(
                        hintDetent: $hintDetent,
                        shouldDisplayHint: $shouldDisplayHintPump,
                        hintLabel: "Pump Pairing to Trio",
                        hintText: AnyView(
                            VStack(alignment: .leading, spacing: 10) {
                                Text(
                                    "Current Pump Models Supported:"
                                )
                                VStack(alignment: .leading) {
                                    Text("• Medtronic")
                                    Text("• All Omnipod Types")
                                    Text("• Omnipod Eros")
                                    Text("• Omnipod DASH")
                                    Text("• Dana (RS/-i)")
                                    Text("• Medtrum Nano (200u/300u)")
                                    Text("• Pump Simulator")
                                }
                                Text(
                                    "Note: If using a pump simulator, you will not have continuous readings from the CGM in Trio. Using a pump simulator is only advisable for becoming familiar with the app user interface. It will not give you insight on how the algorithm will respond."
                                )
                            }
                        ),
                        sheetTitle: String(localized: "Help", comment: "Help sheet title")
                    )
                }
                .confirmationDialog("Pump Model", isPresented: $showPumpSelection) {
                    Button("Medtronic") { state.addPump(.minimed) }
                    Button("All Omnipod Types") { state.addPump(.omni) }
                    Button("Omnipod Eros") { state.addPump(.omnipod) }
                    Button("Omnipod DASH") { state.addPump(.omnipodBLE) }
                    Button("Dana(RS/-i)") { state.addPump(.dana) }
                    Button("Medtrum Nano") { state.addPump(.medtrum) }
                    if !Bundle.main.simulatorVisibility.isHidden {
                        Button("Pump Simulator") { state.addPump(.simulator) }
                    }
                } message: { Text("Select Pump Model") }
            }
        }
    }
}
