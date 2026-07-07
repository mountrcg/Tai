import Foundation
import SwiftUI

struct EditOverrideForm: View {
    var override: OverrideStored
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState
    @Bindable var state: Adjustments.StateModel

    @State private var name: String
    @State private var percentage: Double
    @State private var indefinite: Bool
    @State private var duration: Decimal
    @State private var target: Decimal?
    @State private var advancedSettings: Bool
    @State private var smbIsOff: Bool
    @State private var smbIsScheduledOff: Bool
    @State private var start: Decimal?
    @State private var end: Decimal?
    @State private var isfAndCr: Bool
    @State private var isf: Bool
    @State private var cr: Bool
    @State private var smbMinutes: Decimal?
    @State private var uamMinutes: Decimal?
    @State private var selectedIsfCrOption: IsfAndOrCrOptions
    @State private var selectedDisableSmbOption: DisableSmbOptions
    @State private var hasChanges = false
    @State private var isEditing = false
    @State private var target_override = false
    @State private var percentageStep: Int = 1
    @State private var displayPickerPercentage: Bool = false
    @State private var displayPickerDuration: Bool = false
    @State private var targetStep: Decimal = 1
    @State private var displayPickerTarget: Bool = false
    @State private var displayPickerDisableSmbSchedule: Bool = false
    @State private var displayPickerSmbMinutes: Bool = false
    @State private var showAutoISFSection = false
    @State private var showSmbSection = false
    @State private var showVariableSmbRatio = false
    // AutoISF overrides (nil = use profile default)
    @State private var aiAutoISFmin: Decimal?
    @State private var aiAutoISFmax: Decimal?
    @State private var aiAutoISFhourlyChange: Decimal?
    @State private var aiHigherISFrangeWeight: Decimal?
    @State private var aiLowerISFrangeWeight: Decimal?
    @State private var aiPostMealISFweight: Decimal?
    @State private var aiBgAccelISFweight: Decimal?
    @State private var aiBgBrakeISFweight: Decimal?
    @State private var aiIobThresholdPercent: Decimal?
    @State private var aiSmbDeliveryRatio: Decimal?
    @State private var aiSmbDeliveryRatioBGrange: Decimal?
    @State private var aiSmbDeliveryRatioMin: Decimal?
    @State private var aiSmbDeliveryRatioMax: Decimal?
    @State private var aiEnableBGacceleration: Bool?

    init(overrideToEdit: OverrideStored, state: Adjustments.StateModel) {
        override = overrideToEdit
        _state = Bindable(wrappedValue: state)
        _name = State(initialValue: overrideToEdit.name ?? "")
        _percentage = State(initialValue: overrideToEdit.percentage)
        _indefinite = State(initialValue: overrideToEdit.indefinite)
        _duration = State(initialValue: overrideToEdit.duration?.decimalValue ?? 0)
        _target = State(initialValue: overrideToEdit.target?.decimalValue)
        _target_override = State(initialValue: overrideToEdit.target != nil && overrideToEdit.target?.decimalValue != 0)
        _advancedSettings = State(initialValue: overrideToEdit.advancedSettings)
        _smbIsOff = State(initialValue: overrideToEdit.smbIsOff)
        _smbIsScheduledOff = State(initialValue: overrideToEdit.smbIsScheduledOff)
        _start = State(initialValue: overrideToEdit.start?.decimalValue)
        _end = State(initialValue: overrideToEdit.end?.decimalValue)
        _isfAndCr = State(initialValue: overrideToEdit.isfAndCr)
        _isf = State(initialValue: overrideToEdit.isf)
        _cr = State(initialValue: overrideToEdit.cr)
        _selectedIsfCrOption = State(
            initialValue: overrideToEdit.isfAndCr ? .isfAndCr
                : (overrideToEdit.isf ? .isf : (overrideToEdit.cr ? .cr : .nothing))
        )
        _selectedDisableSmbOption = State(
            initialValue: overrideToEdit.smbIsScheduledOff ? .disableOnSchedule
                : (overrideToEdit.smbIsOff ? .disable : .dontDisable)
        )
        _smbMinutes = State(initialValue: overrideToEdit.smbMinutes?.decimalValue)
        _uamMinutes = State(initialValue: overrideToEdit.uamMinutes?.decimalValue)
        _aiAutoISFmin = State(initialValue: overrideToEdit.autoISFmin?.decimalValue)
        _aiAutoISFmax = State(initialValue: overrideToEdit.autoISFmax?.decimalValue)
        _aiAutoISFhourlyChange = State(initialValue: overrideToEdit.autoISFhourlyChange?.decimalValue)
        _aiHigherISFrangeWeight = State(initialValue: overrideToEdit.higherISFrangeWeight?.decimalValue)
        _aiLowerISFrangeWeight = State(initialValue: overrideToEdit.lowerISFrangeWeight?.decimalValue)
        _aiPostMealISFweight = State(initialValue: overrideToEdit.postMealISFweight?.decimalValue)
        _aiBgAccelISFweight = State(initialValue: overrideToEdit.bgAccelISFweight?.decimalValue)
        _aiBgBrakeISFweight = State(initialValue: overrideToEdit.bgBrakeISFweight?.decimalValue)
        _aiIobThresholdPercent = State(initialValue: overrideToEdit.iobThresholdPercent?.decimalValue)
        _aiSmbDeliveryRatio = State(initialValue: overrideToEdit.smbDeliveryRatio?.decimalValue)
        _aiSmbDeliveryRatioBGrange = State(initialValue: overrideToEdit.smbDeliveryRatioBGrange?.decimalValue)
        _aiSmbDeliveryRatioMin = State(initialValue: overrideToEdit.smbDeliveryRatioMin?.decimalValue)
        _aiSmbDeliveryRatioMax = State(initialValue: overrideToEdit.smbDeliveryRatioMax?.decimalValue)
        _aiEnableBGacceleration = State(initialValue: overrideToEdit.enableBGacceleration?.boolValue)
    }

