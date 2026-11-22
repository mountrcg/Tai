import CGMBLEKit
import Combine
import G7SensorKit
import LoopKitUI
import SwiftUI

/// For a full description of the events that can happen for the CGM lifecycle, see comment at the top
/// of HomeStateModel+CGM since these are the same events

struct CGMModel: Identifiable, Hashable {
    var id: String
    var type: CGMType
    var displayName: String
    var subtitle: String
}

extension CGMModel {
    init(_ entry: CGMCatalogEntry) {
        self.init(id: entry.id, type: entry.cgmType, displayName: entry.name, subtitle: entry.subtitle)
    }
}

let cgmDefaultModel = CGMModel(
    id: CGMType.none.id,
    type: .none,
    displayName: CGMType.none.displayName,
    subtitle: CGMType.none.subtitle
)

extension CGMSettings {
    final class StateModel: BaseStateModel<Provider> {
        // Singleton implementation
        private static var _shared: StateModel?
        static var shared: StateModel {
            if _shared == nil {
                _shared = StateModel()
                _shared?.resolver = TrioApp.resolver
            }
            return _shared!
        }

        @Injected() var fetchGlucoseManager: FetchGlucoseManager!
        @Injected() var pluginCGMManager: PluginManager!
        @Injected() var broadcaster: Broadcaster!
        @Injected() var nightscoutManager: NightscoutManager!
        @Injected() var bluetoothManager: BluetoothStateManager!
        @Injected() var logExport: LogExport!
        @Injected() var glucoseStorage: GlucoseStorage!

        @Published var units: GlucoseUnits = .mgdL
        @Published var shouldDisplayCGMSetupSheet: Bool = false
        @Published var cgmCurrent = cgmDefaultModel
        @Published var smoothGlucose = false
        @Published var smoothingAlgorithm: GlucoseSmoothingAlgorithm = .ukf
        @Published var cgmTransmitterDeviceAddress: String? = nil
        @Published var listOfCGM: [CGMModel] = []
        @Published var url: URL?

        @Published var enableSub5MinuteGlucose = false {
            didSet {
                if !enableSub5MinuteGlucose { suggestionBaseline = nil }
                else if !oldValue { seedSuggestionBaseline() }
            }
        }

        @Published var sub5MinuteLoopInterval: Decimal = 5
        @Published var smbInterval: Decimal = 3
        @Published var smbDeliveryRatio: Decimal = 0.85 {
            didSet { seedSuggestionBaseline() }
        }

        @Published var smbDeliveryRatioMin: Decimal = 0.65
        @Published var smbDeliveryRatioMax: Decimal = 0.80
        @Published var smbDeliveryRatioBGrange: Decimal = 0

        /// CGM reading interval detected from the readings while sub-5-minute loops are on; the loop
        /// runs on every reading, so this is also the loop frequency. nil until detection has run.
        @Published var detectedCGMMinutes: Int?

        func refreshDetectedCGMMinutes() {
            detectedCGMMinutes = enableSub5MinuteGlucose
                ? glucoseStorage?.observationContext.map { CGMCadenceChangeMonitor.minutes(for: $0.cadence) }
                : nil
        }

        /// Loop frequency in minutes as shown on the page: 5 with sub-5-minute loops off, otherwise the
        /// detected CGM interval; while detection is still running a 1-minute CGM is assumed so the
        /// scaling chart can be used right away.
        var effectiveLoopMinutes: Int {
            guard enableSub5MinuteGlucose else { return 5 }
            return detectedCGMMinutes ?? 1
        }

        /// Nominal SMB cadence (minutes) the delivery ratio applies to: max(loop frequency, SMB interval).
        var smbRatioPeriod: Double {
            max(Double(effectiveLoopMinutes), NSDecimalNumber(decimal: smbInterval).doubleValue)
        }

        /// User switched sub-5-minute loops on or off: the loop cadence changes with it, so the user is
        /// asked to review the SMB delivery ratios.
        func setSub5MinuteGlucose(_ enabled: Bool) {
            guard enabled != enableSub5MinuteGlucose else { return }
            enableSub5MinuteGlucose = enabled
            refreshDetectedCGMMinutes()
            fetchGlucoseManager?.notifySub5MinuteLoopsToggled(enabled: enabled)
        }

        @Published var suggestionBaseline: SmbDeliveryRatioSuggestion.Baseline?
        private var previousSource: String?

        var isSuitableSource: Bool {
            guard let settings = settingsManager?.settings else { return false }
            return settings.cgm == .plugin &&
                CGMCatalogEntry.supportsRawGlucoseObservations(identifier: settings.cgmPluginIdentifier)
        }

        private var sourceIdentity: String {
            let settings = settingsManager.settings
            return settings.cgm.id + ":" + (settings.cgm == .plugin ? settings.cgmPluginIdentifier : "")
        }

        var suggestedRatio: Decimal? {
            guard enableSub5MinuteGlucose, isSuitableSource, let baseline = suggestionBaseline,
                  case let .suggestion(value, _) = SmbDeliveryRatioSuggestion.suggestion(
                      baseline: baseline, loopInterval: sub5MinuteLoopInterval, smbInterval: smbInterval
                  ), value < smbDeliveryRatio else { return nil }
            return value
        }

