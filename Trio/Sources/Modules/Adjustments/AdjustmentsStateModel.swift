import Combine
import CoreData
import Observation
import SwiftUI

extension Adjustments {
    @Observable final class StateModel: BaseStateModel<Provider> {
        // MARK: - Injected Dependencies

        @ObservationIgnored @Injected() var broadcaster: Broadcaster!
        @ObservationIgnored @Injected() var tempTargetStorage: TempTargetsStorage!
        @ObservationIgnored @Injected() var apsManager: APSManager!
        @ObservationIgnored @Injected() var overrideStorage: OverrideStorage!
        @ObservationIgnored @Injected() var nightscoutManager: NightscoutManager!

        var requireAdjustmentsConfirmation: Bool = false
        var shouldDisplayPresetStartConfirmDialog: Bool = false

        // MARK: - Override and Temp Target Properties

        var overridePercentage: Double = 100
        var isOverrideEnabled = false
        var indefinite = true
        var overrideDuration: Decimal = 0
        var target: Decimal = 0
        var currentGlucoseTarget: Decimal = 100
        var shouldOverrideTarget: Bool = false
        var smbIsOff: Bool = false
        var id = ""
        var overrideName: String = ""
        var isPreset: Bool = false
        var overridePresets: [OverrideStored] = []
        var advancedSettings: Bool = false
        var isfAndCr: Bool = true
        var isf: Bool = true
        var cr: Bool = true
        var smbIsScheduledOff: Bool = false
        var start: Decimal = 0
        var end: Decimal = 0
        var smbMinutes: Decimal = 0
        var uamMinutes: Decimal = 0
        var defaultSmbMinutes: Decimal = 0
        var defaultUamMinutes: Decimal = 0
        var selectedTab: Tab = .tempTargets

        // AutoISF profile injection overrides — nil means use profile default
        var overrideAutoISFmin: Decimal?
        var overrideAutoISFmax: Decimal?
        var overrideAutoISFhourlyChange: Decimal?
        var overrideHigherISFrangeWeight: Decimal?
        var overrideLowerISFrangeWeight: Decimal?
        var overridePostMealISFweight: Decimal?
        var overrideBgAccelISFweight: Decimal?
        var overrideBgBrakeISFweight: Decimal?
        var overrideIobThresholdPercent: Decimal?
        var overrideSmbDeliveryRatio: Decimal?
        var overrideSmbDeliveryRatioBGrange: Decimal?
        var overrideSmbDeliveryRatioMin: Decimal?
        var overrideSmbDeliveryRatioMax: Decimal?
        var overrideEnableBGacceleration: Bool?
        // Profile defaults for color comparison in UI
        var profileAutoISFmin: Decimal = 0.5
        var profileAutoISFmax: Decimal = 2
        var profileAutoISFhourlyChange: Decimal = 0
        var profileHigherISFrangeWeight: Decimal = 0
        var profileLowerISFrangeWeight: Decimal = 0
        var profilePostMealISFweight: Decimal = 0
        var profileBgAccelISFweight: Decimal = 0.15
        var profileBgBrakeISFweight: Decimal = 0.15
        var profileIobThresholdPercent: Decimal = 1
        var profileSmbDeliveryRatio: Decimal = 0.5
        var profileSmbDeliveryRatioBGrange: Decimal = 0
        var profileSmbDeliveryRatioMin: Decimal = 0.5
        var profileSmbDeliveryRatioMax: Decimal = 0.8
        var profileEnableBGacceleration: Bool = true
        var useAutoISF: Bool = false
        var activeOverrideName: String = ""
        var currentActiveOverride: OverrideStored?
        var activeTempTargetName: String = ""

        var currentActiveTempTarget: TempTargetStored?
        var showOverrideEditSheet = false
        var showTempTargetEditSheet = false
        var units: GlucoseUnits = .mgdL

        // Temp Target Properties
        var tempTargetDuration: Decimal = 0
        var tempTargetName: String = ""
        var tempTargetTarget: Decimal = 100
        var isTempTargetEnabled: Bool = false
        var date = Date()
        var newPresetName = ""
        var tempTargetPresets: [TempTargetStored] = []
        var scheduledTempTargets: [TempTargetStored] = []
        var percentage: Double = 100
        var autosensMax: Decimal = 1.2
        var halfBasalTarget: Decimal = 160
        var settingHalfBasalTarget: Decimal = 160
        var highTTraisesSens: Bool = false
        var lowTTlowersSens: Bool = false
        var didSaveSettings: Bool = false

