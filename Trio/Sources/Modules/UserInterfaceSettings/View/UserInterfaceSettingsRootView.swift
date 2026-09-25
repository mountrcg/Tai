import SwiftUI
import Swinject

extension UserInterfaceSettings {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false
        @State private var displayPickerLowThreshold: Bool = false
        @State private var displayPickerHighThreshold: Bool = false

        @AppStorage("colorSchemePreference") private var colorSchemePreference: ColorSchemeOption = .systemDefault

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var glucoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            }
            formatter.roundingMode = .halfUp
            return formatter
        }

        private var carbsFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        var body: some View {
            List {
                Section(
                    header: Text("General Appearance"),
                    content: {
                        VStack {
                            Picker(
                                selection: $colorSchemePreference,
                                label: Text("Appearance")
                            ) {
                                ForEach(ColorSchemeOption.allCases) { selection in
                                    Text(selection.displayName).tag(selection)
                                }
                            }.padding(.top)

                            HStack(alignment: .center) {
                                Text(
                                    "Choose Trio's appearance. See hint for more details."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = String(localized: "Color Scheme Preference")
                                        selectedVerboseHint =
                                            AnyView(
                                                VStack(alignment: .leading, spacing: 10) {
                                                    Text(
                                                        "Sets Trio's appearance. Descriptions of each option found below."
                                                    )
                                                    VStack(alignment: .leading, spacing: 5) {
                                                        Text("System Default:").bold()
                                                        Text("Follows the phone's current color scheme setting at that time")
                                                    }
                                                    VStack(alignment: .leading, spacing: 5) {
                                                        Text("Light:").bold()
                                                        Text("Always in Light mode")
                                                    }
                                                    VStack(alignment: .leading, spacing: 5) {
                                                        Text("Dark:").bold()
                                                        Text("Always in Dark mode")
                                                    }
                                                }
                                            )
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
                    }
                ).listRowBackground(Color.chart)
                    .settingsSearchTarget(label: String(localized: "Appearance"))

                Section {
                    VStack {
                        Picker(
                            selection: $state.glucoseColorScheme,
                            label: Text("Glucose Color Scheme")
                        ) {
                            ForEach(GlucoseColorScheme.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }.padding(.top)

                        HStack(alignment: .center) {
                            Text(
                                "Choose glucose reading color scheme. See hint for more details."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = String(localized: "Glucose Color Scheme")
                                    selectedVerboseHint =
                                        AnyView(
                                            VStack(alignment: .leading, spacing: 10) {
                                                Text(
                                                    "Set the color scheme for glucose readings on the main glucose graph, live activities, and bolus calculator. Descriptions for each option found below."
                                                )
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Dynamic (Default):").bold()
                                                    Text("Green = At Target")
                                                    Text(
                                                        "Gradient Red = As readings approach and exceed below target, they gradually become more red."
                                                    )
                                                    .fixedSize(horizontal: false, vertical: true)
                                                    Text(
                                                        "Gradient Purple = As readings approach and exceed above target, they become more purple."
                                                    )
                                                    .fixedSize(horizontal: false, vertical: true)
                                                    GlucoseColorGradientPreview(
                                                        units: state.units,
                                                        target: state.currentGlucoseTarget
                                                    )
                                                    .padding(.top, 6)
                                                }
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Static:").bold()
                                                    Text("Red = Below Range")
                                                    Text("Green = In Range")
                                                    Text("Purple = Above Range")
                                                }
                                            }
                                        )
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
                    .settingsSearchTarget(label: String(localized: "Glucose Color Scheme"))

                Section(
                    header: Text("Home View Settings"),
                    content: {
                        VStack {
                            Toggle("Show X-Axis Grid Lines", isOn: $state.xGridLines)
                            Toggle("Show Y-Axis Grid Lines", isOn: $state.yGridLines).padding(.top)
                            Toggle("Show COB-IOB Chart", isOn: $state.showCobIobChart).padding(.top)
                            Toggle("Show Glucose Peaks", isOn: $state.showGlucosePeaks).padding(.top)

                            HStack(alignment: .center) {
                                Text(
                                    "Display the grid lines behind the glucose graph."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = String(localized: "Show Main Chart X- and Y-Axis Grid Lines")
                                        selectedVerboseHint =
                                            AnyView(
                                                Text("Choose whether or not to display one or both X- and Y-Axis grid lines.")
                                            )
                                        shouldDisplayHint.toggle()
                                    },
                                    label: {
                                        HStack {
                                            Image(systemName: "questionmark.circle").accessibilityLabel(Text("More information"))
                                        }
                                    }
                                ).buttonStyle(BorderlessButtonStyle())
                            }.padding(.top)
                        }.padding(.vertical)
                    }
                ).listRowBackground(Color.chart)
                    .settingsSearchTarget(label: String(localized: "Show X-Axis Grid Lines"))

                Section {
                    VStack(alignment: .leading) {
                        Picker(
                            selection: $state.homeStatsPanelFace,
                            label: Text("Home Statistics Panel").multilineTextAlignment(.leading)
                        ) {
                            ForEach(HomeStatsPanelFace.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }.padding(.top)

                        HStack(alignment: .center) {
                            Text(
                                "Choose what the statistics panel on the home screen displays."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = String(localized: "Home Statistics Panel")
                                    selectedVerboseHint =
                                        AnyView(
                                            Text(
                                                "Choose what the statistics panel on the home screen shows by default. Tapping the panel always opens the full statistics view.\n\nTime in Range: today's time in range percentage with a glucose distribution bar.\n\nDistribution Bar Only: just the glucose distribution bar, without the percentage.\n\nToday's Averages: today's average glucose and GMI (Glucose Management Index).\n\nActive Profile: the active profile card. Temporary (expiring) profiles are always shown regardless of this setting.\n\nHide Statistics: shows no data at all, just a \"View Statistics\" shortcut."
                                            )
                                        )
                                    shouldDisplayHint.toggle()
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
                .listRowBackground(Color.chart)
                .settingsSearchTarget(label: String(localized: "Home Statistics Panel"))

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.useChartBars,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Use Bars for Bolus and Carbs")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Use Bars for Bolus and Carbs"),
                    miniHint: String(
                        localized: "Replace circles and triangles with vertical bars for bolus, SMB and carbs."
                    ),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "When enabled, boluses and SMBs are drawn as blue bars hanging down from above the glucose curve, and carbs as orange bars rising up from below."
                        )
                        Text(
                            "The bar height grows with the dose or carb amount, making it easier to spot large entries at a glance."
                        )
                        Text("External insulin keeps its rhombus marker.")
                    }
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.showCgmSensorStatus,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Show CGM Status Around Bobble")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Show CGM Status Around Bobble"),
                    miniHint: String(
                        localized: "Display sensor lifecycle arc, hourglass and status around the glucose bobble."
                    ),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text(
                            "When enabled, the glucose bobble shows CGM sensor status: a lifecycle arc during warmup and the last 48 hours before expiry, an hourglass icon tracking the sensor's remaining time, and compact status views for error states like signal loss or sensor failure."
                        )
                        Text(
                            "When disabled, the bobble only shows the glucose reading, trend arrow, and delta."
                        )
                    }
                )

                Section {
                    VStack {
                        Picker(
                            selection: $state.bolusDisplayThreshold,
                            label: Text("Bolus Label Threshold")
                        ) {
                            ForEach(BolusDisplayThreshold.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }.padding(.top)

                        HStack(alignment: .center) {
                            Text(
                                "Hide numeric labels next to small boluses and SMBs to reduce chart clutter."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = String(localized: "Bolus Label Threshold")
                                    selectedVerboseHint =
                                        AnyView(
                                            VStack(alignment: .leading, spacing: 10) {
                                                Text(
                                                    "Only boluses and SMBs at or above the selected amount will show their numeric label on the main chart. The bar or marker itself is always drawn."
                                                )
                                                Text(
                                                    "Choose 'Show all labels' to keep every label, or pick a higher threshold to clean up the chart when there are many small SMBs."
                                                )
                                            }
                                        )
                                    shouldDisplayHint.toggle()
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
                .listRowBackground(Color.chart)
                .settingsSearchTarget(label: String(localized: "Bolus Label Threshold"))

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.rulerMarks,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Show Low and High Thresholds")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Show Low and High Thresholds"),
                    miniHint: String(localized: "Display the Low and High glucose thresholds set below."),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("This setting displays the upper and lower values for your glucose target range.")
                        Text("This range is for display and statistical purposes only and does not influence insulin dosing.")
                    }
                )

                if state.rulerMarks {
                    Section {
                        VStack {
                            VStack {
                                HStack {
                                    Text("Low Threshold")

                                    Spacer()

                                    Group {
                                        Text(state.units == .mgdL ? state.low.description : state.low.asMmolL.description)
                                            .foregroundColor(!displayPickerLowThreshold ? .primary : .accentColor)

                                        Text(state.units == .mgdL ? " mg/dL" : " mmol/L").foregroundColor(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    displayPickerLowThreshold.toggle()
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text("Low Threshold"))
                                .accessibilityValue(Text(
                                    (state.units == .mgdL ? state.low.description : state.low.asMmolL.description)
                                        + " " + state.units.spokenValue
                                ))
                                .accessibilityHint(Text(
                                    displayPickerLowThreshold
                                        ? String(localized: "Closes the value picker", comment: "Accessibility hint")
                                        : String(
                                            localized: "Opens a picker to change this value",
                                            comment: "Accessibility hint"
                                        )
                                ))
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { displayPickerLowThreshold.toggle() }
                            }
                            .padding(.top)

                            if displayPickerLowThreshold {
                                let setting = PickerSettingsProvider.shared.settings.low

                                Picker(selection: $state.low, label: Text("")) {
                                    ForEach(
                                        PickerSettingsProvider.shared.generatePickerValues(from: setting, units: state.units),
                                        id: \.self
                                    ) { value in
                                        let displayValue = state.units == .mgdL ? value : value.asMmolL
                                        Text("\(displayValue.description)").tag(value)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(maxWidth: .infinity)
                            }

                            VStack {
                                HStack {
                                    Text("High Threshold")

                                    Spacer()

                                    Group {
                                        Text(state.units == .mgdL ? state.high.description : state.high.asMmolL.description)
                                            .foregroundColor(!displayPickerHighThreshold ? .primary : .accentColor)

                                        Text(state.units == .mgdL ? " mg/dL" : " mmol/L").foregroundColor(.secondary)
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    displayPickerHighThreshold.toggle()
                                }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Text("High Threshold"))
                                .accessibilityValue(Text(
                                    (state.units == .mgdL ? state.high.description : state.high.asMmolL.description)
                                        + " " + state.units.spokenValue
                                ))
                                .accessibilityHint(Text(
                                    displayPickerHighThreshold
                                        ? String(localized: "Closes the value picker", comment: "Accessibility hint")
                                        : String(
                                            localized: "Opens a picker to change this value",
                                            comment: "Accessibility hint"
                                        )
                                ))
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { displayPickerHighThreshold.toggle() }
                            }
                            .padding(.top)

                            if displayPickerHighThreshold {
                                let setting = PickerSettingsProvider.shared.settings.high
                                Picker(selection: $state.high, label: Text("")) {
                                    ForEach(
                                        PickerSettingsProvider.shared.generatePickerValues(from: setting, units: state.units),
                                        id: \.self
                                    ) { value in
                                        let displayValue = state.units == .mgdL ? value : value.asMmolL
                                        Text("\(displayValue.description)").tag(value)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(maxWidth: .infinity)
                            }

                            HStack(alignment: .center) {
                                Text(
                                    "Set low and high glucose values for the main screen, watch app, live activity, and contact image colors."
                                )
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.footnote)
                                .foregroundColor(.secondary)

                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = String(localized: "Low and High Thresholds")
                                        selectedVerboseHint =
                                            AnyView(
                                                VStack(alignment: .leading, spacing: 10) {
                                                    Text(
                                                        "Default values are based on internationally accepted Time in Range values of \(state.units == .mgdL ? "70" : 70.formattedAsMmolL)-\(state.units == .mgdL ? "180" : 180.formattedAsMmolL) \(state.units.rawValue)."
                                                    ).bold()
                                                    Text(
                                                        "These thresholds drive the chart band colors, statistics in-range buckets, Live Activity colors, and Contact Image colors."
                                                    )
                                                    Text(
                                                        "To configure when alarms fire (urgent low / low / high / forecasted low), open Glucose Alarms."
                                                    )
                                                    Text("Note: These values are not used to calculate insulin dosing.")
                                                }
                                            )

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
                        .settingsSearchTarget(label: String(localized: "Low Threshold"))
                }

                Section {
                    VStack {
                        Picker(
                            selection: $state.forecastDisplayType,
                            label: Text("Forecast Display Type")
                        ) {
                            ForEach(ForecastDisplayType.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }.padding(.top)

                        HStack(alignment: .center) {
                            Text(
                                "Choose glucose forecast presentation. See hint for more details."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = String(localized: "Forecast Display Type")
                                    selectedVerboseHint =
                                        AnyView(
                                            VStack(alignment: .leading, spacing: 10) {
                                                Text(
                                                    "This setting allows you to choose between Cone of Uncertainty (Cone) and OpenAPS Forecast Lines (Forecast Lines) for the glucose forecast. Descriptions for each option found below."
                                                )
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Cone:").bold()
                                                    Text(
                                                        "Uses a combined range of all possible forecasts from the OpenAPS lines and provides you with a range of possible forecasts. This option has shown to reduce confusion and stress around algorithm forecasts by providing a less concerning visual representation."
                                                    )
                                                }
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Text("Forecast Lines:").bold()
                                                    Text(
                                                        "Uses the IOB, COB, UAM, and ZT forecast lines from OpenAPS. This option provides a more detailed view of the algorithm's forecast, but may be more confusing for some users."
                                                    )
                                                }
                                            }
                                        )
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
                }
                .listRowBackground(Color.chart)
                .settingsSearchTarget(label: String(localized: "Forecast Display Type"))

                Section(
                    header: Text("Trio Statistics"),
                    content: {
                        VStack {
                            Picker(
                                selection: $state.eA1cDisplayUnit,
                                label: Text("eA1c/GMI Display Unit")
                            ) {
                                ForEach(EstimatedA1cDisplayUnit.allCases) { selection in
                                    Text(selection.displayName).tag(selection)
                                }
                            }.padding(.top)

                            HStack(alignment: .center) {
                                Text(
                                    "Choose to display eA1c and GMI in percent or mmol/mol."
                                )
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(nil)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Button(
                                    action: {
                                        hintLabel = String(localized: "eA1c/GMI Display Unit")
                                        selectedVerboseHint =
                                            AnyView(
                                                Text(
                                                    "Choose which format you'd prefer the eA1c (estimated A1c) and GMI (Glucose Management Index) value in the statistics view as a percentage (Example: eA1c: 6.5%) or mmol/mol (Example: eA1c: 48 mmol/mol)."
                                                )
                                            )
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
                    }
                ).listRowBackground(Color.chart)
                    .settingsSearchTarget(label: String(localized: "eA1c/GMI Display Unit"))

                Section {
                    VStack(alignment: .leading) {
                        Picker(
                            selection: $state.timeInRangeType,
                            label: Text("Time in Range Type").multilineTextAlignment(.leading)
                        ) {
                            ForEach(TimeInRangeType.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }.padding(.top)

                        HStack(alignment: .center) {
                            Text(
                                "Choose type of time in range to be used for Trio's statistics."
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button(
                                action: {
                                    hintLabel = String(localized: "Time in Range Type")
                                    selectedVerboseHint =
                                        AnyView(
                                            VStack(
                                                alignment: .leading,
                                                spacing: 10
                                            ) {
                                                Text(
                                                    "Choose which type of time in range Trio should adopt for all its statistical charts and displays:"
                                                )
                                                VStack(
                                                    alignment: .leading,
                                                    spacing: 5
                                                ) {
                                                    Text(
                                                        "Time in Tight Range (TITR):"
                                                    )
                                                    .bold()
                                                    let titrBottomThreshold =
                                                        "\(state.units == .mgdL ? Decimal(70) : 70.asMmolL)"
                                                    let titrTopThreshold =
                                                        "\(state.units == .mgdL ? Decimal(140) : 140.asMmolL)"
                                                    Text(String(
                                                        localized: "Uses the fairly established Time in Tight Range definition, which is defined as time between \(titrBottomThreshold) and \(titrTopThreshold)  \(state.units.rawValue).",
                                                        comment: "Time in Tight Range (TITR) verbose hint description"
                                                    ))
                                                }
                                                VStack(
                                                    alignment: .leading,
                                                    spacing: 5
                                                ) {
                                                    Text(
                                                        "Time in Normoglycemia (TING):"
                                                    )
                                                    .bold()
                                                    let tingBottomThreshold =
                                                        "\(state.units == .mgdL ? Decimal(63) : 63.asMmolL)"
                                                    let tingTopThreshold =
                                                        "\(state.units == .mgdL ? Decimal(140) : 140.asMmolL)"
                                                    Text(String(
                                                        localized: "Uses the very new – first discussed at ATTD 2025 in Amsterdam, NL – Time in Normoglycemia definition, which adopts its range as all values between the normoglycemic minimum threshold (\(tingBottomThreshold) \(state.units.rawValue)) and \(tingTopThreshold) \(state.units.rawValue).",
                                                        comment: "Time in Normoglycemia (TING) verbose hint description"
                                                    ))
                                                }
                                            }
                                        )
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
                }
                .listRowBackground(Color.chart)
                .settingsSearchTarget(label: String(localized: "Time in Range Type"))

                SettingInputSection(
                    decimalValue: $state.carbsRequiredThreshold,
                    booleanValue: $state.showCarbsRequiredBadge,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Show Carbs Required Badge")
                        }
                    ),
                    units: state.units,
                    type: .conditionalDecimal("carbsRequiredThreshold"),
                    label: String(localized: "Show Carbs Required Badge"),
                    conditionalLabel: String(localized: "Carbs Required Threshold"),
                    miniHint: String(localized: "Show carbs required as a red icon on the main graph icon."),
                    verboseHint: Text(
                        "Turning this on will show the grams of carbs needed to prevent a low as a notification badge on the Trio home screen located above the main icon.\n\nOnce enabled, set the Carbs Required Threshold to the lowest number of carbs you'd like to be recommended. A recommendation will not be given if carbs required is below this number.\n\nNote: The carbs suggested with this feature are to be used as a recommendation, not as a requirement. Depending on the current accuracy of your sensor and the accuracy of your settings, the suggested carbs can vary widely. Use your best judgement before injesting the suggested quanitity of carbs."
                    ),
                    headerText: String(localized: "Carbs Required Badge")
                )

                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.requireAdjustmentsConfirmation,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Require Adjustments Confirmation")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Require Adjustments Confirmation"),
                    miniHint: String(
                        localized: "If enabled, a confirmation dialog will be shown when activating adjustment presets."
                    ),
                    verboseHint: Text(
                        "Turning this on will show a confirmation dialog when you activate an Override or Temporary Target preset. This is for users who would like avoid accidentally activating a preset by mistake."
                    ),
                    headerText: String(localized: "Adjustments")
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
            .navigationBarTitle("User Interface")
            .navigationBarTitleDisplayMode(.automatic)
            .settingsHighlightScroll()
        }
    }
}

/// Illustrative bar that samples `getDynamicGlucoseColor` across the glucose range,
/// so the hint shows exactly how the dynamic scheme colors readings from low to high.
private struct GlucoseColorGradientPreview: View {
    let units: GlucoseUnits
    // User's current glucose target — the green peak of the dynamic sweep.
    let target: Decimal

    private let minGlucose: Decimal = 40
    private let maxGlucose: Decimal = 250

    // Fixed anchors the dynamic scheme uses on the glucose graph: solid red at/below,
    // solid purple at/above, sweeping red → green → purple between them.
    private let hardCodedLow: Decimal = 55
    private let hardCodedHigh: Decimal = 220

    private var markerValues: [Decimal] {
        [hardCodedLow, target, hardCodedHigh]
    }

    private var gradientStops: [Gradient.Stop] {
        let steps = 60
        return (0 ... steps).map { step in
            let location = Double(step) / Double(steps)
            let value = minGlucose + (maxGlucose - minGlucose) * Decimal(location)
            return Gradient.Stop(
                color: getDynamicGlucoseColor(
                    glucoseValue: value,
                    highGlucoseColorValue: hardCodedHigh,
                    lowGlucoseColorValue: hardCodedLow,
                    targetGlucose: target,
                    glucoseColorScheme: .dynamicColor
                ),
                location: location
            )
        }
    }

    private func fraction(of value: Decimal) -> CGFloat {
        let raw = (value - minGlucose) / (maxGlucose - minGlucose)
        return min(max(CGFloat(truncating: raw as NSNumber), 0), 1)
    }

    private func axisValue(_ value: Decimal) -> String {
        let display = units == .mgdL ? value : value.asMmolL
        return "\(display)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    gradient: Gradient(stops: gradientStops),
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .frame(height: 26)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)

            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    ForEach(markerValues, id: \.self) { value in
                        marker(value, at: fraction(of: value), width: geo.size.width)
                    }
                }
            }
            .frame(height: 22)
        }
        .accessibilityHidden(true)
    }

    private func marker(_ value: Decimal, at fraction: CGFloat, width: CGFloat) -> some View {
        VStack(spacing: 1) {
            Image(systemName: "arrowtriangle.up.fill")
                .font(.system(size: 7))
                .foregroundColor(.primary.opacity(0.55))
            Text(axisValue(value))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .fixedSize()
        .position(x: min(max(width * fraction, 12), width - 12), y: 11)
    }
}