        func sub5MinuteSectionAppeared() {
            guard let scope else { return }
            let preferences = scope.preferences
            enableSub5MinuteGlucose = preferences.enableSub5MinuteGlucose
            sub5MinuteLoopInterval = preferences.sub5MinuteLoopInterval
            smbInterval = preferences.smbInterval
            smbDeliveryRatio = preferences.smbDeliveryRatio
            smbDeliveryRatioMin = preferences.smbDeliveryRatioMin
            smbDeliveryRatioMax = preferences.smbDeliveryRatioMax
            smbDeliveryRatioBGrange = preferences.smbDeliveryRatioBGrange
            refreshDetectedCGMMinutes()
            seedSuggestionBaseline()
        }

        func seedSuggestionBaseline() {
            suggestionBaseline = enableSub5MinuteGlucose ? .init(
                loopInterval: sub5MinuteLoopInterval, smbInterval: smbInterval, ratio: smbDeliveryRatio
            ) : nil
        }

        func applySuggestedRatio() {
            guard let value = suggestedRatio else { return }
            smbDeliveryRatio = value
        }

        func normalizeSub5MinuteSettingsOnSourceChange() {
            let currentSource = sourceIdentity
            defer { previousSource = currentSource }
            guard let previousSource, previousSource != currentSource, !isSuitableSource else { return }
            var preferences = scope.preferences
            preferences.normalizeSub5MinuteSettings()
            scope.preferences = preferences
            enableSub5MinuteGlucose = preferences.enableSub5MinuteGlucose
            sub5MinuteLoopInterval = preferences.sub5MinuteLoopInterval
            smbInterval = preferences.smbInterval
            smbDeliveryRatio = preferences.smbDeliveryRatio
        }

        var shouldRunDeleteOnSettingsChange = true

        override func subscribe() {
            previousSource = sourceIdentity
            units = settingsManager.settings.units
            broadcaster.register(SettingsObserver.self, observer: self)

            listOfCGM = DeviceCatalog.cgmModels

            switch settingsManager.settings.cgm {
            case .plugin:
                if let cgmPluginInfo = listOfCGM.first(where: { $0.id == settingsManager.settings.cgmPluginIdentifier }) {
                    cgmCurrent = CGMModel(
                        id: settingsManager.settings.cgmPluginIdentifier,
                        type: .plugin,
                        displayName: cgmPluginInfo.displayName,
                        subtitle: cgmPluginInfo.subtitle
                    )
                } else {
                    // no more type of plugin available - fallback to default model
                    cgmCurrent = cgmDefaultModel
                }
            default:
                cgmCurrent = CGMModel(
                    id: settingsManager.settings.cgm.id,
                    type: settingsManager.settings.cgm,
                    displayName: settingsManager.settings.cgm.displayName,
                    subtitle: settingsManager.settings.cgm.subtitle
                )
            }

            url = nightscoutManager.cgmURL
            switch url?.absoluteString {
            case "http://127.0.0.1:1979":
                url = URL(string: "spikeapp://")!
            case "http://127.0.0.1:17580":
                url = URL(string: "diabox://")!
            default: break
            }

            cgmTransmitterDeviceAddress = UserDefaults.standard.cgmTransmitterDeviceAddress

            subscribePreferencesSetting(\.enableSub5MinuteGlucose, on: $enableSub5MinuteGlucose) { enableSub5MinuteGlucose = $0 }
            subscribePreferencesSetting(\.sub5MinuteLoopInterval, on: $sub5MinuteLoopInterval) { sub5MinuteLoopInterval = $0 }
            subscribePreferencesSetting(\.smbInterval, on: $smbInterval) { smbInterval = $0 }
            subscribePreferencesSetting(\.smbDeliveryRatio, on: $smbDeliveryRatio) { smbDeliveryRatio = $0 }
            subscribePreferencesSetting(\.smbDeliveryRatioMin, on: $smbDeliveryRatioMin) { smbDeliveryRatioMin = $0 }
            subscribePreferencesSetting(\.smbDeliveryRatioMax, on: $smbDeliveryRatioMax) { smbDeliveryRatioMax = $0 }
            subscribePreferencesSetting(\.smbDeliveryRatioBGrange, on: $smbDeliveryRatioBGrange) { smbDeliveryRatioBGrange = $0 }
            // A new SMB Interval changes how often SMBs can be given, which the ratios must follow.
            $smbInterval
                .removeDuplicates()
                .scan((old: smbInterval, new: smbInterval)) { (old: $0.new, new: $1) }
                .dropFirst()
                .sink { [weak self] change in
                    guard let self else { return }
                    let loop = self.effectiveLoopMinutes
                    let oldPeriod = SmbRatioReviewNotice.smbPeriod(cgmMinutes: loop, smbInterval: change.old)
                    let newPeriod = SmbRatioReviewNotice.smbPeriod(cgmMinutes: loop, smbInterval: change.new)
                    guard oldPeriod != newPeriod else { return }
                    SmbRatioReviewNotice.shared.post(
                        toDense: self.enableSub5MinuteGlucose,
                        cgmMinutes: self.detectedCGMMinutes,
                        smbPeriodMinutes: newPeriod
                    )
                }
                .store(in: &lifetime)
            // Changing a delivery ratio after a cadence change is the review the Home notice asks for.
            Publishers.Merge3(
                $smbDeliveryRatio.removeDuplicates().dropFirst(),
                $smbDeliveryRatioMin.removeDuplicates().dropFirst(),
                $smbDeliveryRatioMax.removeDuplicates().dropFirst()
            )
            .sink { _ in SmbRatioReviewNotice.shared.clear() }
            .store(in: &lifetime)
            subscribeSetting(\.smoothGlucose, on: $smoothGlucose, initial: { smoothGlucose = $0 })
            subscribeSetting(\.smoothingAlgorithm, on: $smoothingAlgorithm, initial: { smoothingAlgorithm = $0 })
        }

