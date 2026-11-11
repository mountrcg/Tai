import SwiftUI

struct SettingInputSection<VerboseHint: View>: View {
    enum SettingInputSectionType: Equatable {
        case decimal(String)
        case boolean
        case conditionalDecimal(String)

        static func == (lhs: SettingInputSectionType, rhs: SettingInputSectionType) -> Bool {
            switch (lhs, rhs) {
            case (.boolean, .boolean):
                return true
            case let (.decimal(lhsValue), .decimal(rhsValue)):
                return lhsValue == rhsValue
            case let (.conditionalDecimal(lhsValue), .conditionalDecimal(rhsValue)):
                return lhsValue == rhsValue
            default:
                return false
            }
        }
    }

    @Binding var decimalValue: Decimal
    @Binding var booleanValue: Bool
    @Binding var shouldDisplayHint: Bool
    @Binding var selectedVerboseHint: (any View)?

    var units: GlucoseUnits
    var type: SettingInputSectionType
    var label: String
    var conditionalLabel: String?
    var miniHint: String
    var verboseHint: VerboseHint
    var headerText: String?
    var footerText: String?
    var isToggleDisabled: Bool = false
    var miniHintColor: Color = .secondary
    /// When `true`, the label text is tinted with the accent color. Used by the profile draft
    /// editor to mark values that differ from the source profile.
    var isChanged: Bool = false
    /// When non-nil AND `isChanged` is true, a small circle-x button is shown next to the value
    /// that invokes this closure to reset the field to its source value.
    var onReset: (() -> Void)? = nil

    @ObservedObject private var pickerSettingsProvider = PickerSettingsProvider.shared
    @State private var displayPicker: Bool = false
    @State private var displayConditionalPicker: Bool = false

    var body: some View {
        Section(
            content: {
                VStack {
                    switch type {
                    case let .decimal(key):
                        if let setting = getPickerSetting(for: key) {
                            pickerView(
                                label: label,
                                displayPicker: $displayPicker,
                                setting: setting,
                                decimalValue: $decimalValue
                            )
                        }

                    case .boolean:
                        toggleView(label: label, isOn: $booleanValue)
                            .disabled(isToggleDisabled)

                    case let .conditionalDecimal(key):
                        VStack {
                            toggleView(label: label, isOn: $booleanValue)
                            if booleanValue, let setting = getPickerSetting(for: key) {
                                pickerView(
                                    label: conditionalLabel ?? label,
                                    displayPicker: $displayConditionalPicker,
                                    setting: setting,
                                    decimalValue: $decimalValue
                                )
                            }
                        }
                    }

                    hintSection(
                        miniHint: miniHint,
                        shouldDisplayHint: $shouldDisplayHint,
                        verboseHint: verboseHint,
                        miniHintColor: miniHintColor
                    )
                }
            },
            header: { headerText.map(Text.init) },
            footer: { footerText.map(Text.init) }
        )
        .settingsSearchTarget(label: label)
    }

    // Helper function to retrieve PickerSetting based on key
    private func getPickerSetting(for key: String) -> PickerSetting? {
        pickerSettingsProvider.pickerSetting(for: key)
    }

