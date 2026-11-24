import SwiftUI
import Swinject

extension AlgorithmAdvancedSettings {
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
                    header: Text("DISCLAIMER"),
                    content: {
                        VStack(alignment: .leading) {
                            Text(
                                "The settings in this section typically do not require ANY modifications. Do not alter them without a solid understanding of what you are changing and the full impact it will have on the algorithm."
                            ).bold()
                        }
                    }

                ).listRowBackground(Color.tabBar)

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.useProfileCSF,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.useProfileCSFLabel
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: AlgorithmSettingHints.useProfileCSFLabel,
                    miniHint: AlgorithmSettingHints.useProfileCSFMini,
                    verboseHint: AlgorithmSettingHints.useProfileCSFVerbose(),
                    headerText: String(localized: "Carb Sensitivity Factor (CSF)", comment: "Header for CSF section")
                )

                SettingInputSection(
                    decimalValue: $state.maxDailySafetyMultiplier,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.maxDailySafetyMultiplierLabel
                        }
                    ),
                    units: state.units,
                    type: .decimal("maxDailySafetyMultiplier"),
                    label: AlgorithmSettingHints.maxDailySafetyMultiplierLabel,
                    miniHint: AlgorithmSettingHints.maxDailySafetyMultiplierMini,
                    verboseHint: AlgorithmSettingHints.maxDailySafetyMultiplierVerbose()
                )

                SettingInputSection(
                    decimalValue: $state.currentBasalSafetyMultiplier,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.currentBasalSafetyMultiplierLabel
                        }
                    ),
                    units: state.units,
                    type: .decimal("currentBasalSafetyMultiplier"),
                    label: AlgorithmSettingHints.currentBasalSafetyMultiplierLabel,
                    miniHint: AlgorithmSettingHints.currentBasalSafetyMultiplierMini,
                    verboseHint: AlgorithmSettingHints.currentBasalSafetyMultiplierVerbose()
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.skipNeutralTemps,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.skipNeutralTempsLabel
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: AlgorithmSettingHints.skipNeutralTempsLabel,
                    miniHint: AlgorithmSettingHints.skipNeutralTempsMini,
                    verboseHint: AlgorithmSettingHints.skipNeutralTempsVerbose()
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.unsuspendIfNoTemp,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.unsuspendIfNoTempLabel
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: AlgorithmSettingHints.unsuspendIfNoTempLabel,
                    miniHint: AlgorithmSettingHints.unsuspendIfNoTempMini,
                    verboseHint: AlgorithmSettingHints.unsuspendIfNoTempVerbose()
                )

                SettingInputSection(
                    decimalValue: $state.smbDeliveryRatio,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.smbDeliveryRatioLabel
                        }
                    ),
                    units: state.units,
                    type: .decimal("smbDeliveryRatio"),
                    label: AlgorithmSettingHints.smbDeliveryRatioLabel,
                    miniHint: AlgorithmSettingHints.smbDeliveryRatioMini,
                    verboseHint: AlgorithmSettingHints.smbDeliveryRatioVerbose()
                )

                SettingInputSection(
                    decimalValue: $state.smbInterval,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.smbIntervalLabel
                        }
                    ),
                    units: state.units,
                    type: .decimal("smbInterval"),
                    label: AlgorithmSettingHints.smbIntervalLabel,
                    miniHint: AlgorithmSettingHints.smbIntervalMini,
                    verboseHint: AlgorithmSettingHints.smbIntervalVerbose()
                )

                SettingInputSection(
                    decimalValue: $state.min5mCarbimpact,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.min5mCarbimpactLabel
                        }
                    ),
                    units: state.units,
                    type: .decimal("min5mCarbimpact"),
                    label: AlgorithmSettingHints.min5mCarbimpactLabel,
                    miniHint: AlgorithmSettingHints.min5mCarbimpactMini,
                    verboseHint: AlgorithmSettingHints.min5mCarbimpactVerbose(units: state.units)
                )

                SettingInputSection(
                    decimalValue: $state.remainingCarbsFraction,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.remainingCarbsFractionLabel
                        }
                    ),
                    units: state.units,
                    type: .decimal("remainingCarbsFraction"),
                    label: AlgorithmSettingHints.remainingCarbsFractionLabel,
                    miniHint: AlgorithmSettingHints.remainingCarbsFractionMini,
                    verboseHint: AlgorithmSettingHints.remainingCarbsFractionVerbose()
                )

                SettingInputSection(
                    decimalValue: $state.remainingCarbsCap,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.remainingCarbsCapLabel
                        }
                    ),
                    units: state.units,
                    type: .decimal("remainingCarbsCap"),
                    label: AlgorithmSettingHints.remainingCarbsCapLabel,
                    miniHint: AlgorithmSettingHints.remainingCarbsCapMini,
                    verboseHint: AlgorithmSettingHints.remainingCarbsCapVerbose()
                )

                SettingInputSection(
                    decimalValue: $state.noisyCGMTargetMultiplier,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.noisyCGMTargetMultiplierHintLabel
                        }
                    ),
                    units: state.units,
                    type: .decimal("noisyCGMTargetMultiplier"),
                    label: AlgorithmSettingHints.noisyCGMTargetMultiplierLabel,
                    miniHint: AlgorithmSettingHints.noisyCGMTargetMultiplierMini,
                    verboseHint: AlgorithmSettingHints.noisyCGMTargetMultiplierVerbose()
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
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Additionals")
            .navigationBarTitleDisplayMode(.automatic)
            .settingsHighlightScroll()
        }
    }
}