        // this function will get called for all CGM types (plugin and non plugin)
        func addCGM(cgm: CGMModel) {
            cgmCurrent = cgm
            switch cgm.type {
            case .plugin:
                // Not toggle(): addCGM is now invoked from a sheet's onDismiss, where a stale true would close
                // the setup sheet instead of opening it.
                shouldDisplayCGMSetupSheet = true
            default:
                // non plugin CGM types should be considered onboarded right away
                shouldDisplayCGMSetupSheet = true
                settingsManager.settings.cgm = cgmCurrent.type
                settingsManager.settings.cgmPluginIdentifier = ""
                normalizeSub5MinuteSettingsOnSourceChange()
                fetchGlucoseManager.updateGlucoseSource(cgmGlucoseSourceType: cgmCurrent.type, cgmGlucosePluginId: cgmCurrent.id)
                broadcaster.notify(GlucoseObserver.self, on: .main) {
                    $0.glucoseDidUpdate([])
                }
            }
        }

        // Note: This function does _not_ get called for plugin CGMs
        // instead, they will get cgmManagerWantsDeletion events which
        // are handled by PluginSource
        func deleteCGM() {
            Task {
                await self.fetchGlucoseManager?.deleteGlucoseSource()

                await MainActor.run {
                    self.normalizeSub5MinuteSettingsOnSourceChange()
                    self.shouldDisplayCGMSetupSheet = false
                    broadcaster.notify(GlucoseObserver.self, on: .main) {
                        $0.glucoseDidUpdate([])
                    }
                }
            }
        }
    }
}

extension CGMSettings.StateModel: CompletionDelegate {
    func completionNotifyingDidComplete(_: CompletionNotifying) {
        Task {
            // this sleep is because this event and cgmManagerWantsDeletion
            // are called in parallel.
            try await Task.sleep(for: .seconds(0.2))
            await MainActor.run {
                if fetchGlucoseManager.cgmGlucoseSourceType == .none {
                    cgmCurrent = cgmDefaultModel
                }
            }
        }
        shouldDisplayCGMSetupSheet = false
    }
}

extension CGMSettings.StateModel: CGMManagerOnboardingDelegate {
    func cgmManagerOnboarding(didCreateCGMManager manager: LoopKitUI.CGMManagerUI) {
        // cgmCurrent should have been set in addCGM
        info(.cgm, "CGM \(cgmCurrent.displayName) added")
        settingsManager.settings.cgm = cgmCurrent.type
        settingsManager.settings.cgmPluginIdentifier = cgmCurrent.id
        normalizeSub5MinuteSettingsOnSourceChange()
        fetchGlucoseManager.updateGlucoseSource(
            cgmGlucoseSourceType: cgmCurrent.type,
            cgmGlucosePluginId: cgmCurrent.id,
            newManager: manager
        )
        DispatchQueue.main.async {
            self.broadcaster.notify(GlucoseObserver.self, on: .main) {
                $0.glucoseDidUpdate([])
            }
        }
    }

    func cgmManagerOnboarding(didOnboardCGMManager _: LoopKitUI.CGMManagerUI) {
        normalizeSub5MinuteSettingsOnSourceChange()
    }
}

extension CGMSettings.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        normalizeSub5MinuteSettingsOnSourceChange()
        objectWillChange.send()
        units = settingsManager.settings.units
        // Deletes are handled differently for plugins vs non plugins
        // but both will call deleteGlucoseSource on the fetchGlucoseManager
        // so we listen for changes to the cgm setting and update our internal
        // state accordingly
        if settingsManager.settings.cgm == .none, shouldRunDeleteOnSettingsChange {
            shouldRunDeleteOnSettingsChange = false
            cgmCurrent = cgmDefaultModel
            DispatchQueue.main.async {
                self.broadcaster.notify(GlucoseObserver.self, on: .main) {
                    $0.glucoseDidUpdate([])
                }
            }
        } else {
            shouldRunDeleteOnSettingsChange = true
        }
    }
}
