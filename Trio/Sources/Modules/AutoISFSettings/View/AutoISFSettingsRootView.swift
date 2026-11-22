import SwiftUI
import Swinject

extension AutoISFSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var denseParabolaSection: some View {
            Section(header: Text("Dense Parabola Fit")) {
                parabolaInput(
                    label: String(localized: "Parabola on Smoothed Glucose"),
                    explanation: String(
                        localized: "Default: OFF. Requires trusted dense readings, glucose smoothing and AutoISF. Otherwise the raw fit remains in use."
                    ),
                    boolean: $state.autoISFParabolaSmoothed
                )
                parabolaInput(
                    label: String(localized: "Automatic Parabola Minimum"),
                    explanation: String(
                        localized: "Default: Automatic. Uses 10 minutes for a qualified cadence below 90 seconds, otherwise 15 minutes. A manual minimum may be 5–20 minutes."
                    ),
                    boolean: Binding(
                        get: { state.autoISFParabolaMinMinutes == nil },
                        set: { state.autoISFParabolaMinMinutes = $0 ? nil : state.automaticParabolaMinimum }
                    )
                )
                if state.autoISFParabolaMinMinutes != nil {
                    parabolaInput(
                        label: String(localized: "Shortest Parabola Duration"),
                        explanation: String(localized: "Default: Automatic. This minimum affects the dense AutoISF fit only."),
                        decimal: Binding(
                            get: { state.autoISFParabolaMinMinutes ?? state.automaticParabolaMinimum },
                            set: { state.autoISFParabolaMinMinutes = $0 }
                        ), key: "autoISFParabolaMinMinutes"
                    )
                } else {
                    Text("Automatic parabola minimum: \(state.automaticParabolaMinimum.description) min.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.chart)
        }

        private func parabolaInput(
            label: String, explanation: String, boolean: Binding<Bool> = .constant(false),
            decimal: Binding<Decimal> = .constant(0), key: String? = nil
        ) -> some View {
            SettingInputSection(
                decimalValue: decimal, booleanValue: boolean, shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = label
                    }
                ),
                units: state.units, type: key.map { .decimal($0) } ?? .boolean,
                label: label, miniHint: explanation,
                verboseHint: Text(explanation)
            )
        }

        var body: some View {
            List {
                Section(
                    header: Text("Enable"),
                    content: {
                        SettingInputSection(
                            decimalValue: .constant(0),
                            booleanValue: $state.autoisf,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = AlgorithmSettingHints.autoISFTitleLabel
                                }
                            ),
                            units: state.units,
                            type: .boolean,
                            label: AlgorithmSettingHints.activateAutoISFLabel,
                            miniHint: AlgorithmSettingHints.activateAutoISFMini,
                            verboseHint: AlgorithmSettingHints.activateAutoISFVerbose()
                        )
                    }
                )

                if state.isSuitableSource {
                    denseParabolaSection
                }

                if state.autoisf {
                    Section {
                        SettingInputSection(
                            decimalValue: .constant(0),
                            booleanValue: $state.enableAutosens,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = AlgorithmSettingHints.enableAutosensAutoISFLabel
                                }
                            ),
                            units: state.units,
                            type: .boolean,
                            label: AlgorithmSettingHints.enableAutosensAutoISFLabel,
                            miniHint: AlgorithmSettingHints.enableAutosensAutoISFMini,
                            verboseHint: AlgorithmSettingHints.enableAutosensAutoISFVerbose()
                        )

