import Combine
import Observation
import SwiftUI

extension AutoISFSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var settings: SettingsManager!

        @Injected() var broadcaster: Broadcaster!
        @Injected() var glucoseStorage: GlucoseStorage!
        @Published var autoISFParabolaSmoothed = false
        @Published var autoISFParabolaMinMinutes: Decimal?

        var isSuitableSource: Bool {
            guard let settings = settingsManager?.settings else { return false }
            return settings.cgm == .plugin &&
                CGMCatalogEntry.supportsRawGlucoseObservations(identifier: settings.cgmPluginIdentifier)
        }

        var automaticParabolaMinimum: Decimal {
            (glucoseStorage.observationContext?.cadence ?? .legacy).parabolaMinimum(override: nil)
        }

        var units: GlucoseUnits = .mgdL

        // Published properties for state binding
        @Published var autoisf: Bool = false {
            didSet {
                updateEnableAutosens()
                if autoisf {
                    scope.preferences.useNewFormula = false
                    scope.preferences.sigmoid = false
                }
            }
        }

        @Published var enableAutosens: Bool = true
        @Published var enableSMBEvenOnOddOffAlways: Bool = false
        @Published var autoISFoffSport: Bool = false
        @Published var autoISFmax: Decimal = 2
        @Published var autoISFmin: Decimal = 0.5
        @Published var smbDeliveryRatio: Decimal = 0.85
        @Published var smbDeliveryRatioMin: Decimal = 0.65
        @Published var smbDeliveryRatioMax: Decimal = 0.80
        @Published var smbDeliveryRatioBGrange: Decimal = 0
        @Published var smbMaxRangeExtension: Decimal = 2
        @Published var smbInterval: Decimal = 3
        @Published var enableBGAcceleration: Bool = true
        @Published var autoISFhourlyChange: Decimal = 0.6
        @Published var lowerISFrangeWeight: Decimal = 0.7
        @Published var higherISFrangeWeight: Decimal = 0.3
        @Published var bgAccelISFweight: Decimal = 0.15
        @Published var bgBrakeISFweight: Decimal = 0.15
        @Published var postMealISFweight: Decimal = 0.02
        @Published var iobThresholdPercent: Decimal = 1
        @Published var enableBGacceleration: Bool = false

        var insulinActionCurve: Decimal = 6

        // Method to update enableAutosens when autoisf is false
        private func updateEnableAutosens() {
            if !autoisf {
                enableAutosens = true // Always enable autosens to true when autoisf is false
            }
        }

        override func subscribe() {
            broadcaster.register(SettingsObserver.self, observer: self)
            units = settingsManager.settings.units
            subscribePreferencesSetting(\.autoISFParabolaSmoothed, on: $autoISFParabolaSmoothed) { autoISFParabolaSmoothed = $0 }
            subscribePreferencesSetting(\.autoISFParabolaMinMinutes, on: $autoISFParabolaMinMinutes) {
                autoISFParabolaMinMinutes = $0 }
            // Ensure all preferences map to state properties correctly
            subscribePreferencesSetting(\.autoisf, on: $autoisf) { autoisf = $0 }
            subscribePreferencesSetting(\.enableAutosens, on: $enableAutosens) { enableAutosens = $0 }
            subscribePreferencesSetting(\.enableSMBEvenOnOddOffAlways, on: $enableSMBEvenOnOddOffAlways) {
                enableSMBEvenOnOddOffAlways = $0 }
            subscribePreferencesSetting(\.autoISFoffSport, on: $autoISFoffSport) { autoISFoffSport = $0 }
            subscribePreferencesSetting(\.iobThresholdPercent, on: $iobThresholdPercent) { iobThresholdPercent = $0 }
            subscribePreferencesSetting(\.enableBGacceleration, on: $enableBGacceleration) { enableBGacceleration = $0 }
            subscribePreferencesSetting(\.autoISFmax, on: $autoISFmax) { autoISFmax = $0 }
            subscribePreferencesSetting(\.autoISFmin, on: $autoISFmin) { autoISFmin = $0 }
            subscribePreferencesSetting(\.smbDeliveryRatio, on: $smbDeliveryRatio) { smbDeliveryRatio = $0 }
            subscribePreferencesSetting(\.smbDeliveryRatioMin, on: $smbDeliveryRatioMin) { smbDeliveryRatioMin = $0 }
            subscribePreferencesSetting(\.smbDeliveryRatioMax, on: $smbDeliveryRatioMax) { smbDeliveryRatioMax = $0 }
            subscribePreferencesSetting(\.smbDeliveryRatioBGrange, on: $smbDeliveryRatioBGrange) { smbDeliveryRatioBGrange = $0 }
            // Changing a delivery ratio after a cadence change is the review the Home notice asks for.
            Publishers.Merge3(
                $smbDeliveryRatio.removeDuplicates().dropFirst(),
                $smbDeliveryRatioMin.removeDuplicates().dropFirst(),
                $smbDeliveryRatioMax.removeDuplicates().dropFirst()
            )
            .sink { _ in SmbRatioReviewNotice.shared.clear() }
            .store(in: &lifetime)
            subscribePreferencesSetting(\.smbMaxRangeExtension, on: $smbMaxRangeExtension) { smbMaxRangeExtension = $0 }
            subscribePreferencesSetting(\.smbInterval, on: $smbInterval) { smbInterval = $0 }
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
            subscribePreferencesSetting(\.enableBGacceleration, on: $enableBGAcceleration) { enableBGAcceleration = $0 }
            subscribePreferencesSetting(\.autoISFhourlyChange, on: $autoISFhourlyChange) { autoISFhourlyChange = $0 }
            subscribePreferencesSetting(\.lowerISFrangeWeight, on: $lowerISFrangeWeight) { lowerISFrangeWeight = $0 }
            subscribePreferencesSetting(\.higherISFrangeWeight, on: $higherISFrangeWeight) { higherISFrangeWeight = $0 }
            subscribePreferencesSetting(\.bgAccelISFweight, on: $bgAccelISFweight) { bgAccelISFweight = $0 }
            subscribePreferencesSetting(\.bgBrakeISFweight, on: $bgBrakeISFweight) { bgBrakeISFweight = $0 }
            subscribePreferencesSetting(\.postMealISFweight, on: $postMealISFweight) { postMealISFweight = $0 }
        }
    }
}

extension AutoISFSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        objectWillChange.send()
        units = settingsManager.settings.units
    }
}