    private func pickerView(
        label: String,
        displayPicker: Binding<Bool>,
        setting: PickerSetting,
        decimalValue: Binding<Decimal>
    ) -> some View {
        VStack {
            HStack {
                Text(label)
                    .foregroundColor(isChanged ? .accentColor : .primary)
                Spacer()
                if isChanged, let onReset = onReset {
                    Button(action: onReset) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                displayText(for: setting, decimalValue: decimalValue.wrappedValue)
                    .foregroundColor(!displayPicker.wrappedValue ? .primary : .accentColor)
            }
            .padding(.top)
            // whole row is the tap target and reads as one element: "label, value, button"
            .contentShape(Rectangle())
            .onTapGesture {
                displayPicker.wrappedValue.toggle()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(accessibilityValueString(for: setting, decimalValue: decimalValue.wrappedValue)))
            .accessibilityHint(Text(
                displayPicker.wrappedValue
                    ? String(localized: "Closes the value picker", comment: "Accessibility hint")
                    : String(localized: "Opens a picker to change the value", comment: "Accessibility hint")
            ))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { displayPicker.wrappedValue.toggle() }

            if displayPicker.wrappedValue {
                Picker(selection: decimalValue, label: Text(label)) {
                    ForEach(pickerSettingsProvider.generatePickerValues(from: setting, units: self.units), id: \.self) { value in
                        displayText(for: setting, decimalValue: value).tag(value)
                    }
                }
                .pickerStyle(WheelPickerStyle())
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func displayText(for setting: PickerSetting, decimalValue: Decimal) -> Text {
        Text(displayString(for: setting, decimalValue: decimalValue))
    }

    /// The value + unit as a plain string, for the visible label and the
    /// row's `accessibilityValue` (so VoiceOver announces the value + unit).
    private func displayString(for setting: PickerSetting, decimalValue: Decimal) -> String {
        switch setting.type {
        case .glucose:
            return decimalValue.formatted(withUnits: units)
        case .factor:
            return "\(decimalValue * 100) \(String(localized: "%", comment: "Percentage symbol"))"
        case .factorRaw:
            return "\(decimalValue)"
        case .insulinUnit:
            return "\(decimalValue) \(String(localized: "U", comment: "Insulin unit abbreviation"))"
        case .insulinUnitPerHour:
            return "\(decimalValue) \(String(localized: "U/hr", comment: "Insulin unit per hour abbreviation"))"
        case .gram:
            return "\(decimalValue) \(String(localized: "g", comment: "Gram abbreviation"))"
        case .minute:
            return "\(decimalValue) \(String(localized: "min", comment: "Minutes abbreviation"))"
        case .hour:
            return "\(decimalValue) \(String(localized: "hr", comment: "Hours abbreviation"))"
        case .percent:
            return "\(decimalValue) \(String(localized: "%", comment: "Percentage symbol"))"
        }
    }

    /// Same value as `displayString` but with the unit spelled out for VoiceOver.
    private func accessibilityValueString(for setting: PickerSetting, decimalValue: Decimal) -> String {
        switch setting.type {
        case .glucose:
            return decimalValue.formatted(for: units) + " " + units.spokenValue
        case .factor:
            return "\(decimalValue * 100) \(UnitSpelling.spoken("%"))"
        case .factorRaw:
            return "\(decimalValue)"
        case .insulinUnit:
            return "\(decimalValue) \(UnitSpelling.spoken("U"))"
        case .insulinUnitPerHour:
            return "\(decimalValue) \(UnitSpelling.spoken("U/hr"))"
        case .gram:
            return "\(decimalValue) \(UnitSpelling.spoken("g"))"
        case .minute:
            return "\(decimalValue) \(UnitSpelling.spoken("min"))"
        case .hour:
            return "\(decimalValue) \(UnitSpelling.spoken("hr"))"
        case .percent:
            return "\(decimalValue) \(UnitSpelling.spoken("%"))"
        }
    }

    private func toggleView(label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Toggle(isOn: isOn) {
                Text(label)
                    .foregroundColor(isChanged ? .accentColor : .primary)
            }
            if isChanged, let onReset = onReset {
                Button(action: onReset) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }.padding(.top)
    }

    public func hintSection(
        miniHint: String,
        shouldDisplayHint: Binding<Bool>,
        verboseHint: VerboseHint,
        miniHintColor: Color = .secondary
    ) -> some View {
        HStack(alignment: .center) {
            Text(miniHint)
                .font(.footnote)
                .foregroundColor(miniHintColor)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: {
                shouldDisplayHint.wrappedValue.toggle()
                selectedVerboseHint = shouldDisplayHint.wrappedValue ? verboseHint : nil
            }) {
                HStack {
                    Image(systemName: "questionmark.circle")
                }
            }
            .buttonStyle(BorderlessButtonStyle())
            .accessibilityLabel(Text("More information about \(label)"))
        }.padding(.vertical)
    }
}
