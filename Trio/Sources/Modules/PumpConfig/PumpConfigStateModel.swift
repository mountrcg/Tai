import LoopKit
import LoopKitUI
import MockKit
import SwiftDate
import SwiftUI

extension PumpConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var nightscout: NightscoutManager!
        @Injected() private var tidepoolManager: TidepoolManager!

        @Published var setupPump = false
        @Published var shouldDisplayPumpConcentrationWarning = false
        private(set) var setupPumpType: PumpType = .minimed
        @Published var pumpState: PumpDisplayState?
        private(set) var initialSettings: PumpInitialSettings = .default
        @Published var hasUnacknowledgedAlert: Bool = false
        @Published var useCustomPeakTime: Bool = false
        @Published var insulinPeakTime: Decimal = 75
        @Published var insulinActionCurve: Decimal = 10
        @Published var insulinConcentration: Decimal = 1
        @Published var allowDilution: Bool = false
        @Published var hideInsulinBadge: Bool = false
        @Injected() var bluetoothManager: BluetoothStateManager!

        var pumpSettings: PumpSettings {
            provider.settings()
        }

        var units: GlucoseUnits = .mgdL

        override func subscribe() {
            insulinActionCurve = pumpSettings.insulinActionCurve
            allowDilution = settings.settings.allowDilution
            subscribeSetting(\.insulinConcentration, on: $insulinConcentration) {
                insulinConcentration = $0 }
            subscribePreferencesSetting(\.useCustomPeakTime, on: $useCustomPeakTime) { useCustomPeakTime = $0 }
            subscribePreferencesSetting(\.insulinPeakTime, on: $insulinPeakTime) { insulinPeakTime = $0 }
            subscribeSetting(\.allowDilution, on: $allowDilution) { allowDilution = $0 }
            subscribeSetting(\.hideInsulinBadge, on: $hideInsulinBadge) { hideInsulinBadge = $0 }

            provider.pumpDisplayState
                .receive(on: DispatchQueue.main)
                .assign(to: \.pumpState, on: self)
                .store(in: &lifetime)

            hasUnacknowledgedAlert = provider.hasInitialUnacknowledgedAlerts()
            provider.unacknowledgedAlertsPublisher
                .receive(on: DispatchQueue.main)
                .assign(to: \.hasUnacknowledgedAlert, on: self)
                .store(in: &lifetime)

            Task {
                let basalSchedule = BasalRateSchedule(
                    dailyItems: await provider.getBasalProfile().map {
                        RepeatingScheduleValue(startTime: $0.minutes.minutes.timeInterval, value: Double($0.rate))
                    }
                )

                let pumpSettings = provider.pumpSettings()

                await MainActor.run {
                    initialSettings = PumpInitialSettings(
                        maxBolusUnits: Double(pumpSettings.maxBolus),
                        maxBasalRateUnitsPerHour: Double(pumpSettings.maxBasal),
                        basalSchedule: basalSchedule!
                    )
                }
            }
        }

        var isPumpSettingUnchanged: Bool {
            pumpSettings.insulinActionCurve == insulinActionCurve
        }

        func saveIfChanged() {
            if !isPumpSettingUnchanged {
                let settings = PumpSettings(
                    insulinActionCurve: insulinActionCurve,
                    maxBolus: pumpSettings.maxBolus,
                    maxBasal: pumpSettings.maxBasal
                )
                provider.save(settings: settings)
                    .receive(on: DispatchQueue.main)
                    .sink { _ in
                        let settings = self.provider.settings()
                        self.insulinActionCurve = settings.insulinActionCurve

                        Task.detached(priority: .low) {
                            do {
                                debug(.nightscout, "Attempting to upload DIA to Nightscout")
                                try await self.nightscout.uploadProfiles()
                            } catch {
                                debug(
                                    .default,
                                    "\(DebuggingIdentifiers.failed) failed to upload DIA to Nightscout: \(error.localizedDescription)"
                                )
                            }
                        }

                        Task.detached(priority: .low) {
                            await self.tidepoolManager.uploadSettings()
                        }
                    } receiveValue: {}
                    .store(in: &lifetime)
            }
        }

        func addPump(_ type: PumpType) {
            setupPumpType = type
            setupPump = true
        }

        /// User intent: open the pump driver's settings UI for the currently
        /// attached pump. At non-U100 we interpose a warning because anything
        /// the user sets in the pump's *own* screens (basal, temp basal,
        /// bolus) gets sent to the pump as a U100 value — the pump driver
        /// has no concept of concentration. If the user confirms, `setupPump`
        /// is flipped and the LoopKit settings sheet opens normally.
        func requestOpenPumpSettings() {
            if provider.apsManager.pumpManager != nil, settings.settings.insulinConcentration != 1 {
                shouldDisplayPumpConcentrationWarning = true
            } else {
                setupPump = true
            }
        }

        func ack() {
            provider.deviceManager.alertHistoryStorage.broadcastAlertUpdates()
        }

        /// Checks if the pump simulator is selected and resets it if Bundle.main.simulatorVisibility.isHidden is true
        private func checkAndResetPumpSimulatorIfNeeded() {
            // Only proceed if simulators should be hidden
            guard Bundle.main.simulatorVisibility.isHidden else { return }

            // Check if the current pump is a simulator
            if provider.apsManager.pumpManager is MockPumpManager {
                // Reset the pump manager to nil to allow selecting a new pump
                provider.apsManager.pumpManager = nil

                // Update UI state
                DispatchQueue.main.async {
                    self.pumpState = nil
                }

                debug(.service, "Pump simulator was reset because simulators are hidden")
            }
        }
    }
}

extension PumpConfig.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        setupPump = false
    }
}

extension PumpConfig.StateModel: PumpManagerOnboardingDelegate {
    func pumpManagerOnboarding(didCreatePumpManager pumpManager: PumpManagerUI) {
        provider.setPumpManager(pumpManager)
        if let insulinType = pumpManager.status.insulinType {
            settingsManager.updateInsulinCurve(insulinType)
        }
    }

    func pumpManagerOnboarding(didOnboardPumpManager _: PumpManagerUI) {
        // nothing to do
    }

    func pumpManagerOnboarding(didPauseOnboarding _: PumpManagerUI) {
        // TODO:
    }
}