    private var percentageSelection: Binding<Double> {
        Binding<Double>(
            get: {
                let value = floor(percentage / Double(percentageStep)) * Double(percentageStep)
                return max(10, min(value, 200))
            },
            set: {
                percentage = $0
                hasChanges = true
            }
        )
    }

    var body: some View {
        NavigationView {
            List {
                editOverride()
                saveButton
            }
            .listSectionSpacing(10)
            .padding(.top, 30)
            .ignoresSafeArea(edges: .top)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Edit Override")
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
            .onDisappear {
                if !hasChanges {
                    // Reset UI changes
                    resetValues()
                }
            }
            .sheet(isPresented: $state.isHelpSheetPresented) {
                OverrideHelpView(state: state, helpSheetDetent: $state.helpSheetDetent)
            }
        }
    }

    @ViewBuilder private func editOverride() -> some View {
        Group {
            if override.name != nil {
                Section {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Name", text: $name)
                            .onChange(of: name) { hasChanges = true }
                            .multilineTextAlignment(.trailing)
                    }
                }
                .listRowBackground(Color.chart)
            }

            // Percentage Picker
            Section(footer: state.percentageDescription(percentage)) {
                HStack {
                    Text("Basal Rate Adjustment")
                    Spacer()
                    Text("\(percentage.formatted(.number)) %")
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
                                    percentage = Adjustments.StateModel.roundOverridePercentageToStep(percentage, step)
                                }
                                .padding(.top, 10)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Spacer()

                        // Picker on the right side
                        Picker(
                            selection: percentageSelection,
                            label: Text("")
                        ) {
                            ForEach(
                                Array(stride(from: 40.0, through: 150.0, by: Double(percentageStep))),
                                id: \.self
                            ) { percent in
                                Text("\(Int(percent)) %").tag(percent)
                            }
                        }
                        .pickerStyle(WheelPickerStyle())
                        .frame(maxWidth: .infinity)
                    }
                    .listRowSeparator(.hidden, edges: .top)
                }

                // Picker for ISF/CR settings
                Picker("Also Change", selection: $selectedIsfCrOption) {
                    ForEach(IsfAndOrCrOptions.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: selectedIsfCrOption) { _, newValue in
                    switch newValue {
                    case .isfAndCr:
                        isfAndCr = true
                        isf = false
                        cr = false
                    case .isf:
                        isfAndCr = false
                        isf = true
                        cr = false
                    case .cr:
                        isfAndCr = false
                        isf = false
                        cr = true
                    case .nothing:
                        isfAndCr = false
                        isf = false
                        cr = false
                    }
                    hasChanges = true
                }
            }
            .listRowBackground(Color.chart)

