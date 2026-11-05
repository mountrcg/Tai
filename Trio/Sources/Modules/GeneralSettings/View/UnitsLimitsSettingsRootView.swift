import SwiftUI
import Swinject

extension UnitsLimitsSettings {
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
        @EnvironmentObject var appIcons: Icons
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                Section(
                    header: Text("Trio Core Setup"),
                    content: {
                        Picker("Glucose Units", selection: $state.unitsIndex) {
                            Text("mg/dL").tag(0)
                            Text("mmol/L").tag(1)
                        }
                    }
                ).listRowBackground(Color.chart)

                SettingInputSection(
                    decimalValue: $state.maxIOB,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Maximum Insulin on Board (IOB)", comment: "Max IOB")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxIOB"),
                    label: String(localized: "Maximum Insulin on Board (IOB)", comment: "Max IOB"),
                    miniHint: String(localized: "Maximum units of insulin allowed to be active."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 0 units").bold()

                        Text(
                            "Note: This setting must be greater than 0 for any automatic insulin dosing by Trio (unless you currently have negative IOB)."
                        )
                        .bold()
                        .foregroundStyle(Color.orange)

                        Text(
                            "Choose a value that covers your highest insulin needs — think about a correction for a very high glucose reading plus your biggest meal bolus. This gives Trio room to work while keeping you safe."
                        )

                        Text(
                            "Max IOB sets a safety limit on how much insulin Trio can automatically deliver above your scheduled basal rates. This prevents the system from giving too much insulin at once."
                        )

                        VStack(alignment: .leading, spacing: 0) {
                            Text("Trio calculates your current Insulin On Board (IOB) from:")
                            Text("• Boluses (including SMBs)")
                            Text("• Temporary Basal Rates (TBRs)")
                            Text("  ◦ A TBR higher than your scheduled rate will increase IOB")
                            Text("  ◦ A TBR lower than your scheduled rate will decrease IOB")
                        }

                        Text(
                            "If delivering more insulin would push your IOB above this limit, Trio will reduce or skip the dose to stay within the safety boundary. This applies to SMBs, TBRs, and the recommendation from the bolus calculator."
                        )

                        VStack(alignment: .leading, spacing: 0) {
                            Text("What's NOT limited:")
                            Text("• Manual boluses you enter yourself")
                            Text("• Manual temporary basal rates you set yourself")
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                )

                SettingInputSection(
                    decimalValue: $state.maxBolus,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Maximum Bolus")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxBolus"),
                    label: String(localized: "Maximum Bolus"),
                    miniHint: String(localized: "Largest bolus of insulin allowed."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 10 units").bold()
                        Text(
                            "This is the maximum bolus allowed to be delivered at one time. This only limits manual boluses and does not limit SMBs."
                        )
                        Text("Most set this to their largest meal bolus. Then, adjust if needed.")
                        Text("If you attempt to request a bolus larger than this, the bolus will not be accepted.")
                    }
                )