        // Core Data
        let coredataContext = CoreDataStack.shared.newTaskContext()
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        // Help Sheet
        var isHelpSheetPresented: Bool = false
        var helpSheetDetent = PresentationDetent.large

        // Combine
        private var cancellables = Set<AnyCancellable>()

        // MARK: - Lifecycle

        /// Subscribes to notifications and initializes settings.
        override func subscribe() {
            setupNotification()
            setupSettings()
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PreferencesObserver.self, observer: self)

            Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { self.setupOverridePresetsArray() }
                    group.addTask { self.setupTempTargetPresetsArray() }
                    // Populate the scheduled-TT list on first load too —
                    // shortcut-driven scheduling can persist rows while this
                    // view's StateModel hasn't been instantiated yet.
                    group.addTask { self.setupScheduledTempTargetsArray() }
                    group.addTask { self.updateLatestOverrideConfiguration() }
                    group.addTask { self.updateLatestTempTargetConfiguration() }
                }
            }
        }

        /// Retrieves the current glucose target based on the time of day.
        func getCurrentGlucoseTarget() async {
            let now = Date()
            let calendar = Calendar.current
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "HH:mm:ss"
            dateFormatter.timeZone = TimeZone.current

            let bgTargets = await provider.getBGTargets()
            let entries: [(start: String, value: Decimal)] = bgTargets.targets.map { ($0.start, $0.low) }

            for (index, entry) in entries.enumerated() {
                guard let entryTime = dateFormatter.date(from: entry.start) else {
                    print("Invalid entry start time: \(entry.start)")
                    continue
                }

                let entryComponents = calendar.dateComponents([.hour, .minute, .second], from: entryTime)
                let entryStartTime = calendar.date(
                    bySettingHour: entryComponents.hour!,
                    minute: entryComponents.minute!,
                    second: entryComponents.second!,
                    of: now
                )!

                let entryEndTime: Date
                if index < entries.count - 1,
                   let nextEntryTime = dateFormatter.date(from: entries[index + 1].start)
                {
                    let nextEntryComponents = calendar.dateComponents([.hour, .minute, .second], from: nextEntryTime)
                    entryEndTime = calendar.date(
                        bySettingHour: nextEntryComponents.hour!,
                        minute: nextEntryComponents.minute!,
                        second: nextEntryComponents.second!,
                        of: now
                    )!
                } else {
                    entryEndTime = calendar.date(byAdding: .day, value: 1, to: entryStartTime)!
                }

                if now >= entryStartTime, now < entryEndTime {
                    await MainActor.run {
                        currentGlucoseTarget = entry.value
                        target = currentGlucoseTarget
                    }
                    return
                }
            }
        }

        /// Configures various settings from the settings manager.
        private func setupSettings() {
            units = settingsManager.settings.units
            useAutoISF = settingsManager.preferences.autoisf
            defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
            defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
            autosensMax = settingsManager.preferences.autosensMax
            settingHalfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
            halfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
            highTTraisesSens = settingsManager.preferences.highTemptargetRaisesSensitivity
            lowTTlowersSens = settingsManager.preferences.lowTemptargetLowersSensitivity
            percentage = TempTargetCalculations.computeAdjustedPercentage(
                halfBasalTarget: halfBasalTarget,
                target: tempTargetTarget,
                autosensMax: autosensMax
            )
            loadAutoISFProfileDefaults()
            requireAdjustmentsConfirmation = settingsManager.settings.requireAdjustmentsConfirmation
            Task {
                await getCurrentGlucoseTarget()
            }
        }

        func loadAutoISFProfileDefaults() {
            let prefs = settingsManager.preferences
            profileAutoISFmin = prefs.autoISFmin
            profileAutoISFmax = prefs.autoISFmax
            profileAutoISFhourlyChange = prefs.autoISFhourlyChange
            profileHigherISFrangeWeight = prefs.higherISFrangeWeight
            profileLowerISFrangeWeight = prefs.lowerISFrangeWeight
            profilePostMealISFweight = prefs.postMealISFweight
            profileBgAccelISFweight = prefs.bgAccelISFweight
            profileBgBrakeISFweight = prefs.bgBrakeISFweight
            profileIobThresholdPercent = prefs.iobThresholdPercent
            profileSmbDeliveryRatio = prefs.smbDeliveryRatio
            profileSmbDeliveryRatioBGrange = prefs.smbDeliveryRatioBGrange
            profileSmbDeliveryRatioMin = prefs.smbDeliveryRatioMin
            profileSmbDeliveryRatioMax = prefs.smbDeliveryRatioMax
            profileEnableBGacceleration = prefs.enableBGacceleration
        }

        /// Reorders Override Presets and updates the view.
        func reorderOverride(from source: IndexSet, to destination: Int) {
            overridePresets.move(fromOffsets: source, toOffset: destination)
            for (index, override) in overridePresets.enumerated() {
                override.orderPosition = Int16(index + 1)
            }
            Task {
                do {
                    guard viewContext.hasChanges else { return }
                    try viewContext.save()
                    setupOverridePresetsArray()
                    try await nightscoutManager.uploadProfiles()
                } catch {
                    debugPrint(
                        "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save Override Presets order or upload profiles"
                    )
                }
            }
        }

        /// Reorders Temp Target Presets and updates the view.
        func reorderTempTargets(from source: IndexSet, to destination: Int) {
            tempTargetPresets.move(fromOffsets: source, toOffset: destination)
            for (index, tempTarget) in tempTargetPresets.enumerated() {
                tempTarget.orderPosition = Int16(index + 1)
            }
            do {
                guard viewContext.hasChanges else { return }
                try viewContext.save()
                setupTempTargetPresetsArray()
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save Temp Target Presets order")
            }
        }
    }
}

