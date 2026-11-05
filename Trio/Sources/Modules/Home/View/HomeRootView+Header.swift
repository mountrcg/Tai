import CoreData
import SwiftUI

// MARK: - Device pickers

/// Presents the "Add CGM" / "Add Pump" pickers for the home screen.
///
/// Both selections are applied in `onDismiss` rather than inline: the home view already stacks several sheets,
/// and presenting the device setup sheet while the picker is still dismissing gets dropped by SwiftUI.
private struct DevicePickersModifier: ViewModifier {
    @Binding var showPumpSelection: Bool
    @Binding var showCGMSelection: Bool
    @Binding var pendingPump: PumpCatalogEntry?
    @Binding var pendingCGM: CGMCatalogEntry?
    let state: Home.StateModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showPumpSelection, onDismiss: {
                if let entry = pendingPump {
                    pendingPump = nil
                    state.addPump(entry)
                }
            }) {
                DevicePickerView(
                    title: String(localized: "Add Pump", comment: "The title of the pump chooser in settings"),
                    entries: DeviceCatalog.pumps
                ) { entry in
                    pendingPump = entry
                    showPumpSelection = false
                }
            }
            .sheet(isPresented: $showCGMSelection, onDismiss: {
                if let entry = pendingCGM {
                    pendingCGM = nil
                    state.addCGM(cgm: CGMModel(entry))
                }
            }) {
                DevicePickerView(
                    title: String(localized: "Add CGM", comment: "The title of the CGM chooser in settings"),
                    entries: DeviceCatalog.cgms
                ) { entry in
                    pendingCGM = entry
                    showCGMSelection = false
                }
            }
    }
}

extension View {
    func devicePickers(
        showPumpSelection: Binding<Bool>,
        showCGMSelection: Binding<Bool>,
        pendingPump: Binding<PumpCatalogEntry?>,
        pendingCGM: Binding<CGMCatalogEntry?>,
        state: Home.StateModel
    ) -> some View {
        modifier(DevicePickersModifier(
            showPumpSelection: showPumpSelection,
            showCGMSelection: showCGMSelection,
            pendingPump: pendingPump,
            pendingCGM: pendingCGM,
            state: state
        ))
    }
}

// MARK: - Zone B: header (left info panel / glucose bobble / loop status)

extension Home.RootView {
    var glucoseView: some View {
        CurrentGlucoseView(
            concentration: state.concentration,
            hideInsulinBadge: state.hideInsulinBadge,
            timerDate: state.timerDate,
            units: state.units,
            alarm: state.alarm,
            lowGlucose: state.lowGlucose,
            highGlucose: state.highGlucose,
            cgmAvailable: state.cgmAvailable,
            currentGlucoseTarget: state.currentGlucoseTarget,
            glucoseColorScheme: state.glucoseColorScheme,
            glucose: state.latestTwoGlucoseValues,
            cgmProgress: state.showCgmSensorStatus ? state.cgmProgressHighlight : nil,
            cgmStatus: state.showCgmSensorStatus ? state.cgmDisplayState : nil,
            cgmSensorExpiresAt: state.showCgmSensorStatus ? state.cgmSensorExpiresAt : nil,
            cgmWarmupEndsAt: state.showCgmSensorStatus ? state.cgmWarmupEndsAt : nil
        )
        .onTapGesture {
            if !state.cgmAvailable {
                showCGMSelection.toggle()
            } else {
                state.shouldDisplayCGMSetupSheet.toggle()
            }
        }
        .accessibilityAction {
            if !state.cgmAvailable {
                showCGMSelection.toggle()
            } else {
                state.shouldDisplayCGMSetupSheet.toggle()
            }
        }
        .accessibilityAction(named: Text("Snooze alerts")) {
            showSnoozeSheet = true
        }
    }

    @ViewBuilder func rightHeaderPanel() -> some View {
        VStack(alignment: .trailing, spacing: 15) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 16))
                    .foregroundColor(.loopGreen)
                let isfValue = state.enactedAndNonEnactedDeterminations.first?.insulinSensitivity ?? NSDecimalNumber.zero
                let isfValueDecimal = isfValue.decimalValue
                let convertedISF = isfValueDecimal.formattedISF(for: state.units)
                Text(convertedISF)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
