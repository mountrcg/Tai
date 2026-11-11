import SwiftUI
import Swinject

extension AutosensSettings {
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

        var autosensVerboseHint: some View {
            VStack(alignment: .leading, spacing: 15) {
                Text(
                    "Autosens automatically adjusts insulin delivery based on how sensitive or resistant you are to insulin at the time of the current loop cycle by analyzing past data to keep blood sugar levels stable."
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("How it Works").bold()
                    Text(
                        "It looks at the last 8-24 hours of data, excluding meal-related changes, and adjusts insulin settings like basal rates and targets when needed to match your sensitivity or resistance to insulin."
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("What it Adjusts").bold()
                    Text(
                        "Autosens modifies Insulin Sensitivity Factor (ISF), basal rates, and target glucose. It doesn’t account for carbs but adjusts for insulin effectiveness based on patterns in your glucose data."
                    )
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Safety").bold()
                    Text(
                        "Autosens has safety limits determined by your Autosens Max and Autosens Min settings. These settings prevent over-adjusting."
                    )
                }

                Text(
                    "Autosens functions alongside certain settings, like Super Micro Bolus (SMB). Other settings, like Dynamic ISF, alter portions of the Autosens formula. Please review the in-app hints for the Algorithm Settings prior to enabling them to understand how they may influence it."
                )
            }
        }

        var AutosensView: some View {
            Section(
                header: !state.scope.preferences
                    .useNewFormula ? Text("Autosens") : Text("Dynamic Sensitivity")
            ) {
                VStack {
                    if state.settingsManager.settings.dosingMode == .basalTesting {
                        DosingModeOverrideNote(
                            mode: .basalTesting,
                            message: String(localized: "Trio is holding sensitivity at 100% and ignoring these settings.")
                        )
                        .padding(.bottom, 8)
                    }

                    let dynamicRatio = state.determinationsFromPersistence.first?.sensitivityRatio
                    let dynamicISF = state.determinationsFromPersistence.first?.insulinSensitivity
                    let newISF = state.autosensISF
                    let decimalValue = !state.scope.preferences.useNewFormula ? state
                        .autosensRatio as NSDecimalNumber : dynamicRatio ?? 1

                    HStack {
                        Text("Sensitivity Ratio")
                        Spacer()
                        Text((decimalValue as Decimal).formatted(.upToTwoDecimalPercent))
                    }.padding(.vertical)
                    HStack {
                        Text("Calculated Sensitivity")
                        Spacer()
                        Text(
                            (!state.scope.preferences.useNewFormula ? newISF! : dynamicISF?.decimalValue ?? 0)
                                .formattedISF(for: state.units)
                        )
                        Text(state.units.rawValue + "/U").foregroundColor(.secondary)
                    }

                    HStack(alignment: .top) {
                        Text(
                            "This adjusted ISF is temporary, will change with the next loop cycle, and should not be directly used as your profile ISF value."
                        )
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(
                            action: {
                                hintLabel = String(
                                    localized: "Autosens",
                                    comment: "Hint mini-label on the Autosens settings screen when explaining the live Sensitivity Ratio"
                                )
                                selectedVerboseHint = AnyView(autosensVerboseHint)
                                shouldDisplayHint.toggle()
                            },
                            label: {
                                HStack {
                                    Image(systemName: "questionmark.circle").accessibilityLabel(Text("More information"))
                                }
                            }
                        ).buttonStyle(BorderlessButtonStyle())
                    }.padding(.top)
                }.padding(.bottom)
            }.listRowBackground(Color.chart)
        }

        var body: some View {
            List {
                if state.autosensISF != nil {
                    AutosensView
                }

                SettingInputSection(
                    decimalValue: $state.autosensMax,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.autosensMaxLabel
                        }
                    ),
                    units: state.units,
                    type: .decimal("autosensMax"),
                    label: AlgorithmSettingHints.autosensMaxLabel,
                    miniHint: AlgorithmSettingHints.autosensMaxMini,
                    verboseHint: AlgorithmSettingHints.autosensMaxVerbose(),
                    headerText: String(
                        localized: "Glucose Deviations Algorithm",
                        comment: "Section header on the Autosens settings screen grouping max/min and related controls"
                    )
                )

                SettingInputSection(
                    decimalValue: $state.autosensMin,
                    booleanValue: $booleanPlaceholder,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.autosensMinLabel
                        }
                    ),
                    units: state.units,
                    type: .decimal("autosensMin"),
                    label: AlgorithmSettingHints.autosensMinLabel,
                    miniHint: AlgorithmSettingHints.autosensMinMini,
                    verboseHint: AlgorithmSettingHints.autosensMinVerbose()
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.rewindResetsAutosens,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = AlgorithmSettingHints.rewindResetsAutosensLabel
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: AlgorithmSettingHints.rewindResetsAutosensLabel,
                    miniHint: AlgorithmSettingHints.rewindResetsAutosensMini,
                    verboseHint: AlgorithmSettingHints.rewindResetsAutosensVerbose()
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
            .navigationTitle("Autosens")
            .navigationBarTitleDisplayMode(.automatic)
            .settingsHighlightScroll()
        }
    }
}
