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
        @Published var ratioReview: SmbDeliveryRatioReview?

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
        // preference
        var smbDeliveryRatio: Decimal {
            get { ratioReview?.preferences.smbDeliveryRatio ?? 0.85 }
            set { ratioReview?.change(\.smbDeliveryRatio, to: newValue) }
        }

        @Published var smbInterval: Decimal = 3
        @Published var useProfileCSF: Bool = false

        override func subscribe() {
            units = settingsManager.settings.units
            ratioReview = SmbDeliveryRatioReview(scope: scope, revision: { [weak self] in
                self?.settingsManager.glucoseInputRevision?.uuidString ?? ""
            }) { [weak self] in
                guard let self else { return "unavailable" }
                let source = settingsManager.settings.cgm.id + settingsManager.settings.cgmPluginIdentifier
                if scope.isDraft { return "draft." + source }
                let context = CoreDataStack.shared.newTaskContext()
                var identity = "live"
                context.performAndWait {
                    if let profile = try? context.fetch(ProfileStored.fetch(.activeProfile, fetchLimit: 1)).first {
                        identity = profile.id?.uuidString ?? profile.objectID.uriRepresentation().absoluteString
                    }
                }
                return identity + "." + source
            }

            ratioReview?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &lifetime)

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
            subscribePreferencesSetting(\.smbInterval, on: $smbInterval) { smbInterval = $0 }
            subscribePreferencesSetting(\.useProfileCSF, on: $useProfileCSF) { useProfileCSF = $0 }
        }
    }
}

extension AlgorithmAdvancedSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
