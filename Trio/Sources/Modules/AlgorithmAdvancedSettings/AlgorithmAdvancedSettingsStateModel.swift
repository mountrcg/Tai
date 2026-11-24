import Combine
import CoreData
import Observation
import SwiftUI

extension AlgorithmAdvancedSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!
        @Injected() var storage: FileStorage!
        @Injected() var nightscout: NightscoutManager!
        @Injected() var glucoseStorage: GlucoseStorage!

        var units: GlucoseUnits = .mgdL

        // settings
        @Published var maxDailySafetyMultiplier: Decimal = 3
        @Published var currentBasalSafetyMultiplier: Decimal = 4
        @Published var skipNeutralTemps: Bool = false
        @Published var unsuspendIfNoTemp: Bool = false
        @Published var min5mCarbimpact: Decimal = 8
        @Published var remainingCarbsFraction: Decimal = 1.0
        @Published var remainingCarbsCap: Decimal = 90
        @Published var noisyCGMTargetMultiplier: Decimal = 1.3
        @Published var smbInterval: Decimal = 3
        @Published var smbDeliveryRatio: Decimal = 0.85
        // preference
        @Published var useProfileCSF: Bool = false

        override func subscribe() {
            units = settingsManager.settings.units
            subscribePreferencesSetting(\.maxDailySafetyMultiplier, on: $maxDailySafetyMultiplier) {
                maxDailySafetyMultiplier = $0
            }
            subscribePreferencesSetting(\.currentBasalSafetyMultiplier, on: $currentBasalSafetyMultiplier) {
                currentBasalSafetyMultiplier = $0
            }
            subscribePreferencesSetting(\.skipNeutralTemps, on: $skipNeutralTemps) { skipNeutralTemps = $0 }
            subscribePreferencesSetting(\.unsuspendIfNoTemp, on: $unsuspendIfNoTemp) { unsuspendIfNoTemp = $0 }
            subscribePreferencesSetting(\.min5mCarbimpact, on: $min5mCarbimpact) { min5mCarbimpact = $0 }
            subscribePreferencesSetting(\.remainingCarbsFraction, on: $remainingCarbsFraction) { remainingCarbsFraction = $0 }
            subscribePreferencesSetting(\.remainingCarbsCap, on: $remainingCarbsCap) { remainingCarbsCap = $0 }
            subscribePreferencesSetting(\.noisyCGMTargetMultiplier, on: $noisyCGMTargetMultiplier) {
                noisyCGMTargetMultiplier = $0
            }
            subscribePreferencesSetting(\.useProfileCSF, on: $useProfileCSF) { useProfileCSF = $0 }
            subscribePreferencesSetting(\.smbInterval, on: $smbInterval) { smbInterval = $0 }
            subscribePreferencesSetting(\.smbDeliveryRatio, on: $smbDeliveryRatio) { smbDeliveryRatio = $0 }
            // Changing the ratio is the review the Home notice asks for.
            $smbDeliveryRatio.removeDuplicates().dropFirst()
                .sink { _ in SmbRatioReviewNotice.shared.clear() }
                .store(in: &lifetime)
            // A new SMB Interval changes how often SMBs can be given, which the delivery ratios must follow.
            $smbInterval
                .removeDuplicates()
                .scan((old: smbInterval, new: smbInterval)) { (old: $0.new, new: $1) }
                .dropFirst()
                .sink { [weak self] change in
                    guard let self else { return }
                    SmbRatioReviewNotice.shared.smbIntervalChanged(
                        from: change.old, to: change.new,
                        preferences: self.settingsManager.preferences,
                        observation: self.glucoseStorage?.observationContext
                    )
                }
                .store(in: &lifetime)
        }
    }
}

extension AlgorithmAdvancedSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
