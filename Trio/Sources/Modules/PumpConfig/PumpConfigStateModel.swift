import Foundation
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
        private(set) var setupPumpEntry: PumpCatalogEntry?
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
        @Injected() var logExport: LogExport!

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
                                warning(.nightscout, "Uploading DIA to Nightscout failed", error: error)
                            }
                        }

                        Task.detached(priority: .low) {
                            await self.tidepoolManager.uploadSettings()
                        }
                    } receiveValue: {}
                    .store(in: &lifetime)
            }
        }

        func addPump(_ entry: PumpCatalogEntry) {
            setupPumpEntry = entry
            setupPump = true
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
