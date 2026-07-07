import Foundation
import SwiftUI

struct AddOverrideForm: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @Environment(AppState.self) var appState
    @Bindable var state: Adjustments.StateModel
    @State private var selectedIsfCrOption: IsfAndOrCrOptions = .isfAndCr
    @State private var selectedDisableSmbOption: DisableSmbOptions = .dontDisable
    @State private var percentageStep: Int = 5
    @State private var displayPickerPercentage: Bool = false
    @State private var displayPickerDuration: Bool = false
    @State private var targetStep: Decimal = 5
    @State private var displayPickerTarget: Bool = false
    @State private var displayPickerDisableSmbSchedule: Bool = false
    @State private var displayPickerSmbMinutes: Bool = false
    @State private var durationHours = 0
    @State private var durationMinutes = 0
    @State private var overrideTarget = false
    @State private var didPressSave = false
    @State private var showAutoISFSection = false
    @State private var showSmbSection = false
    @State private var showVariableSmbRatio = false

    var body: some View {
        NavigationView {
            List {
                addOverride()
                saveButton
            }
            .listSectionSpacing(10)
            .padding(.top, 30)
            .ignoresSafeArea(edges: .top)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Add Override")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }, label: {
                        Text("Cancel")
                    })
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        action: {
                            state.isHelpSheetPresented.toggle()
                        },
                        label: {
                            Image(systemName: "questionmark.circle")
                        }
                    )
                }
            }
            .onAppear { targetStep = state.units == .mgdL ? 5 : 9 }
            .sheet(isPresented: $state.isHelpSheetPresented) {
                OverrideHelpView(state: state, helpSheetDetent: $state.helpSheetDetent)
            }
        }
    }

    @ViewBuilder private func addOverride() -> some View {
        Group {
            Section {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("(Optional)", text: $state.overrideName).multilineTextAlignment(.trailing)
                }
            }
            .listRowBackground(Color.chart)

            Section(footer: state.percentageDescription(state.overridePercentage)) {
                // Percentage Picker
                HStack {
                    Text("Basal Rate Adjustment")
                    Spacer()
                    Text("\(state.overridePercentage.formatted(.number)) %")
                        .foregroundColor(!displayPickerPercentage ? .primary : .accentColor)
                        .onTapGesture {
                            displayPickerPercentage = toggleScrollWheel(displayPickerPercentage)
                        }
                }

                if displayPickerPercentage {
                    HStack {
                        // Radio buttons and text on the left side
                        VStack(alignment: .leading) {
                            // Radio buttons for step iteration
                            ForEach([1, 5], id: \.self) { step in
                                RadioButton(isSelected: percentageStep == step, label: "\(step) %") {
                                    percentageStep = step
                                    state.overridePercentage = Adjustments.StateModel.roundOverridePercentageToStep(
                                        state.overridePercentage,
                                        step
                                    )
                                }
                                .padding(.top, 10)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Spacer()

                        // Picker on the right side
                        Picker(
                            selection: Binding(
                                get: { Int(truncating: state.overridePercentage as NSNumber) },
                                set: { state.overridePercentage = Double($0) }
                            ), label: Text("")
                        ) {
                            ForEach(Array(stride(from: 40, through: 150, by: percentageStep)), id: \.self) { percent in
                                Text("\(percent) %").tag(percent)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden, edges: .top)
                }

                // Picker for ISF/CR settings
                Picker("Also Inversely Change", selection: $selectedIsfCrOption) {
                    ForEach(IsfAndOrCrOptions.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: selectedIsfCrOption) { _, newValue in
                    switch newValue {
                    case .isfAndCr:
                        state.isfAndCr = true
                        state.isf = true
                        state.cr = true
                    case .isf:
                        state.isfAndCr = false
                        state.isf = true
                        state.cr = false
                    case .cr:
                        state.isfAndCr = false
                        state.isf = false
                        state.cr = true
                    case .nothing:
                        state.isfAndCr = false
                        state.isf = false
                        state.cr = false
                    }
                }
            }
            .listRowBackground(Color.chart)

            Section {
                Toggle(isOn: $state.shouldOverrideTarget) {
                    Text("Override Target")
                }

                if state.shouldOverrideTarget {
                    let settingsProvider = PickerSettingsProvider.shared
                    let glucoseSetting = PickerSetting(value: 0, step: targetStep, min: 72, max: 270, type: .glucose)
                    TargetPicker(
                        label: "Target Glucose",
                        selection: Binding(
                            get: { state.target },
                            set: { state.target = $0 }
                        ),
                        options: settingsProvider.generatePickerValues(
                            from: glucoseSetting,
                            units: state.units,
                            roundMinToStep: true
                        ),
                        units: state.units,
                        targetStep: $targetStep,
                        displayPickerTarget: $displayPickerTarget,
                        toggleScrollWheel: toggleScrollWheel
                    )
                    .onAppear {
                        if state.target == 0 {
                            state.target = 100
                        }
                    }
                }
            }
            .listRowBackground(Color.chart)

            Section {
                // Picker for ISF/CR settings
                Picker("Disable SMBs", selection: $selectedDisableSmbOption) {
                    ForEach(DisableSmbOptions.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: selectedDisableSmbOption) { _, newValue in
                    switch newValue {
                    case .dontDisable:
                        state.smbIsOff = false
                        state.smbIsScheduledOff = false
                    case .disable:
                        state.smbIsOff = true
                        state.smbIsScheduledOff = false
                    case .disableOnSchedule:
                        state.smbIsOff = false
                        state.smbIsScheduledOff = true
                    }
                }

                if state.smbIsScheduledOff {
                    // First Hour SMBs Are Disabled
                    HStack {
                        Text("From")
                        Spacer()
                        Text(
                            state.is24HourFormat() ? state.format24Hour(Int(truncating: state.start as NSNumber)) + ":00" :
                                state.convertTo12HourFormat(Int(truncating: state.start as NSNumber))
                        )
                        .foregroundColor(!displayPickerDisableSmbSchedule ? .primary : .accentColor)
                        .onTapGesture {
                            displayPickerDisableSmbSchedule = toggleScrollWheel(displayPickerDisableSmbSchedule)
                        }
                        Spacer()
                        Divider().frame(width: 1, height: 20)
                        Spacer()
                        Text("To")
                        Spacer()
                        Text(
                            state.is24HourFormat() ? state.format24Hour(Int(truncating: state.end as NSNumber)) + ":00" :
                                state.convertTo12HourFormat(Int(truncating: state.end as NSNumber))
                        )
                        .foregroundColor(!displayPickerDisableSmbSchedule ? .primary : .accentColor)
                        .onTapGesture {
                            displayPickerDisableSmbSchedule = toggleScrollWheel(displayPickerDisableSmbSchedule)
                        }
                        Spacer()
                    }

                    if displayPickerDisableSmbSchedule {
                        HStack {
                            // From Picker
                            Picker(selection: Binding(
                                get: { Int(truncating: state.start as NSNumber) },
                                set: { state.start = Decimal($0) }
                            ), label: Text("")) {
                                ForEach(0 ..< 24, id: \.self) { hour in
                                    Text(
                                        state.is24HourFormat() ? state.format24Hour(hour) + ":00" : state
                                            .convertTo12HourFormat(hour)
                                    )
                                    .tag(hour)
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)

                            // To Picker
                            Picker(selection: Binding(
                                get: { Int(truncating: state.end as NSNumber) },
                                set: { state.end = Decimal($0) }
                            ), label: Text("")) {
                                ForEach(0 ..< 24, id: \.self) { hour in
                                    Text(
                                        state.is24HourFormat() ? state.format24Hour(hour) + ":00" : state
                                            .convertTo12HourFormat(hour)
                                    )
                                    .tag(hour)
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)
                        }
                        .listRowSeparator(.hidden, edges: .top)
                    }
                }
            }
            .listRowBackground(Color.chart)

            if !state.smbIsOff {
                Section {
                    Toggle(isOn: $state.advancedSettings) {
                        Text("Override Max SMB Minutes")
                    }

                    if state.advancedSettings {
                        // SMB Minutes Picker
                        HStack {
                            Text("SMB")
                            Spacer()
                            Text("\(state.smbMinutes.formatted(.number)) min")
                                .foregroundColor(!displayPickerSmbMinutes ? .primary : .accentColor)
                                .onTapGesture {
                                    displayPickerSmbMinutes = toggleScrollWheel(displayPickerSmbMinutes)
                                }
                            Spacer()
                            Divider().frame(width: 1, height: 20)
                            Spacer()
                            Text("UAM")
                            Spacer()
                            Text("\(state.uamMinutes.formatted(.number)) min")
                                .foregroundColor(!displayPickerSmbMinutes ? .primary : .accentColor)
                                .onTapGesture {
                                    displayPickerSmbMinutes = toggleScrollWheel(displayPickerSmbMinutes)
                                }
                        }

                        if displayPickerSmbMinutes {
                            HStack {
                                Picker(selection: Binding(
                                    get: { Int(truncating: state.smbMinutes as NSNumber) },
                                    set: { state.smbMinutes = Decimal($0) }
                                ), label: Text("")) {
                                    ForEach(Array(stride(from: 0, through: 180, by: 5)), id: \.self) { minute in
                                        Text("\(minute) min").tag(minute)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(maxWidth: .infinity)

                                Picker(selection: Binding(
                                    get: { Int(truncating: state.uamMinutes as NSNumber) },
                                    set: { state.uamMinutes = Decimal($0) }
                                ), label: Text("")) {
                                    ForEach(Array(stride(from: 0, through: 180, by: 5)), id: \.self) { minute in
                                        Text("\(minute) min").tag(minute)
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(maxWidth: .infinity)
                            }
                            .listRowSeparator(.hidden, edges: .top)
                        }
                    }
                }
                .listRowBackground(Color.chart)
            }

            if state.useAutoISF {
                autoISFSection()
                smbSection()
            }

            Section {
                Toggle(isOn: $state.indefinite) {
                    Text("Enable Indefinitely")
                }

                if !state.indefinite {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(state.formatHoursAndMinutes(Int(state.overrideDuration)))
                            .foregroundColor(!displayPickerDuration ? .primary : .accentColor)
                            .onTapGesture {
                                displayPickerDuration = toggleScrollWheel(displayPickerDuration)
                            }
                    }

                    if displayPickerDuration {
                        HStack {
                            Picker("Hours", selection: $durationHours) {
                                ForEach(0 ..< 24) { hour in
                                    Text("\(hour) hr").tag(hour)
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)
                            .onChange(of: durationHours) {
                                state.overrideDuration = state.convertToMinutes(durationHours, durationMinutes)
                            }

                            Picker("Minutes", selection: $durationMinutes) {
                                ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { minute in
                                    Text("\(minute) min").tag(minute)
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)
                            .onChange(of: durationMinutes) {
                                state.overrideDuration = state.convertToMinutes(durationHours, durationMinutes)
                            }
                        }
                        .listRowSeparator(.hidden, edges: .top)
                    }
                }
            }
            .listRowBackground(Color.chart)
        }
    }

    @ViewBuilder private func autoISFSection() -> some View {
        Section {
            DisclosureGroup(
                isExpanded: $showAutoISFSection,
                content: {
                    autoISFRow(
                        label: String(localized: "IOB Threshold %", comment: "Row label on Add Override form — IOB Threshold %"),
                        value: Binding(
                            get: { state.overrideIobThresholdPercent ?? state.profileIobThresholdPercent },
                            set: { state.overrideIobThresholdPercent = $0 == state.profileIobThresholdPercent ? nil : $0 }
                        ),
                        profileValue: state.profileIobThresholdPercent,
                        isModified: state.overrideIobThresholdPercent != nil,
                        settingKey: "iobThresholdPercent",
                        onReset: { state.overrideIobThresholdPercent = nil }
                    )
                    autoISFRow(
                        label: String(localized: "autoISF Min", comment: "Row label on Add Override form — autoISF Min"),
                        value: Binding(
                            get: { state.overrideAutoISFmin ?? state.profileAutoISFmin },
                            set: { state.overrideAutoISFmin = $0 == state.profileAutoISFmin ? nil : $0 }
                        ),
                        profileValue: state.profileAutoISFmin,
                        isModified: state.overrideAutoISFmin != nil,
                        settingKey: "autoISFmin",
                        onReset: { state.overrideAutoISFmin = nil }
                    )
                    autoISFRow(
                        label: String(localized: "autoISF Max", comment: "Row label on Add Override form — autoISF Max"),
                        value: Binding(
                            get: { state.overrideAutoISFmax ?? state.profileAutoISFmax },
                            set: { state.overrideAutoISFmax = $0 == state.profileAutoISFmax ? nil : $0 }
                        ),
                        profileValue: state.profileAutoISFmax,
                        isModified: state.overrideAutoISFmax != nil,
                        settingKey: "autoISFmax",
                        onReset: { state.overrideAutoISFmax = nil }
                    )
                    autoISFRow(
                        label: String(localized: "DuraISF Weight", comment: "Row label on Add Override form — DuraISF Weight"),
                        value: Binding(
                            get: { state.overrideAutoISFhourlyChange ?? state.profileAutoISFhourlyChange },
                            set: { state.overrideAutoISFhourlyChange = $0 == state.profileAutoISFhourlyChange ? nil : $0 }
                        ),
                        profileValue: state.profileAutoISFhourlyChange,
                        isModified: state.overrideAutoISFhourlyChange != nil,
                        settingKey: "autoISFhourlyChange",
                        onReset: { state.overrideAutoISFhourlyChange = nil }
                    )
                    autoISFRow(
                        label: String(
                            localized: "ISF Weight for Higher BGs",
                            comment: "Row label on Add Override form — ISF Weight for Higher BGs"
                        ),
                        value: Binding(
                            get: { state.overrideHigherISFrangeWeight ?? state.profileHigherISFrangeWeight },
                            set: { state.overrideHigherISFrangeWeight = $0 == state.profileHigherISFrangeWeight ? nil : $0 }
                        ),
                        profileValue: state.profileHigherISFrangeWeight,
                        isModified: state.overrideHigherISFrangeWeight != nil,
                        settingKey: "higherISFrangeWeight",
                        onReset: { state.overrideHigherISFrangeWeight = nil }
                    )
                    autoISFRow(
                        label: String(
                            localized: "ISF Weight for Lower BGs",
                            comment: "Row label on Add Override form — ISF Weight for Lower BGs"
                        ),
                        value: Binding(
                            get: { state.overrideLowerISFrangeWeight ?? state.profileLowerISFrangeWeight },
                            set: { state.overrideLowerISFrangeWeight = $0 == state.profileLowerISFrangeWeight ? nil : $0 }
                        ),
                        profileValue: state.profileLowerISFrangeWeight,
                        isModified: state.overrideLowerISFrangeWeight != nil,
                        settingKey: "lowerISFrangeWeight",
                        onReset: { state.overrideLowerISFrangeWeight = nil }
                    )
                    autoISFRow(
                        label: String(
                            localized: "ISF Weight for Postprandial BG Rise",
                            comment: "Row label on Add Override form — ISF Weight for Postprandial BG Rise"
                        ),
                        value: Binding(
                            get: { state.overridePostMealISFweight ?? state.profilePostMealISFweight },
                            set: { state.overridePostMealISFweight = $0 == state.profilePostMealISFweight ? nil : $0 }
                        ),
                        profileValue: state.profilePostMealISFweight,
                        isModified: state.overridePostMealISFweight != nil,
                        settingKey: "postMealISFweight",
                        onReset: { state.overridePostMealISFweight = nil }
                    )
                    HStack {
                        Text("Enable BG Acceleration")
                            .foregroundColor(state.overrideEnableBGacceleration != nil ? .accentColor : .secondary)
                        Spacer()
                        if state.overrideEnableBGacceleration != nil {
                            Button(action: { state.overrideEnableBGacceleration = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .imageScale(.small)
                            }
                            .buttonStyle(.plain)
                        }
                        Toggle(
                            "",
                            isOn: Binding(
                                get: { state.overrideEnableBGacceleration ?? state.profileEnableBGacceleration },
                                set: { newVal in
                                    state.overrideEnableBGacceleration = newVal == state
                                        .profileEnableBGacceleration ? nil : newVal
                                }
                            )
                        )
                        .labelsHidden()
                    }
                    autoISFRow(
                        label: String(
                            localized: "ISF Weight While BG Accelerates",
                            comment: "Row label on Add Override form — ISF Weight While BG Accelerates"
                        ),
                        value: Binding(
                            get: { state.overrideBgAccelISFweight ?? state.profileBgAccelISFweight },
                            set: { state.overrideBgAccelISFweight = $0 == state.profileBgAccelISFweight ? nil : $0 }
                        ),
                        profileValue: state.profileBgAccelISFweight,
                        isModified: state.overrideBgAccelISFweight != nil,
                        settingKey: "bgAccelISFweight",
                        onReset: { state.overrideBgAccelISFweight = nil }
                    )
                    autoISFRow(
                        label: String(
                            localized: "ISF Weight While BG Decelerates",
                            comment: "Row label on Add Override form — ISF Weight While BG Decelerates"
                        ),
                        value: Binding(
                            get: { state.overrideBgBrakeISFweight ?? state.profileBgBrakeISFweight },
                            set: { state.overrideBgBrakeISFweight = $0 == state.profileBgBrakeISFweight ? nil : $0 }
                        ),
                        profileValue: state.profileBgBrakeISFweight,
                        isModified: state.overrideBgBrakeISFweight != nil,
                        settingKey: "bgBrakeISFweight",
                        onReset: { state.overrideBgBrakeISFweight = nil }
                    )
                },
                label: {
                    HStack {
                        Text("AutoISF Settings")
                        if hasAutoISFOverrides {
                            Spacer()
                            Text("Modified")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            )
        }
        .listRowBackground(Color.chart)
    }

    @ViewBuilder private func autoISFRow(
        label: String,
        value: Binding<Decimal>,
        profileValue _: Decimal,
        isModified: Bool,
        settingKey: String,
        onReset: @escaping () -> Void = {}
    ) -> some View {
        OverrideAutoISFRow(
            label: label,
            value: value,
            isModified: isModified,
            settingKey: settingKey,
            units: state.units,
            onReset: onReset
        )
    }

    private var hasAutoISFOverrides: Bool {
        state.overrideAutoISFmin != nil ||
            state.overrideAutoISFmax != nil ||
            state.overrideAutoISFhourlyChange != nil ||
            state.overrideHigherISFrangeWeight != nil ||
            state.overrideLowerISFrangeWeight != nil ||
            state.overridePostMealISFweight != nil ||
            state.overrideBgAccelISFweight != nil ||
            state.overrideBgBrakeISFweight != nil ||
            state.overrideIobThresholdPercent != nil ||
            state.overrideEnableBGacceleration != nil
    }

    private var hasSmbOverrides: Bool {
        state.overrideSmbDeliveryRatio != nil ||
            state.overrideSmbDeliveryRatioBGrange != nil ||
            state.overrideSmbDeliveryRatioMin != nil ||
            state.overrideSmbDeliveryRatioMax != nil
    }

    @ViewBuilder private func smbSection() -> some View {
        Section {
            DisclosureGroup(
                isExpanded: $showSmbSection,
                content: {
                    autoISFRow(
                        label: String(
                            localized: "SMB Delivery Ratio",
                            comment: "Row label on Add Override form — SMB Delivery Ratio"
                        ),
                        value: Binding(
                            get: { state.overrideSmbDeliveryRatio ?? state.profileSmbDeliveryRatio },
                            set: { state.overrideSmbDeliveryRatio = $0 == state.profileSmbDeliveryRatio ? nil : $0 }
                        ),
                        profileValue: state.profileSmbDeliveryRatio,
                        isModified: state.overrideSmbDeliveryRatio != nil,
                        settingKey: "smbDeliveryRatio",
                        onReset: { state.overrideSmbDeliveryRatio = nil }
                    )

                    DisclosureGroup(
                        isExpanded: $showVariableSmbRatio,
                        content: {
                            autoISFRow(
                                label: String(
                                    localized: "SMB Delivery Ratio BG Range",
                                    comment: "Row label on Add Override form — SMB Delivery Ratio BG Range"
                                ),
                                value: Binding(
                                    get: { state.overrideSmbDeliveryRatioBGrange ?? state.profileSmbDeliveryRatioBGrange },
                                    set: {
                                        state.overrideSmbDeliveryRatioBGrange = $0 == state
                                            .profileSmbDeliveryRatioBGrange ? nil : $0
                                    }
                                ),
                                profileValue: state.profileSmbDeliveryRatioBGrange,
                                isModified: state.overrideSmbDeliveryRatioBGrange != nil,
                                settingKey: "smbDeliveryRatioBGrange",
                                onReset: { state.overrideSmbDeliveryRatioBGrange = nil }
                            )
                            autoISFRow(
                                label: String(
                                    localized: "SMB Delivery Ratio Min",
                                    comment: "Row label on Add Override form — SMB Delivery Ratio Min"
                                ),
                                value: Binding(
                                    get: { state.overrideSmbDeliveryRatioMin ?? state.profileSmbDeliveryRatioMin },
                                    set: {
                                        state.overrideSmbDeliveryRatioMin = $0 == state.profileSmbDeliveryRatioMin ? nil : $0
                                    }
                                ),
                                profileValue: state.profileSmbDeliveryRatioMin,
                                isModified: state.overrideSmbDeliveryRatioMin != nil,
                                settingKey: "smbDeliveryRatioMin",
                                onReset: { state.overrideSmbDeliveryRatioMin = nil }
                            )
                            autoISFRow(
                                label: String(
                                    localized: "SMB Delivery Ratio Max",
                                    comment: "Row label on Add Override form — SMB Delivery Ratio Max"
                                ),
                                value: Binding(
                                    get: { state.overrideSmbDeliveryRatioMax ?? state.profileSmbDeliveryRatioMax },
                                    set: {
                                        state.overrideSmbDeliveryRatioMax = $0 == state.profileSmbDeliveryRatioMax ? nil : $0
                                    }
                                ),
                                profileValue: state.profileSmbDeliveryRatioMax,
                                isModified: state.overrideSmbDeliveryRatioMax != nil,
                                settingKey: "smbDeliveryRatioMax",
                                onReset: { state.overrideSmbDeliveryRatioMax = nil }
                            )
                        },
                        label: {
                            HStack {
                                Text("Variable SMB DelRatio")
                                if state.overrideSmbDeliveryRatioBGrange != nil ||
                                    state.overrideSmbDeliveryRatioMin != nil ||
                                    state.overrideSmbDeliveryRatioMax != nil
                                {
                                    Spacer()
                                    Text("Modified")
                                        .font(.caption)
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    )
                },
                label: {
                    HStack {
                        Text("SMB Settings")
                        if hasSmbOverrides {
                            Spacer()
                            Text("Modified")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                }
            )
        }
        .listRowBackground(Color.chart)
    }

    private var saveButton: some View {
        let (isInvalid, errorMessage) = isOverrideInvalid()

        return Group {
            Section(
                header:
                HStack {
                    Spacer()
                    Text(errorMessage ?? "").textCase(nil)
                        .foregroundColor(colorScheme == .dark ? .orange : .accentColor)
                    Spacer()
                },
                content: {
                    Button(action: {
                        Task {
                            if state.indefinite { state.overrideDuration = 0 }
                            state.isOverrideEnabled.toggle()
                            await state.saveCustomOverride()
                            await state.resetStateVariables()
                            dismiss()
                        }
                    }, label: {
                        Text("Start Override")
                    })
                        .disabled(isInvalid)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .tint(.white)
                }
            ).listRowBackground(isInvalid ? Color(.systemGray4) : Color(.systemBlue))

            Section {
                Button(action: {
                    Task {
                        await state.saveOverridePreset()
                        dismiss()
                    }
                }, label: {
                    Text("Save as Preset")

                })
                    .disabled(isInvalid)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .tint(.white)
            }
            .listRowBackground(
                isInvalid ? Color(.systemGray4) : Color.secondary
            )
        }
    }

    private func toggleScrollWheel(_ toggle: Bool) -> Bool {
        displayPickerDuration = false
        displayPickerPercentage = false
        displayPickerTarget = false
        displayPickerDisableSmbSchedule = false
        displayPickerSmbMinutes = false
        return !toggle
    }

    private func isOverrideInvalid() -> (Bool, String?) {
        let noDurationSpecified = !state.indefinite && state.overrideDuration == 0
        let targetZeroWithOverride = state.shouldOverrideTarget && state.target == 0
        let allSettingsDefault = state.overridePercentage == 100 && !state.shouldOverrideTarget &&
            !state.advancedSettings && !state.smbIsOff && !state.smbIsScheduledOff && !hasAutoISFOverrides &&
            !hasSmbOverrides

        if noDurationSpecified {
            return (
                true,
                String(
                    localized: "Enable indefinitely or set a duration.",
                    comment: "Validation error on Add Override form when neither indefinite nor a duration is set"
                )
            )
        }

        if targetZeroWithOverride {
            return (
                true,
                String(
                    localized: "Target glucose is out of range (\(state.units == .mgdL ? "72-270" : "4-14")).",
                    comment: "Validation error on Add Override form when target glucose is outside allowed range — interpolated value is the unit-dependent range"
                )
            )
        }

        if allSettingsDefault {
            return (
                true,
                String(
                    localized: "All settings are at default values.",
                    comment: "Validation error on Add Override form when the override would be a no-op (all defaults)"
                )
            )
        }

        return (false, nil)
    }
}

/// Row used by the override forms for AutoISF / SMB numeric overrides. Mirrors
/// the tap-to-expand wheel-picker UX from `SettingInputSection`, sourcing
/// bounds, step and value formatting from `DecimalPickerSettings`. Adds the
/// override-form reset button + accent-color modification indicator.
struct OverrideAutoISFRow: View {
    let label: String
    @Binding var value: Decimal
    let isModified: Bool
    let settingKey: String
    let units: GlucoseUnits
    var onReset: () -> Void = {}

    @ObservedObject private var pickerSettingsProvider = PickerSettingsProvider.shared
    @State private var displayPicker: Bool = false

    var body: some View {
        if let setting = pickerSettingsProvider.pickerSetting(for: settingKey) {
            VStack {
                HStack {
                    Text(label)
                        .foregroundColor(isModified ? .accentColor : .primary)
                    Spacer()
                    if isModified {
                        Button(action: onReset) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .imageScale(.small)
                        }
                        .buttonStyle(.plain)
                    }
                    setting.displayText(for: value, units: units)
                        .foregroundColor(displayPicker ? .accentColor : .primary)
                        .onTapGesture { displayPicker.toggle() }
                }
                if displayPicker {
                    Picker(selection: $value, label: Text(label)) {
                        ForEach(pickerSettingsProvider.generatePickerValues(from: setting, units: units), id: \.self) { v in
                            setting.displayText(for: v, units: units).tag(v)
                        }
                    }
                    .pickerStyle(WheelPickerStyle())
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