                        // Odd  Targets disables SMB for autoISF
                        SettingInputSection(
                            decimalValue: .constant(0),
                            booleanValue: $state.enableSMBEvenOnOddOffAlways,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = AlgorithmSettingHints.oddTargetDisablesSMBLabel
                                }
                            ),
                            units: state.units,
                            type: .boolean,
                            label: AlgorithmSettingHints.oddTargetDisablesSMBLabel,
                            miniHint: AlgorithmSettingHints.oddTargetDisablesSMBMini,
                            verboseHint: AlgorithmSettingHints.oddTargetDisablesSMBVerbose(units: state.units)
                        )

                        // Exercise toggles all autoISF adjustments off
                        SettingInputSection(
                            decimalValue: .constant(0),
                            booleanValue: $state.autoISFoffSport,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = AlgorithmSettingHints.autoISFoffSportLabel
                                }
                            ),
                            units: state.units,
                            type: .boolean,
                            label: AlgorithmSettingHints.autoISFoffSportLabel,
                            miniHint: AlgorithmSettingHints.autoISFoffSportMini,
                            verboseHint: AlgorithmSettingHints.autoISFoffSportVerbose()
                        )

                        // autoISF IOB Threshold Percent
                        SettingInputSection(
                            decimalValue: $state.iobThresholdPercent,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = AlgorithmSettingHints.iobThresholdPercentLabel
                                }
                            ),
                            units: state.units,
                            type: .decimal("iobThresholdPercent"),
                            label: AlgorithmSettingHints.iobThresholdPercentLabel,
                            miniHint: AlgorithmSettingHints.iobThresholdPercentMini,
                            verboseHint: AlgorithmSettingHints.iobThresholdPercentVerbose()
                        )

                        // autoISF Max
                        SettingInputSection(
                            decimalValue: $state.autoISFmax,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = AlgorithmSettingHints.autoISFmaxLabel
                                }
                            ),
                            units: state.units,
                            type: .decimal("autoISFmax"),
                            label: AlgorithmSettingHints.autoISFmaxLabel,
                            miniHint: AlgorithmSettingHints.autoISFmaxMini,
                            verboseHint: AlgorithmSettingHints.autoISFmaxVerbose()
                        )

                        // autoISF Min
                        SettingInputSection(
                            decimalValue: $state.autoISFmin,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = AlgorithmSettingHints.autoISFminLabel
                                }
                            ),
                            units: state.units,
                            type: .decimal("autoISFmin"),
                            label: AlgorithmSettingHints.autoISFminLabel,
                            miniHint: AlgorithmSettingHints.autoISFminMini,
                            verboseHint: AlgorithmSettingHints.autoISFminVerbose()
                        )
                    } header: { Text("General") }
                    Section {
                        // Enable BG Acceleration
                        SettingInputSection(
                            decimalValue: .constant(0),
                            booleanValue: $state.enableBGacceleration,
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = AlgorithmSettingHints.enableBGaccelerationLabel
                                }
                            ),
                            units: state.units,
                            type: .boolean,
                            label: AlgorithmSettingHints.enableBGaccelerationLabel,
                            miniHint: AlgorithmSettingHints.enableBGaccelerationMini,
                            verboseHint: AlgorithmSettingHints.enableBGaccelerationVerbose()
                        )
                        if state.enableBGacceleration {
                            // ISF Weight While BG Accelerates
                            SettingInputSection(
                                decimalValue: $state.bgAccelISFweight,
                                booleanValue: .constant(false),
                                shouldDisplayHint: $shouldDisplayHint,
                                selectedVerboseHint: Binding(
                                    get: { selectedVerboseHint },
                                    set: {
                                        selectedVerboseHint = $0.map { AnyView($0) }
                                        hintLabel = AlgorithmSettingHints.bgAccelISFweightLabel
                                    }
                                ),
                                units: state.units,
                                type: .decimal("bgAccelISFweight"),
                                label: AlgorithmSettingHints.bgAccelISFweightLabel,
                                miniHint: AlgorithmSettingHints.bgAccelISFweightMini,
                                verboseHint: AlgorithmSettingHints.bgAccelISFweightVerbose()
                            )
                            SettingInputSection(
                                decimalValue: $state.bgBrakeISFweight,
                                booleanValue: .constant(false),
                                shouldDisplayHint: $shouldDisplayHint,
                                selectedVerboseHint: Binding(
                                    get: { selectedVerboseHint },
                                    set: {
                                        selectedVerboseHint = $0.map { AnyView($0) }
                                        hintLabel = AlgorithmSettingHints.bgBrakeISFweightLabel
                                    }
                                ),
                                units: state.units,
                                type: .decimal("bgAccelISFweight"),
                                label: AlgorithmSettingHints.bgBrakeISFweightLabel,
                                miniHint: AlgorithmSettingHints.bgBrakeISFweightMini,
                                verboseHint: AlgorithmSettingHints.bgBrakeISFweightVerbose()
                            )
                        }
                    } header: { Text("Acce-ISF") }
                    Section {
                        // ISF Weight for Higher BGs
                        SettingInputSection(
                            decimalValue: $state.higherISFrangeWeight,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = AlgorithmSettingHints.higherISFrangeWeightLabel
                                }
                            ),
                            units: state.units,
                            type: .decimal("higherISFrangeWeight"),
                            label: AlgorithmSettingHints.higherISFrangeWeightLabel,
                            miniHint: AlgorithmSettingHints.higherISFrangeWeightMini,
                            verboseHint: AlgorithmSettingHints.higherISFrangeWeightVerbose()
                        )
                        // ISF Weight for Lower BGs
                        SettingInputSection(
                            decimalValue: $state.lowerISFrangeWeight,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = AlgorithmSettingHints.lowerISFrangeWeightLabel
                                }
                            ),
                            units: state.units,
                            type: .decimal("lowerISFrangeWeight"),
                            label: AlgorithmSettingHints.lowerISFrangeWeightLabel,
                            miniHint: AlgorithmSettingHints.lowerISFrangeWeightMini,
                            verboseHint: AlgorithmSettingHints.lowerISFrangeWeightVerbose()
                        )
                    } header: { Text("BG-ISF") }
                    Section {
                        // ISF weight for postprandial BG rise
                        SettingInputSection(
                            decimalValue: $state.postMealISFweight,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = AlgorithmSettingHints.postMealISFweightLabel
                                }
                            ),
                            units: state.units,
                            type: .decimal("postMealISFweight"),
                            label: AlgorithmSettingHints.postMealISFweightLabel,
                            miniHint: AlgorithmSettingHints.postMealISFweightMini,
                            verboseHint: AlgorithmSettingHints.postMealISFweightVerbose()
                        )
                    } header: { Text("pp-ISF") }
                    Section {
                        // DuraISF Weight
                        SettingInputSection(
                            decimalValue: $state.autoISFhourlyChange,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = AlgorithmSettingHints.autoISFhourlyChangeLabel
                                }
                            ),
                            units: state.units,
                            type: .decimal("autoISFhourlyChange"),
                            label: AlgorithmSettingHints.autoISFhourlyChangeLabel,
                            miniHint: AlgorithmSettingHints.autoISFhourlyChangeMini,
                            verboseHint: AlgorithmSettingHints.autoISFhourlyChangeVerbose()
                        )
                    } header: { Text("Dura-ISF") }
                    Section {
                        // SMB DeliveryRatio
                        SettingInputSection(
                            decimalValue: $state.smbDeliveryRatio,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = AlgorithmSettingHints.smbDeliveryRatioFixedHintLabel
                                }
                            ),
                            units: state.units,
                            type: .decimal("smbDeliveryRatio"),
                            label: AlgorithmSettingHints.smbDeliveryRatioFixedLabel,
                            miniHint: AlgorithmSettingHints.smbDeliveryRatioFixedMini,
                            verboseHint: AlgorithmSettingHints.smbDeliveryRatioFixedVerbose()
                        )
                        // SMB DeliveryRatio BG Range
                        SettingInputSection(
                            decimalValue: $state.smbDeliveryRatioBGrange,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = AlgorithmSettingHints.smbDeliveryRatioBGrangeLabel
                                }
                            ),
                            units: state.units,
                            type: .decimal("smbDeliveryRatioBGrange"),
                            label: AlgorithmSettingHints.smbDeliveryRatioBGrangeLabel,
                            miniHint: AlgorithmSettingHints.smbDeliveryRatioBGrangeMini(units: state.units),
                            verboseHint: AlgorithmSettingHints.smbDeliveryRatioBGrangeVerbose(units: state.units)
                        )
                        if state.smbDeliveryRatioBGrange != 0 {
                            // SMB DeliveryRatio BG Minimum
                            SettingInputSection(
                                decimalValue: $state.smbDeliveryRatioMin,
                                booleanValue: .constant(false),
                                shouldDisplayHint: $shouldDisplayHint,
                                selectedVerboseHint: Binding(
                                    get: { selectedVerboseHint },
                                    set: {
                                        selectedVerboseHint = $0.map { AnyView($0) }
                                        hintLabel = AlgorithmSettingHints.smbDeliveryRatioMinLabel
                                    }
                                ),
                                units: state.units,
                                type: .decimal("smbDeliveryRatioMin"),
                                label: AlgorithmSettingHints.smbDeliveryRatioMinLabel,
                                miniHint: AlgorithmSettingHints.smbDeliveryRatioMinMini,
                                verboseHint: AlgorithmSettingHints.smbDeliveryRatioMinVerbose()
                            )
                            // SMB DeliveryRatio BG Maximum
                            SettingInputSection(
                                decimalValue: $state.smbDeliveryRatioMax,
                                booleanValue: .constant(false),
                                shouldDisplayHint: $shouldDisplayHint,
                                selectedVerboseHint: Binding(
                                    get: { selectedVerboseHint },
                                    set: {
                                        selectedVerboseHint = $0.map { AnyView($0) }
                                        hintLabel = AlgorithmSettingHints.smbDeliveryRatioMaxLabel
                                    }
                                ),
                                units: state.units,
                                type: .decimal("smbDeliveryRatioMax"),
                                label: AlgorithmSettingHints.smbDeliveryRatioMaxLabel,
                                miniHint: AlgorithmSettingHints.smbDeliveryRatioMaxMini,
                                verboseHint: AlgorithmSettingHints.smbDeliveryRatioMaxVerbose()
                            )
                        }
                        // SMB Max RangeExtension
                        SettingInputSection(
                            decimalValue: $state.smbMaxRangeExtension,
                            booleanValue: .constant(false),
                            shouldDisplayHint: $shouldDisplayHint,
                            selectedVerboseHint: Binding(
                                get: { selectedVerboseHint },
                                set: {
                                    selectedVerboseHint = $0.map { AnyView($0) }
                                    hintLabel = AlgorithmSettingHints.smbMaxRangeExtensionLabel
                                }
                            ),
                            units: state.units,
                            type: .decimal("smbMaxRangeExtension"),
                            label: AlgorithmSettingHints.smbMaxRangeExtensionLabel,
                            miniHint: AlgorithmSettingHints.smbMaxRangeExtensionMini,
                            verboseHint: AlgorithmSettingHints.smbMaxRangeExtensionVerbose()
                        )
                    } header: { Text("SMB Delivery Ratios") }
                } else {
                    VStack(alignment: .leading) {
                        Text(
                            "autoISF allows to adapt the insulin sensitivity factor (ISF) in the following scenarios of glucose behaviour:"
                        )
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                        BulletList(
                            listItems:
                            [
                                "accelerating/decelerating blood glucose",
                                "blood glucose levels according to a predefined polygon, like a Sigmoid",
                                "postprandial (after meal) glucose rise",
                                "blood glucose plateaus above target"
                            ],
                            listItemSpacing: 10
                        )
                        Image("autoISF_factors")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 300)
                            .padding(5)
                        Text("It can also adapt SMB delivery settings.")
                        Text("Read up on it at:").padding(.top)
                        SwiftUI.Link(
                            "autoISF 3.01 Documentation",
                            destination: URL(
                                string: "https://github.com/ga-zelle/autoISF"
                            )!
                        )
                        .accentColor(.blue)
                        Text("Tai as the Trio version of autoISF does not include ActivityTracking.")
                    }
                }
            }
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: "Help"
                )
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("autoISF Settings")
            .navigationBarTitleDisplayMode(.automatic)
            .settingsHighlightScroll()
        }
    }
}