// MARK: - Notifications Setup

extension Adjustments.StateModel {
    /// Sets up notification observers for Override and Temp Target updates.
    func setupNotification() {
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOverrideConfigurationUpdate),
            name: .didUpdateOverrideConfiguration,
            object: nil
        )

        // Custom Notification to update View when an Temp Target has been cancelled via Home View
        Foundation.NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTempTargetConfigurationUpdate),
            name: .didUpdateTempTargetConfiguration,
            object: nil
        )

        // Creates a publisher that updates the Override View when the Custom notification was sent (via shortcut)
        Foundation.NotificationCenter.default.publisher(for: .willUpdateOverrideConfiguration)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateLatestOverrideConfiguration()
            }
            .store(in: &cancellables)

        // Creates a publisher that updates the Temp Target View when the Custom notification was sent (via shortcut)
        Foundation.NotificationCenter.default.publisher(for: .willUpdateTempTargetConfiguration)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateLatestTempTargetConfiguration()
                // Also refresh the scheduled-TT list — shortcut-driven scheduling
                // persists a future-dated row that only shows up after a refetch.
                self.setupScheduledTempTargetsArray()
            }
            .store(in: &cancellables)
    }

    /// Handles Override configuration updates.
    @objc private func handleOverrideConfigurationUpdate() {
        updateLatestOverrideConfiguration()
    }

    /// Handles Temp Target configuration updates.
    @objc private func handleTempTargetConfigurationUpdate() {
        updateLatestTempTargetConfiguration()
        // Same as the .willUpdate sink — keep the scheduled list in sync.
        setupScheduledTempTargetsArray()
    }
}

extension Adjustments.StateModel: SettingsObserver, PreferencesObserver {
    /// Updates settings when they change.
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
        requireAdjustmentsConfirmation = settingsManager.settings.requireAdjustmentsConfirmation
        Task {
            await getCurrentGlucoseTarget()
        }
    }

    /// Updates preferences when they change.
    func preferencesDidChange(_: Preferences) {
        useAutoISF = settingsManager.preferences.autoisf
        defaultSmbMinutes = settingsManager.preferences.maxSMBBasalMinutes
        defaultUamMinutes = settingsManager.preferences.maxUAMSMBBasalMinutes
        autosensMax = settingsManager.preferences.autosensMax
        settingHalfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
        halfBasalTarget = settingsManager.preferences.halfBasalExerciseTarget
        highTTraisesSens = settingsManager.preferences.highTemptargetRaisesSensitivity
        lowTTlowersSens = settingsManager.preferences.lowTemptargetLowersSensitivity
        percentage = TempTargetCalculations.computeAdjustedPercentage(
            halfBasalTarget: halfBasalTarget,
            target: tempTargetTarget,
            autosensMax: autosensMax
        )
        Task {
            await getCurrentGlucoseTarget()
        }
    }
}