            Section {
                Toggle(isOn: $target_override) {
                    Text("Override Target")
                }
                .onChange(of: target_override) {
                    hasChanges = true
                }
                // Target Glucose Picker
                if target_override {
                    let settingsProvider = PickerSettingsProvider.shared
                    let glucoseSetting = PickerSetting(value: 0, step: targetStep, min: 72, max: 270, type: .glucose)

                    TargetPicker(
                        label: "Target Glucose",
                        selection: Binding(
                            get: { target ?? 100 },
                            set: { target = $0 }
                        ),
                        options: settingsProvider.generatePickerValues(
                            from: glucoseSetting,
                            units: state.units,
                            roundMinToStep: true
                        ),
                        units: state.units,
                        hasChanges: $hasChanges,
                        targetStep: $targetStep,
                        displayPickerTarget: $displayPickerTarget,
                        toggleScrollWheel: toggleScrollWheel
                    )
                    .onAppear {
                        if target == 0 || target == nil {
                            target = 100
                        }
                    }
                }
            }
            .listRowBackground(Color.chart)

            Section {
                // Picker for Disable SMB settings
                Picker("Disable SMBs", selection: $selectedDisableSmbOption) {
                    ForEach(DisableSmbOptions.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: selectedDisableSmbOption) { _, newValue in
                    switch newValue {
                    case .dontDisable:
                        smbIsOff = false
                        smbIsScheduledOff = false
                    case .disable:
                        smbIsOff = true
                        smbIsScheduledOff = false
                    case .disableOnSchedule:
                        smbIsOff = false
                        smbIsScheduledOff = true
                    }
                    hasChanges = true
                }

                if smbIsScheduledOff {
                    // First Hour SMBs Are Disabled
                    HStack {
                        Text("From")
                        Spacer()
                        Text(
                            state.is24HourFormat() ? state.format24Hour(Int(truncating: start! as NSNumber)) + ":00" :
                                state.convertTo12HourFormat(Int(truncating: start! as NSNumber))
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
                            state.is24HourFormat() ? state.format24Hour(Int(truncating: end! as NSNumber)) + ":00" :
                                state.convertTo12HourFormat(Int(truncating: end! as NSNumber))
                        )
                        .foregroundColor(!displayPickerDisableSmbSchedule ? .primary : .accentColor)
                        .onTapGesture {
                            displayPickerDisableSmbSchedule = toggleScrollWheel(displayPickerDisableSmbSchedule)
                        }
                    }

                    if displayPickerDisableSmbSchedule {
                        HStack {
                            Picker(selection: Binding(
                                get: { Int(truncating: start! as NSNumber) },
                                set: {
                                    start = Decimal($0)
                                    hasChanges = true
                                }
                            ), label: Text("")) {
                                if state.is24HourFormat() {
                                    ForEach(0 ..< 24, id: \.self) { hour in
                                        Text(state.format24Hour(hour) + ":00").tag(hour)
                                    }
                                } else {
                                    ForEach(0 ..< 24, id: \.self) { hour in
                                        Text(state.convertTo12HourFormat(hour)).tag(hour)
                                    }
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)

                            Picker(selection: Binding(
                                get: { Int(truncating: end! as NSNumber) },
                                set: {
                                    end = Decimal($0)
                                    hasChanges = true
                                }
                            ), label: Text("")) {
                                if state.is24HourFormat() {
                                    ForEach(0 ..< 24, id: \.self) { hour in
                                        Text(state.format24Hour(hour) + ":00").tag(hour)
                                    }
                                } else {
                                    ForEach(0 ..< 24, id: \.self) { hour in
                                        Text(state.convertTo12HourFormat(hour)).tag(hour)
                                    }
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

            if !smbIsOff {
                Section {
                    Toggle(isOn: $advancedSettings) {
                        Text("Change Max SMB Minutes")
                    }
                    .onChange(of: advancedSettings) { hasChanges = true }

                    if advancedSettings {
                        // SMB Minutes Picker
                        HStack {
                            Text("SMB")
                            Spacer()
                            Text("\(smbMinutes?.formatted(.number) ?? "\(state.defaultSmbMinutes)") min")
                                .foregroundColor(!displayPickerSmbMinutes ? .primary : .accentColor)
                                .onTapGesture {
                                    displayPickerSmbMinutes = toggleScrollWheel(displayPickerSmbMinutes)
                                }

                            Spacer()

                            Divider().frame(width: 1, height: 20)

                            Spacer()

                            Text("UAM")
                            Spacer()
                            Text("\(uamMinutes?.formatted(.number) ?? "\(state.defaultUamMinutes)") min")
                                .foregroundColor(!displayPickerSmbMinutes ? .primary : .accentColor)
                                .onTapGesture {
                                    displayPickerSmbMinutes = toggleScrollWheel(displayPickerSmbMinutes)
                                }
                        }

                        if displayPickerSmbMinutes {
                            HStack {
                                Picker(
                                    selection: Binding(
                                        get: { smbMinutes ?? state.defaultSmbMinutes },
                                        set: {
                                            smbMinutes = $0
                                            hasChanges = true
                                        }
                                    ),
                                    label: Text("")
                                ) {
                                    ForEach(Array(stride(from: 0, through: 180, by: 5)), id: \.self) { minute in
                                        Text("\(minute) min").tag(Decimal(minute))
                                    }
                                }
                                .pickerStyle(WheelPickerStyle())
                                .frame(maxWidth: .infinity)

                                Picker(
                                    selection: Binding(
                                        get: { uamMinutes ?? state.defaultUamMinutes },
                                        set: {
                                            uamMinutes = $0
                                            hasChanges = true
                                        }
                                    ),
                                    label: Text("")
                                ) {
                                    ForEach(Array(stride(from: 0, through: 180, by: 5)), id: \.self) { minute in
                                        Text("\(minute) min").tag(Decimal(minute))
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
                Toggle(isOn: $indefinite) { Text("Enable Indefinitely") }
                    .onChange(of: indefinite) { hasChanges = true }

                if !indefinite {
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(state.formatHoursAndMinutes(Int(truncating: duration as NSNumber)))
                            .foregroundColor(!displayPickerDuration ? .primary : .accentColor)
                            .onTapGesture {
                                displayPickerDuration = toggleScrollWheel(displayPickerDuration)
                            }
                    }

                    if displayPickerDuration {
                        HStack {
                            Picker(
                                selection: Binding(
                                    get: {
                                        Int(truncating: duration as NSNumber) / 60
                                    },
                                    set: {
                                        let minutes = Int(truncating: duration as NSNumber) % 60
                                        let totalMinutes = $0 * 60 + minutes
                                        duration = Decimal(totalMinutes)
                                        hasChanges = true
                                    }
                                ),
                                label: Text("")
                            ) {
                                ForEach(0 ..< 24) { hour in
                                    Text("\(hour) hr").tag(hour)
                                }
                            }
                            .pickerStyle(WheelPickerStyle())
                            .frame(maxWidth: .infinity)

                            Picker(
                                selection: Binding(
                                    get: {
                                        Int(truncating: duration as NSNumber) %
                                            60 // Convert Decimal to Int for modulus operation
                                    },
                                    set: {
                                        duration = Decimal((Int(truncating: duration as NSNumber) / 60) * 60 + $0)
                                        hasChanges = true
                                    }
                                ),
                                label: Text("")
                            ) {
                                ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) { minute in
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
    }

    private var saveButton: some View {
        let (isInvalid, errorMessage) = isOverrideInvalid()

        return Section(
            header:
            HStack {
                Spacer()
                Text(errorMessage ?? "").textCase(nil)
                    .foregroundColor(colorScheme == .dark ? .orange : .accentColor)
                Spacer()
            },
            content: {
                Button(action: {
                    saveChanges()

                    Task {
                        do {
                            guard let moc = override.managedObjectContext else { return }
                            guard moc.hasChanges else { return }
                            try moc.save()

                            try await state.nightscoutManager.uploadProfiles()

                            // Disable previous active Override
                            if let currentActiveOverride = state.currentActiveOverride {
                                Task {
                                    await state.disableAllActiveOverrides(
                                        except: currentActiveOverride.objectID,
                                        createOverrideRunEntry: false
                                    )
                                    // Update View
                                    state.updateLatestOverrideConfiguration()
                                }
                            }

                            hasChanges = false
                            presentationMode.wrappedValue.dismiss()
                        } catch {
                            debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to edit Override")
                        }
                    }
                }, label: {
                    Text("Save Override")
                })
                    .disabled(isInvalid) // Disable button if changes are invalid
                    .frame(maxWidth: .infinity, alignment: .center)
                    .tint(.white)
            }
        )
        .listRowBackground(isInvalid ? Color(.systemGray4) : Color(.systemBlue))
    }

    private func isOverrideInvalid() -> (Bool, String?) {
        let noDurationSpecified = !indefinite && duration == 0
        let targetZeroWithOverride = target_override && (target ?? 0 < 72 || target ?? 0 > 270)
        let allSettingsDefault = percentage == 100 && !target_override && !advancedSettings &&
            !smbIsOff && !smbIsScheduledOff

        if noDurationSpecified {
            return (
                true,
                String(
                    localized: "Enable indefinitely or set a duration.",
                    comment: "Validation error on Edit Override form when neither indefinite nor a duration is set"
                )
            )
        }

        if targetZeroWithOverride {
            return (
                true,
                String(
                    localized: "Target glucose is out of range (\(state.units == .mgdL ? "72-270" : "4-14")).",
                    comment: "Validation error on Edit Override form when target glucose is outside allowed range — interpolated value is the unit-dependent range"
                )
            )
        }

        if allSettingsDefault {
            return (
                true,
                String(
                    localized: "All settings are at default values.",
                    comment: "Validation error on Edit Override form when the override would be a no-op (all defaults)"
                )
            )
        }

        if !hasChanges {
            return (true, nil)
        }

        return (false, nil)
    }

    @ViewBuilder private func autoISFSection() -> some View {
        let profileMin = state.profileAutoISFmin
        let profileMax = state.profileAutoISFmax

        Section {
            DisclosureGroup(
                isExpanded: $showAutoISFSection,
                content: {
                    editAutoISFRow(
                        label: String(localized: "IOB Threshold %", comment: "Row label on Edit Override form — IOB Threshold %"),
                        value: Binding(
                            get: { aiIobThresholdPercent ?? state.profileIobThresholdPercent },
                            set: { aiIobThresholdPercent = $0 == state.profileIobThresholdPercent ? nil : $0
                                hasChanges = true }
                        ),
                        profileValue: state.profileIobThresholdPercent,
                        isModified: aiIobThresholdPercent != nil,
                        settingKey: "iobThresholdPercent",
                        onReset: { aiIobThresholdPercent = nil
                            hasChanges = true }
                    )
                    editAutoISFRow(
                        label: String(localized: "autoISF Min", comment: "Row label on Edit Override form — autoISF Min"),
                        value: Binding(get: { aiAutoISFmin ?? profileMin }, set: { aiAutoISFmin = $0 == profileMin ? nil : $0
                            hasChanges = true }),
                        profileValue: profileMin,
                        isModified: aiAutoISFmin != nil,
                        settingKey: "autoISFmin",
                        onReset: { aiAutoISFmin = nil
                            hasChanges = true }
                    )
                    editAutoISFRow(
                        label: String(localized: "autoISF Max", comment: "Row label on Edit Override form — autoISF Max"),
                        value: Binding(get: { aiAutoISFmax ?? profileMax }, set: { aiAutoISFmax = $0 == profileMax ? nil : $0
                            hasChanges = true }),
                        profileValue: profileMax,
                        isModified: aiAutoISFmax != nil,
                        settingKey: "autoISFmax",
                        onReset: { aiAutoISFmax = nil
                            hasChanges = true }
                    )
                    editAutoISFRow(
                        label: String(localized: "DuraISF Weight", comment: "Row label on Edit Override form — DuraISF Weight"),
                        value: Binding(
                            get: { aiAutoISFhourlyChange ?? state.profileAutoISFhourlyChange },
                            set: { aiAutoISFhourlyChange = $0 == state.profileAutoISFhourlyChange ? nil : $0
                                hasChanges = true }
                        ),
                        profileValue: state.profileAutoISFhourlyChange,
                        isModified: aiAutoISFhourlyChange != nil,
                        settingKey: "autoISFhourlyChange",
                        onReset: { aiAutoISFhourlyChange = nil
                            hasChanges = true }
                    )
                    editAutoISFRow(
                        label: String(
                            localized: "ISF Weight for Higher BGs",
                            comment: "Row label on Edit Override form — ISF Weight for Higher BGs"
                        ),
                        value: Binding(
                            get: { aiHigherISFrangeWeight ?? state.profileHigherISFrangeWeight },
                            set: { aiHigherISFrangeWeight = $0 == state.profileHigherISFrangeWeight ? nil : $0
                                hasChanges = true }
                        ),
                        profileValue: state.profileHigherISFrangeWeight,
                        isModified: aiHigherISFrangeWeight != nil,
                        settingKey: "higherISFrangeWeight",
                        onReset: { aiHigherISFrangeWeight = nil
                            hasChanges = true }
                    )
                    editAutoISFRow(
                        label: String(
                            localized: "ISF Weight for Lower BGs",
                            comment: "Row label on Edit Override form — ISF Weight for Lower BGs"
                        ),
                        value: Binding(
                            get: { aiLowerISFrangeWeight ?? state.profileLowerISFrangeWeight },
                            set: { aiLowerISFrangeWeight = $0 == state.profileLowerISFrangeWeight ? nil : $0
                                hasChanges = true }
                        ),
                        profileValue: state.profileLowerISFrangeWeight,
                        isModified: aiLowerISFrangeWeight != nil,
                        settingKey: "lowerISFrangeWeight",
                        onReset: { aiLowerISFrangeWeight = nil
                            hasChanges = true }
                    )
                    editAutoISFRow(
                        label: String(
                            localized: "ISF Weight for Postprandial BG Rise",
                            comment: "Row label on Edit Override form — ISF Weight for Postprandial BG Rise"
                        ),
                        value: Binding(
                            get: { aiPostMealISFweight ?? state.profilePostMealISFweight },
                            set: { aiPostMealISFweight = $0 == state.profilePostMealISFweight ? nil : $0
                                hasChanges = true }
                        ),
                        profileValue: state.profilePostMealISFweight,
                        isModified: aiPostMealISFweight != nil,
                        settingKey: "postMealISFweight",
                        onReset: { aiPostMealISFweight = nil
                            hasChanges = true }
                    )
                    HStack {
                        Text("Enable BG Acceleration")
                            .foregroundColor(aiEnableBGacceleration != nil ? .accentColor : .secondary)
                        Spacer()
                        if aiEnableBGacceleration != nil {
                            Button(action: { aiEnableBGacceleration = nil
                                hasChanges = true }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .imageScale(.small)
                            }
                            .buttonStyle(.plain)
                        }
                        Toggle("", isOn: Binding(
                            get: { aiEnableBGacceleration ?? state.profileEnableBGacceleration },
                            set: { newVal in
                                aiEnableBGacceleration = newVal == state.profileEnableBGacceleration ? nil : newVal
                                hasChanges = true
                            }
                        )).labelsHidden()
                    }
                    editAutoISFRow(
                        label: String(
                            localized: "ISF Weight While BG Accelerates",
                            comment: "Row label on Edit Override form — ISF Weight While BG Accelerates"
                        ),
                        value: Binding(
                            get: { aiBgAccelISFweight ?? state.profileBgAccelISFweight },
                            set: { aiBgAccelISFweight = $0 == state.profileBgAccelISFweight ? nil : $0
                                hasChanges = true }
                        ),
                        profileValue: state.profileBgAccelISFweight,
                        isModified: aiBgAccelISFweight != nil,
                        settingKey: "bgAccelISFweight",
                        onReset: { aiBgAccelISFweight = nil
                            hasChanges = true }
                    )
                    editAutoISFRow(
                        label: String(
                            localized: "ISF Weight While BG Decelerates",
                            comment: "Row label on Edit Override form — ISF Weight While BG Decelerates"
                        ),
                        value: Binding(
                            get: { aiBgBrakeISFweight ?? state.profileBgBrakeISFweight },
                            set: { aiBgBrakeISFweight = $0 == state.profileBgBrakeISFweight ? nil : $0
                                hasChanges = true }
                        ),
                        profileValue: state.profileBgBrakeISFweight,
                        isModified: aiBgBrakeISFweight != nil,
                        settingKey: "bgBrakeISFweight",
                        onReset: { aiBgBrakeISFweight = nil
                            hasChanges = true }
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

    @ViewBuilder private func smbSection() -> some View {
        Section {
            DisclosureGroup(
                isExpanded: $showSmbSection,
                content: {
                    editAutoISFRow(
                        label: String(
                            localized: "SMB Delivery Ratio",
                            comment: "Row label on Edit Override form — SMB Delivery Ratio"
                        ),
                        value: Binding(
                            get: { aiSmbDeliveryRatio ?? state.profileSmbDeliveryRatio },
                            set: { aiSmbDeliveryRatio = $0 == state.profileSmbDeliveryRatio ? nil : $0
                                hasChanges = true }
                        ),
                        profileValue: state.profileSmbDeliveryRatio,
                        isModified: aiSmbDeliveryRatio != nil,
                        settingKey: "smbDeliveryRatio",
                        onReset: { aiSmbDeliveryRatio = nil
                            hasChanges = true }
                    )

                    DisclosureGroup(
                        isExpanded: $showVariableSmbRatio,
                        content: {
                            editAutoISFRow(
                                label: String(
                                    localized: "SMB Delivery Ratio BG Range",
                                    comment: "Row label on Edit Override form — SMB Delivery Ratio BG Range"
                                ),
                                value: Binding(
                                    get: { aiSmbDeliveryRatioBGrange ?? state.profileSmbDeliveryRatioBGrange },
                                    set: { aiSmbDeliveryRatioBGrange = $0 == state.profileSmbDeliveryRatioBGrange ? nil : $0
                                        hasChanges = true }
                                ),
                                profileValue: state.profileSmbDeliveryRatioBGrange,
                                isModified: aiSmbDeliveryRatioBGrange != nil,
                                settingKey: "smbDeliveryRatioBGrange",
                                onReset: { aiSmbDeliveryRatioBGrange = nil
                                    hasChanges = true }
                            )
                            editAutoISFRow(
                                label: String(
                                    localized: "SMB Delivery Ratio Min",
                                    comment: "Row label on Edit Override form — SMB Delivery Ratio Min"
                                ),
                                value: Binding(
                                    get: { aiSmbDeliveryRatioMin ?? state.profileSmbDeliveryRatioMin },
                                    set: { aiSmbDeliveryRatioMin = $0 == state.profileSmbDeliveryRatioMin ? nil : $0
                                        hasChanges = true }
                                ),
                                profileValue: state.profileSmbDeliveryRatioMin,
                                isModified: aiSmbDeliveryRatioMin != nil,
                                settingKey: "smbDeliveryRatioMin",
                                onReset: { aiSmbDeliveryRatioMin = nil
                                    hasChanges = true }
                            )
                            editAutoISFRow(
                                label: String(
                                    localized: "SMB Delivery Ratio Max",
                                    comment: "Row label on Edit Override form — SMB Delivery Ratio Max"
                                ),
                                value: Binding(
                                    get: { aiSmbDeliveryRatioMax ?? state.profileSmbDeliveryRatioMax },
                                    set: { aiSmbDeliveryRatioMax = $0 == state.profileSmbDeliveryRatioMax ? nil : $0
                                        hasChanges = true }
                                ),
                                profileValue: state.profileSmbDeliveryRatioMax,
                                isModified: aiSmbDeliveryRatioMax != nil,
                                settingKey: "smbDeliveryRatioMax",
                                onReset: { aiSmbDeliveryRatioMax = nil
                                    hasChanges = true }
                            )
                        },
                        label: {
                            HStack {
                                Text("Variable SMB DelRatio")
                                if aiSmbDeliveryRatioBGrange != nil || aiSmbDeliveryRatioMin != nil ||
                                    aiSmbDeliveryRatioMax != nil
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

    @ViewBuilder private func editAutoISFRow(
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
        aiAutoISFmin != nil || aiAutoISFmax != nil || aiAutoISFhourlyChange != nil ||
            aiHigherISFrangeWeight != nil || aiLowerISFrangeWeight != nil || aiPostMealISFweight != nil ||
            aiBgAccelISFweight != nil || aiBgBrakeISFweight != nil || aiIobThresholdPercent != nil ||
            aiEnableBGacceleration != nil
    }

    private var hasSmbOverrides: Bool {
        aiSmbDeliveryRatio != nil || aiSmbDeliveryRatioBGrange != nil ||
            aiSmbDeliveryRatioMin != nil || aiSmbDeliveryRatioMax != nil
    }

    private func saveChanges() {
        if !override.isPreset, hasChanges, name == (override.name ?? "") {
            override.name = String(
                localized: "Custom Override",
                comment: "Default name assigned to an override when the user saves edits without providing a name"
            )
        } else {
            override.name = name
        }
        override.percentage = percentage
        override.indefinite = indefinite
        override.duration = NSDecimalNumber(decimal: duration)
        override.target = target_override ? NSDecimalNumber(decimal: target ?? 100) : nil
        override.advancedSettings = advancedSettings
        override.smbIsOff = smbIsOff
        override.smbIsScheduledOff = smbIsScheduledOff
        override.start = start.map { NSDecimalNumber(decimal: $0) }
        override.end = end.map { NSDecimalNumber(decimal: $0) }
        override.isfAndCr = isfAndCr
        override.isf = isf
        override.cr = cr
        override.smbMinutes = smbMinutes.map { NSDecimalNumber(decimal: $0) }
        override.uamMinutes = uamMinutes.map { NSDecimalNumber(decimal: $0) }
        override.autoISFmin = aiAutoISFmin.map { NSDecimalNumber(decimal: $0) }
        override.autoISFmax = aiAutoISFmax.map { NSDecimalNumber(decimal: $0) }
        override.autoISFhourlyChange = aiAutoISFhourlyChange.map { NSDecimalNumber(decimal: $0) }
        override.higherISFrangeWeight = aiHigherISFrangeWeight.map { NSDecimalNumber(decimal: $0) }
        override.lowerISFrangeWeight = aiLowerISFrangeWeight.map { NSDecimalNumber(decimal: $0) }
        override.postMealISFweight = aiPostMealISFweight.map { NSDecimalNumber(decimal: $0) }
        override.bgAccelISFweight = aiBgAccelISFweight.map { NSDecimalNumber(decimal: $0) }
        override.bgBrakeISFweight = aiBgBrakeISFweight.map { NSDecimalNumber(decimal: $0) }
        override.iobThresholdPercent = aiIobThresholdPercent.map { NSDecimalNumber(decimal: $0) }
        override.smbDeliveryRatio = aiSmbDeliveryRatio.map { NSDecimalNumber(decimal: $0) }
        override.smbDeliveryRatioBGrange = aiSmbDeliveryRatioBGrange.map { NSDecimalNumber(decimal: $0) }
        override.smbDeliveryRatioMin = aiSmbDeliveryRatioMin.map { NSDecimalNumber(decimal: $0) }
        override.smbDeliveryRatioMax = aiSmbDeliveryRatioMax.map { NSDecimalNumber(decimal: $0) }
        override.enableBGacceleration = aiEnableBGacceleration.map { NSNumber(value: $0) }
        override.isUploadedToNS = false
    }

    private func resetValues() {
        name = override.name ?? ""
        percentage = override.percentage
        indefinite = override.indefinite
        duration = override.duration?.decimalValue ?? 0
        target = override.target?.decimalValue
        advancedSettings = override.advancedSettings
        smbIsOff = override.smbIsOff
        smbIsScheduledOff = override.smbIsScheduledOff
        start = override.start?.decimalValue
        end = override.end?.decimalValue
        isfAndCr = override.isfAndCr
        isf = override.isf
        cr = override.cr
        smbMinutes = override.smbMinutes?.decimalValue ?? state.defaultSmbMinutes
        uamMinutes = override.uamMinutes?.decimalValue ?? state.defaultUamMinutes
        aiAutoISFmin = override.autoISFmin?.decimalValue
        aiAutoISFmax = override.autoISFmax?.decimalValue
        aiAutoISFhourlyChange = override.autoISFhourlyChange?.decimalValue
        aiHigherISFrangeWeight = override.higherISFrangeWeight?.decimalValue
        aiLowerISFrangeWeight = override.lowerISFrangeWeight?.decimalValue
        aiPostMealISFweight = override.postMealISFweight?.decimalValue
        aiBgAccelISFweight = override.bgAccelISFweight?.decimalValue
        aiBgBrakeISFweight = override.bgBrakeISFweight?.decimalValue
        aiIobThresholdPercent = override.iobThresholdPercent?.decimalValue
        aiSmbDeliveryRatio = override.smbDeliveryRatio?.decimalValue
        aiSmbDeliveryRatioBGrange = override.smbDeliveryRatioBGrange?.decimalValue
        aiSmbDeliveryRatioMin = override.smbDeliveryRatioMin?.decimalValue
        aiSmbDeliveryRatioMax = override.smbDeliveryRatioMax?.decimalValue
        aiEnableBGacceleration = override.enableBGacceleration?.boolValue
    }

    private func toggleScrollWheel(_ toggle: Bool) -> Bool {
        displayPickerDuration = false
        displayPickerPercentage = false
        displayPickerTarget = false
        displayPickerDisableSmbSchedule = false
        displayPickerSmbMinutes = false
        return !toggle
    }
}