//                    Text("\(state.units.rawValue)/U")
//                        .font(.system(size: 12, design: .rounded))
            }

            /// eventualBG string
            if let eventualBG = state.enactedAndNonEnactedDeterminations.first?.eventualBG {
                let eventualGlucose = eventualBG as Decimal
                HStack {
                    Text(
                        "⇢"
                    ).font(.system(size: 18, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(eventualGlucose.formatted(for: state.units))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Eventual glucose"))
                .accessibilityValue(Text(
                    eventualGlucose.formatted(for: state.units)
                        + " " + state.units.spokenValue
                ))
            } else {
                HStack {
                    Text("⇢")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.secondary)
                    Text("--")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Eventual glucose"))
                .accessibilityValue(Text(verbatim: "--"))
            }
            /// Loop view at bottomLeading
            LoopView(
                dosingMode: state.dosingMode,
                timerDate: state.timerDate,
                isLooping: state.isLooping,
                lastLoopDate: state.lastLoopDate,
                manualTempBasal: state.manualTempBasal,
                lastGlucoseDate: state.lastGlucoseDate,
                lastPumpCommsDate: state.lastPumpCommsDate,
                hasDeviceIssue: state.hasDeviceIssue,
                determination: state.determinationsFromPersistence
            )
            .onTapGesture {
                state.isStatusPopupPresented.toggle()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text(String(localized: "Opens loop status", comment: "Accessibility hint")))
            .accessibilityAction { state.isStatusPopupPresented.toggle() }
        }
    }

    var basalString: String? {
        let rate: Decimal
        var manualBasalString = ""

        switch state.activeBasalDelivery {
        case .none:
            return nil
        case .suspended:
            rate = 0
        case let .temp(tempRate):
            if state.manualTempBasal {
                manualBasalString = String(
                    localized: " ⚠️",
                    comment: "Manual Temp basal"
                )
            }
            rate = tempRate
        case let .scheduled(scheduledRate):
            rate = scheduledRate
        }
        let rateString = Formatter.insulinFormatterToIncrement(for: state.bolusIncrement)
            .string(from: rate as NSNumber) ?? "0"
        return rateString + String(localized: " U/hr", comment: "Unit per hour with space") +
            manualBasalString
    }

    var isDeliveringScheduledBasal: Bool {
        if case .scheduled = state.activeBasalDelivery { return true }
        return false
    }

    @ViewBuilder func leftHeaderPanel() -> some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Image(systemName: "drop.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.insulin)
                Text(
                    (
                        Formatter.decimalFormatterWithTwoFractionDigits
                            .string(from: state.currentIOB as NSNumber) ?? "0"
                    ) +
                        String(localized: " U", comment: "Insulin unit")
                )
                .font(.callout).fontWeight(.bold).fontDesign(.rounded)
//                    InsulinConcentrationBadge(concentration: 1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Insulin on board"))
            .accessibilityValue(Text(
                (
                    Formatter.decimalFormatterWithTwoFractionDigits
                        .string(from: state.currentIOB as NSNumber) ?? "0"
                )
                    + String(localized: " U", comment: "Insulin unit")
            ))
            HStack {
                Image("premeal")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 15, height: 15)
                    .foregroundColor(.loopYellow)
                    .padding(.leading, 3)
                Text(
                    (
                        Formatter.decimalFormatterWithTwoFractionDigits.string(
                            from: NSNumber(value: state.enactedAndNonEnactedDeterminations.first?.cob ?? 0)
                        ) ?? "0"
                    ) +
                        String(localized: " g", comment: "gram of carbs")
                )
                .font(.callout).fontWeight(.bold).fontDesign(.rounded)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Carbs on board"))
            .accessibilityValue(Text(
                (Formatter.decimalFormatterWithTwoFractionDigits.string(
                    from: NSNumber(value: state.enactedAndNonEnactedDeterminations.first?.cob ?? 0)
                ) ?? "0") + String(localized: " g", comment: "gram of carbs")
            ))
            HStack {
                /// Only display the insulin delivery rate info if the pump is not
                /// suspended and is available (e.g., pod is paired & not faulted).
                if let apsManager = state.apsManager {
                    let pumpAvailable = apsManager.isScheduledBasal != nil
                    if apsManager.isSuspended {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 16))
                            .rotationEffect(Angle(degrees: 180))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.insulinTintColor.opacity(0.9), .insulinTintColor.opacity(0.2)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        Text("0" + String(localized: " U/hr", comment: "Unit per hour with space"))
                            .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                            .foregroundColor(.orange)
                    } else if pumpAvailable {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 16))
                            .rotationEffect(Angle(degrees: 180))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.insulinTintColor.opacity(0.9), .insulinTintColor.opacity(0.2)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        if let basalString = self.basalString {
                            /// Adjust opacity when displaying a scheduled basal rate
                            let opacity = isDeliveringScheduledBasal ? 0.6 : 1.0
                            if basalString.count > 5 {
                                Text(basalString)
                                    .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .truncationMode(.tail)
                                    .allowsTightening(true)
                                    .opacity(opacity)
                            } else {
                                // Short strings can just display normally
                                Text(basalString)
                                    .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                                    .opacity(opacity)
                            }
                        } else {
                            Text("No Data")
                                .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                        }
                    }
                }
            }
        }
    }
}