                SettingInputSection(
                    decimalValue: $state.maxBasal,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Max Basal Rate")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxBasal"),
                    label: String(localized: "Maximum Basal Rate"),
                    miniHint: String(localized: "Largest basal rate allowed."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 2 \(String(localized: "U/hr", comment: "Insulin unit per hour abbreviation"))").bold()
                        Text(
                            "This is the maximum basal rate allowed to be set or scheduled. This applies to both automatic and manual basal rates."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.maxCOB,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Maximum Carbs on Board (COB)", comment: "Max COB")
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxCOB"),
                    label: String(localized: "Maximum Carbs on Board (COB)", comment: "Max COB"),
                    miniHint: String(localized: "Maximum amount of active carbs considered by the algorithm."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 120 grams of carbs").bold()
                        Text(
                            "This setting defines the maximum amount of Carbs On Board (COB) at any given time for Trio to use in dosing calculations. If more carbs are entered than allowed by this limit, Trio will cap the current COB in calculations to Max COB and remain at max until all remaining carbs have shown to be absorbed."
                        )
                        Text(
                            "For example, if Max COB is 120 g and you enter a meal containing 150 g of carbs, your COB will remain at 120 g until the remaining 30 g have been absorbed."
                        )
                        Text("This is an important limit when UAM is ON.")
                    }
                )

                SettingInputSection(
                    decimalValue: $state.threshold_setting,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Minimum Safety Threshold")
                        }
                    ),
                    units: state.units,
                    type: .decimal("threshold_setting"),
                    label: String(localized: "Minimum Safety Threshold"),
                    miniHint: String(localized: "Increase the safety threshold used to suspend insulin delivery."),
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Default: Set by Algorithm").bold()
                        Text(
                            "Minimum Threshold Setting is the hard floor for the SMB cutoff. Below this glucose value Trio will suspend insulin delivery and block SMBs. It is designed to protect against hypoglycemia, particularly during sleep or other vulnerable times."
                        )
                        Text("Combined SMB cutoff calculation:").bold()
                        Text(
                            "cutoff = clamp( max( Minimum Safety Threshold, ratioFloor ), 60, 120 ) mg/dL"
                        )
                        Text(
                            "ratioFloor = TargetGlucose − (1 − SMB Threshold Ratio) × (TargetGlucose − 40)"
                        )
                        Text(
                            "With the default ratio of 0.5 this collapses to TargetGlucose − 0.5 × (TargetGlucose − 40), i.e. the midpoint between target and 40 mg/dL. Trio always uses whichever is higher: this Minimum Safety Threshold or that ratio-derived floor."
                        )
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Example:").bold()
                            Text(
                                "If your glucose target is \(110.formatted(for: state.units)) \(state.units.rawValue) and ratio = 0.5, ratioFloor = \(75.formatted(for: state.units)) \(state.units.rawValue). Setting Minimum Safety Threshold below \(75.formatted(for: state.units)) has no effect; setting it above raises the cutoff."
                            )
                            Text(
                                "\(110.formatted(for: state.units)) − 0.5 × (\(110.formatted(for: state.units)) − \(40.formatted(for: state.units))) = \(75.formatted(for: state.units))"
                            )
                        }
                        Text(
                            "This setting is limited to values between \(60.formatted(for: state.units)) - \(120.formatted(for: state.units)) \(state.units.rawValue)."
                        )
                        Text(
                            "Note: Basal may be resumed if there is negative IOB and glucose is rising faster than the forecast."
                        )
                    }
                )

                SettingInputSection(
                    decimalValue: $state.smbThresholdRatio,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "SMB Threshold Ratio", comment: "SMB Threshold Ratio")
                        }
                    ),
                    units: state.units,
                    type: .decimal("smbThresholdRatio"),
                    label: String(localized: "SMB Threshold Ratio", comment: "SMB Threshold Ratio"),
                    miniHint: String(
                        localized: "Raises the glucose floor below which SMBs are blocked. 0.5 keeps default behaviour, 1.0 blocks SMBs until above target."
                    ),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: 0.5 — valid range (0.5, 1.0]").bold()
                        Text(
                            "A safety knob that controls how close to your low-target SMBs are still allowed. It interpolates the SMB cutoff along the line between your low-target and 40 mg/dL."
                        )
                        Text("Combined SMB cutoff calculation:").bold()
                        Text(
                            "cutoff = clamp( max( Minimum Safety Threshold, ratioFloor ), 60, 120 ) mg/dL"
                        )
                        Text(
                            "ratioFloor = TargetGlucose − (1 − ratio) × (TargetGlucose − 40)"
                        )
                        Text(
                            "Trio uses whichever is higher: the Minimum Safety Threshold above or the ratio-derived floor below. So this ratio only takes effect when ratioFloor exceeds the Minimum Safety Threshold."
                        )
                        Text("Examples (TargetGlucose = 100 mg/dL):").bold()
                        Text("• 0.5 — ratioFloor 70 mg/dL (midpoint between target and 40)")
                        Text("• 0.7 — ratioFloor 82 mg/dL (SMBs cut off sooner)")
                        Text("• 1.0 — ratioFloor 100 mg/dL (no SMBs below target)")
                        Text(
                            "Higher = more conservative. Values at or below 0.5 fall back to 0.5; values above 1.0 are ignored. The final cutoff is also clamped to 60–120 mg/dL."
                        )
                    }
                )
            }
            .listSectionSpacing(sectionSpacing)
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Units and Limits")
            .navigationBarTitleDisplayMode(.automatic)
            .settingsHighlightScroll()
            .onDisappear {
                state.saveIfChanged()
            }
        }
    }
}
