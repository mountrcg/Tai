import Combine
import CoreData
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import SwiftDate
import Swinject
import UIKit

protocol FetchGlucoseManager: SourceInfoProvider {
    func updateGlucoseSource(cgmGlucoseSourceType: CGMType, cgmGlucosePluginId: String, newManager: CGMManagerUI?)
    func deleteGlucoseSource() async
    func removeCalibrations()
    func newGlucoseFromCgmManager(newGlucose: [BloodGlucose])
    /// Notes to Nightscout a sensor state without reliable glucose, once per
    /// state; see `CGMSensorStateLog`. Call on every reading.
    func reportCGMSensorObservation(_ observation: CGMSensorObservation)
    func startCGMSensorSession(startedAt: Date)
    var glucoseSource: GlucoseSource? { get }
    var cgmManager: CGMManagerUI? { get }
    var cgmGlucoseSourceType: CGMType { get set }
    var cgmGlucosePluginId: String { get }
    var settingsManager: SettingsManager! { get }
    var shouldSyncToRemoteService: Bool { get }
    var cgmDisplayState: CurrentValueSubject<CgmDisplayState?, Never> { get }
    var cgmProgressHighlight: CurrentValueSubject<DeviceLifecycleProgress?, Never> { get }
    /// Routes CGMManager-issued alerts (sensor failure, signal loss, expiry,
    /// etc.) into the unified `TrioAlertManager` pipeline. Read by
    /// `PluginSource.issueAlert` / `retractAlert`.
    var trioAlertManager: TrioAlertManager! { get }
}

extension FetchGlucoseManager {
    func updateGlucoseSource(cgmGlucoseSourceType: CGMType, cgmGlucosePluginId: String) {
        updateGlucoseSource(cgmGlucoseSourceType: cgmGlucoseSourceType, cgmGlucosePluginId: cgmGlucosePluginId, newManager: nil)
    }
}

final class BaseFetchGlucoseManager: FetchGlucoseManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseManager.processQueue")

    @Injected() var broadcaster: Broadcaster!
    @Injected() var glucoseStorage: GlucoseStorage!
    @Injected() var nightscoutManager: NightscoutManager!
    @Injected() var settingsManager: SettingsManager!
    @Injected() var healthKitManager: HealthKitManager!
    @Injected() var deviceDataManager: DeviceDataManager!
    @Injected() var pluginCGMManager: PluginManager!
    @Injected() var calibrationService: CalibrationService!
    @Injected() var trioAlertManager: TrioAlertManager!
    @Injected() private var deviceLogStore: DeviceLogStore!

    /// Guarded by `sensorStateLock`.
    @Persisted(key: "cgmSensorStateLog") private var sensorStateLog = CGMSensorStateLog()
    private let sensorStateLock = NSRecursiveLock()

    private var lifetime = Lifetime()
    private let timer = DispatchTimer(timeInterval: 1.minutes.timeInterval)
    var cgmGlucoseSourceType: CGMType = .none
    var cgmGlucosePluginId: String = ""
    var cgmManager: CGMManagerUI? {
        didSet {
            rawCGMManager = cgmManager?.rawValue
            UserDefaults.standard.clearLegacyCGMManagerRawValue()
        }
    }

    @PersistedProperty(key: "CGMManagerState") var rawCGMManager: CGMManager.RawValue?

    private lazy var simulatorSource = GlucoseSimulatorSource()

    /// Enforce mutual exclusion on calls to glucoseStoreAndHeartDecision
    private let glucoseStoreAndHeartLock = DispatchSemaphore(value: 1)

    var shouldSyncToRemoteService: Bool {
        guard let cgmManager = cgmManager else {
            return true
        }
        return cgmManager.shouldSyncToRemoteService
    }

    var shouldSmoothGlucose: Bool = false

    init(resolver: Resolver) {
        injectServices(resolver)
        // init at the start of the app
        cgmGlucoseSourceType = settingsManager.settings.cgm
        cgmGlucosePluginId = settingsManager.settings.cgmPluginIdentifier
        // load cgmManager
        updateGlucoseSource(
            cgmGlucoseSourceType: settingsManager.settings.cgm,
            cgmGlucosePluginId: settingsManager.settings.cgmPluginIdentifier
        )
        shouldSmoothGlucose = settingsManager.settings.smoothGlucose
        subscribe()
    }

    /// The function used to start the timer sync - Function of the variable defined in config
    private func subscribe() {
        timer.publisher
            .receive(on: processQueue)
            .flatMap { [self] _ -> AnyPublisher<[BloodGlucose], Never> in
                if let glucoseSource = self.glucoseSource {
                    return glucoseSource.fetch(self.timer).eraseToAnyPublisher()
                } else {
                    return Empty(completeImmediately: false).eraseToAnyPublisher()
                }
            }
            .sink { glucose in
                debug(.cgm, "Glucose source returned \(glucose.count) readings")
                Publishers.CombineLatest(
                    Just(glucose),
                    Just(self.glucoseStorage.syncDate())
                )
                .eraseToAnyPublisher()
                .sink { newGlucose, syncDate in
                    self.glucoseStoreAndHeartLock.wait()
                    Task {
                        do {
                            try await self.glucoseStoreAndHeartDecision(
                                syncDate: syncDate,
                                glucose: newGlucose
                            )
                        } catch {
                            warning(.cgm, "Storing glucose failed", error: error)
                        }
                        self.glucoseStoreAndHeartLock.signal()
                    }
                }
                .store(in: &self.lifetime)
            }
            .store(in: &lifetime)
        timer.fire()
        timer.resume()

        broadcaster.register(SettingsObserver.self, observer: self)
    }

    /// Store new glucose readings from the CGM manager
    ///
    /// This function enables plugin CGM managers to send new glucose readings directly
    /// to the FetchGlucoseManager, bypassing the Combine pipeline. By bypassing the
    /// Combine pipeline CGM managers can send backfill glucose readings, which come
    /// right after a new glucose reading, typically.
    func newGlucoseFromCgmManager(newGlucose: [BloodGlucose]) {
        glucoseStoreAndHeartLock.wait()
        let syncDate = glucoseStorage.syncDate()
        Task {
            do {
                try await glucoseStoreAndHeartDecision(
                    syncDate: syncDate,
                    glucose: newGlucose
                )
            } catch {
                warning(.cgm, "Storing glucose from the CGM failed", error: error)
            }
            glucoseStoreAndHeartLock.signal()
        }
    }

    let cgmDisplayState = CurrentValueSubject<CgmDisplayState?, Never>(nil)
    let cgmProgressHighlight = CurrentValueSubject<DeviceLifecycleProgress?, Never>(nil)
    private var cgmStatusSubscriptions = Set<AnyCancellable>()

    var glucoseSource: GlucoseSource? {
        didSet {
            // Drop prior subscriptions so source swaps don't dupe emissions.
            cgmStatusSubscriptions.removeAll()
            cgmDisplayState.value = glucoseSource?.cgmDisplayState.value
            cgmProgressHighlight.value = glucoseSource?.cgmProgressHighlight.value
            guard let glucoseSource else { return }
            glucoseSource.cgmDisplayState
                .receive(on: DispatchQueue.main)
                .sink { [weak self] state in self?.cgmDisplayState.value = state }
                .store(in: &cgmStatusSubscriptions)
            glucoseSource.cgmProgressHighlight
                .receive(on: DispatchQueue.main)
                .sink { [weak self] progress in self?.cgmProgressHighlight.value = progress }
                .store(in: &cgmStatusSubscriptions)
        }
    }

    func removeCalibrations() {
        calibrationService.removeAllCalibrations()
    }

    func reportCGMSensorObservation(_ observation: CGMSensorObservation) {
        let settings = settingsManager.settings
        guard settings.isUploadEnabled, settings.uploadCGMSensorStates else { return }
        let pending = sensorStateLock.perform { sensorStateLog.observe(observation) }
        guard let pending else { return }

        Task {
            let note = "CGM: " + pending
            if await nightscoutManager.uploadNoteTreatment(note: note) {
                debug(.nightscout, "CGM sensor state uploaded: \(note)")
            } else {
                self.sensorStateLock.perform { self.sensorStateLog.uploadFailed(pending) }
                warning(.nightscout, "CGM sensor state upload failed, will retry: \(note)")
            }
        }
    }

    func startCGMSensorSession(startedAt: Date) {
        sensorStateLock.perform { sensorStateLog.startSensor(startedAt: startedAt) }
    }

    @MainActor func deleteGlucoseSource() async {
        cgmManager = nil
        glucoseSource = nil
        settingsManager.settings.cgm = cgmDefaultModel.type
        settingsManager.settings.cgmPluginIdentifier = cgmDefaultModel.id
        updateGlucoseSource(
            cgmGlucoseSourceType: cgmDefaultModel.type,
            cgmGlucosePluginId: cgmDefaultModel.id
        )
        settingsManager.settings.cgm = cgmDefaultModel.type
        settingsManager.settings.cgmPluginIdentifier = cgmDefaultModel.id
    }

    func saveConfigManager() {
        guard let cgmM = cgmManager else {
            return
        }
        // save the config in rawCGMManager
        rawCGMManager = cgmM.rawValue

        // sync with upload glucose
        settingsManager.settings.uploadGlucose = cgmM.shouldSyncToRemoteService
    }

    private func updateManagerUnits(_ manager: CGMManagerUI?) {
        let units = settingsManager.settings.units
        let managerName = cgmManager.map { "\(type(of: $0))" } ?? "nil"
        let loopkitUnits: HKUnit = units == .mgdL ? .milligramsPerDeciliter : .millimolesPerLiter
        debug(.cgm, "\(managerName) units set to \(loopkitUnits.description)")
        manager?.unitDidChange(to: loopkitUnits)
    }

    func updateGlucoseSource(cgmGlucoseSourceType: CGMType, cgmGlucosePluginId: String, newManager: CGMManagerUI?) {
        // if changed, remove all calibrations
        if self.cgmGlucoseSourceType != cgmGlucoseSourceType || self.cgmGlucosePluginId != cgmGlucosePluginId {
            info(
                .cgm,
                "Glucose source changed to \(cgmGlucoseSourceType.rawValue)\(cgmGlucosePluginId.isEmpty ? "" : ", \(cgmGlucosePluginId)")"
            )
            removeCalibrations()
            cgmManager = nil
            glucoseSource = nil
        }

        self.cgmGlucoseSourceType = cgmGlucoseSourceType
        self.cgmGlucosePluginId = cgmGlucosePluginId

        // if not plugin, manager is not changed and stay with the "old" value if the user come back to previous cgmtype
        // if plugin, if the same pluginID, no change required because the manager is available
        // if plugin, if not the same pluginID, need to reset the cgmManager
        // if plugin and newManager provides, update cgmManager
        if let manager = newManager {
            cgmManager = manager
            removeCalibrations()
        } else if self.cgmGlucoseSourceType == .plugin, cgmManager == nil, let rawCGMManager = rawCGMManager {
            cgmManager = cgmManagerFromRawValue(rawCGMManager)
            updateManagerUnits(cgmManager)

        } else {
            saveConfigManager()
        }

        if glucoseSource == nil {
            switch self.cgmGlucoseSourceType {
            case .none:
                glucoseSource = nil
            case .xdrip:
                glucoseSource = AppGroupSource(from: "xDrip", cgmType: .xdrip)
            case .nightscout:
                glucoseSource = nightscoutManager
            case .simulator:
                glucoseSource = simulatorSource
            case .plugin:
                glucoseSource = PluginSource(
                    glucoseStorage: glucoseStorage,
                    glucoseManager: self,
                    deviceLogStore: deviceLogStore
                )
            }
        }

        // Persist runtime loop/glucose config (loop interval, filter time, minimum glucose)
        if self.cgmGlucoseSourceType == .simulator {
            UserDefaults.standard.set(Config.simulatorLoopInterval, forKey: Config.UserDefaultsKey.loopInterval)
            UserDefaults.standard.set(Config.simulatorFilterTime, forKey: Config.UserDefaultsKey.filterTime)
            UserDefaults.standard.set(Config.simulatorMinimumGlucose, forKey: Config.UserDefaultsKey.minimumGlucose)
        } else {
            UserDefaults.standard.set(Config.defaultLoopInterval, forKey: Config.UserDefaultsKey.loopInterval)
            UserDefaults.standard.set(Config.defaultFilterTime, forKey: Config.UserDefaultsKey.filterTime)
            UserDefaults.standard.set(Config.defaultMinimumGlucose, forKey: Config.UserDefaultsKey.minimumGlucose)
        }

        // Only an active plugin CGM with its own BLE connection can wake the app; otherwise the pump must heartbeat
        let cgmProvidesHeartbeat = cgmGlucoseSourceType == .plugin && (cgmManager?.providesBLEHeartbeat ?? false)
        deviceDataManager.updateCGMHeartbeatCapability(providesBLEHeartbeat: cgmProvidesHeartbeat)
    }

    /// Upload cgmManager from raw value
    func cgmManagerFromRawValue(_ rawValue: [String: Any]) -> CGMManagerUI? {
        guard let rawState = rawValue["state"] as? CGMManager.RawStateValue,
              let Manager = pluginCGMManager.getCGMManagerTypeByIdentifier(cgmGlucosePluginId)
        else {
            return nil
        }
        return Manager.init(rawState: rawState)
    }

    private func glucoseStoreAndHeartDecision(syncDate: Date, glucose: [BloodGlucose]) async throws {
        // calibration add if required only for sensor
        let newGlucose = overcalibrate(entries: glucose.filter { $0.sgv != nil })

        var filteredByDate: [BloodGlucose] = []
        var filtered: [BloodGlucose] = []

        // Start background task
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = startBackgroundTask(withName: "Glucose Store and Heartbeat Decision")

        // Check if sensor emitted calibrations
        let calibrations = glucose.filter { $0.mbg != nil }
        if calibrations.isNotEmpty {
            debug(.cgm, "Storing \(calibrations.count) calibrations")
            try await glucoseStorage.storeGlucose(calibrations)
        }

        guard newGlucose.isNotEmpty else {
            endBackgroundTaskSafely(&backgroundTaskID, taskName: "Glucose Store and Heartbeat Decision")
            return
        }

        let backfillGlucose = newGlucose.filter { $0.dateString <= syncDate }
        var hasBackfilled = false
        if backfillGlucose.isNotEmpty {
            debug(.cgm, "Backfilling \(backfillGlucose.count) glucose readings")
            do {
                try await glucoseStorage.backfillGlucose(backfillGlucose)
                hasBackfilled = true
            } catch {
                warning(.cgm, "Backfilling glucose failed", error: error)
            }
        }

        filteredByDate = newGlucose.filter { $0.dateString > syncDate }
        filtered = glucoseStorage.filterTooFrequentGlucose(filteredByDate, at: syncDate)

        var hasStoredNew = false
        if filtered.isNotEmpty {
            debug(.cgm, "\(filtered.count) new glucose readings found")
            try await glucoseStorage.storeGlucose(filtered)
            hasStoredNew = true
        }

        // Run smoothing if ANY glucose was stored (backfilled or new)
        if (hasBackfilled || hasStoredNew) && settingsManager.settings.smoothGlucose {
            debug(.cgm, "Smoothing glucose, backfilled \(hasBackfilled), new readings stored \(hasStoredNew)")
            // Create a fresh context for smoothing to ensure it sees the latest data from the persistent store
            let smoothingContext = CoreDataStack.shared.newTaskContext()
            smoothingContext.name = "smoothGlucose"
            await smoothGlucose(context: smoothingContext)
        }

        // Only trigger heartbeat if new glucose was stored (not backfill)
        if hasStoredNew {
            // Push the fresh reading schedule so the pump can align its BLE heartbeat
            deviceDataManager.updatePumpBLEHeartbeat(
                lastCGMReadingDate: filtered.map(\.dateString).max(),
                expectedCGMReadingInterval: cgmManager?.expectedGlucoseSampleInterval
            )

            deviceDataManager.heartbeat(date: Date())
        }

        // Always end background task
        guard hasBackfilled || hasStoredNew else {
            endBackgroundTaskSafely(&backgroundTaskID, taskName: "Glucose Store and Heartbeat Decision")
            return
        }

        TelemetryClient.shared.checkAndSendIfOverdueInBackground()

        endBackgroundTaskSafely(&backgroundTaskID, taskName: "Glucose Store and Heartbeat Decision")
    }

    func sourceInfo() -> [String: Any]? {
        glucoseSource?.sourceInfo()
    }

    private func overcalibrate(entries: [BloodGlucose]) -> [BloodGlucose] {
        // overcalibrate
        var overcalibration: ((Int) -> (Double))?

        if let cal = calibrationService {
            overcalibration = cal.calibrate
        }

        if let overcalibration = overcalibration {
            return entries.map { entry in
                var entry = entry
                guard entry.glucose != nil else { return entry }
                entry.glucose = Int(overcalibration(entry.glucose!))
                entry.sgv = Int(overcalibration(entry.sgv!))
                return entry
            }
        } else {
            return entries
        }
    }
}

extension FetchGlucoseManager {
    /// Dispatches given `functionToInvoke` to the CGM manager's queue (if any).
    func performOnCGMManagerQueue(_ functionToInvoke: @escaping () -> Void) {
        // If a CGM manager exists and it defines a delegate queue, use it
        if let cgmManager = self.cgmManager,
           let managerQueue = cgmManager.delegateQueue
        {
            managerQueue.async {
                functionToInvoke()
            }
        } else {
            // If there's no cgmManager or no queue, just run the block immediately
            // This possibly executes `functionToInvoke` on main thread
            functionToInvoke()
        }
    }
}

extension CGMManager {
    typealias RawValue = [String: Any]

    var rawValue: [String: Any] {
        [
            "managerIdentifier": pluginIdentifier,
            "state": rawState
        ]
    }
}

extension BaseFetchGlucoseManager: SettingsObserver {
    /// Smooth glucose data when smoothing is turned on.
    func settingsDidChange(_: TrioSettings) {
        let smoothingWasEnabled = shouldSmoothGlucose
        let smoothingIsEnabled = settingsManager.settings.smoothGlucose
        shouldSmoothGlucose = smoothingIsEnabled

        guard smoothingIsEnabled, !smoothingWasEnabled else { return }

        processQueue.async { [weak self] in
            guard let self else { return }

            self.glucoseStoreAndHeartLock.wait()
            Task {
                // Create a fresh context for smoothing to ensure it sees the latest data
                let smoothingContext = CoreDataStack.shared.newTaskContext()
                smoothingContext.name = "smoothGlucose"
                // One-shot backfill over the full chart history span: activation (or an algorithm
                // change, which forces the toggle off and back on) smooths everything the chart can
                // show, so no visible stretch is left without a smoothed value. The recurring
                // per-cycle passes stay at the default 24h window that algorithm consumers need.
                let fullChartWindowHours = MainChartHelper.Config.maxChartHistorySeconds / 3600
                await self.smoothGlucose(context: smoothingContext, hours: fullChartWindowHours)
                self.glucoseStoreAndHeartLock.signal()
            }
        }
    }
}

extension BaseFetchGlucoseManager {
    func fetchGlucose(context: NSManagedObjectContext, hours: Double = 24) async throws -> [NSManagedObjectID] {
        // Compound predicate: time window + non-manual + valid date
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        let timePredicate = NSPredicate(format: "date >= %@", cutoff as NSDate)
        let manualPredicate = NSPredicate(format: "isManual == NO")
        let datePredicate = NSPredicate(format: "date != nil")

        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            timePredicate,
            manualPredicate,
            datePredicate
        ])

        // Limit sized for 5-min readings (12/h) plus 25% headroom for duplicates/backfills.
        let fetchLimit = Int(hours * 15)

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            // The default window must cover at least the full glucose horizon used by downstream
            // algorithm consumers. If autosens / oref / smoothing logic ever starts looking back
            // further (e.g. 36h), the default must be expanded accordingly.
            // Fetch descending (newest first) so the limit always keeps the most recent readings.
            // Reversed before return so callers receive oldest-first (chronological) order.
            predicate: compoundPredicate,
            key: "date",
            ascending: false,
            fetchLimit: fetchLimit
        )

        guard let glucoseArray = results as? [GlucoseStored] else {
            throw CoreDataError.fetchError(function: #function, file: #file)
        }

        return Array(glucoseArray.map(\.objectID).reversed())
    }

    /// Main smoothing entry point - dispatches to exponential or UKF based on settings.
    /// - Important: Only stores `smoothedGlucose`. UI/alerts should still use `glucose`.
    ///
    func smoothGlucose(context: NSManagedObjectContext, hours: Double = 24) async {
        let algorithm = settingsManager.settings.smoothingAlgorithm
        debug(.cgm, "Smoothing glucose with \(algorithm.displayName) over \(hours) h")

        switch algorithm {
        case .exponential:
            await exponentialSmoothingGlucose(context: context, hours: hours)
        case .ukf:
            await ukfSmoothingGlucose(context: context, hours: hours)
        case .adaptiveUkf:
            await adaptiveUkfSmoothingGlucose(context: context, hours: hours)
        }
    }

    /// CoreData-friendly AAPS exponential smoothing + storage.
    /// - Important: Only stores `smoothedGlucose`. UI/alerts should still use `glucose`.
    ///
    func exponentialSmoothingGlucose(context: NSManagedObjectContext, hours: Double = 24) async {
        let startTime = Date()

        do {
            // get objectIDs
            let objectIDs = try await fetchGlucose(context: context, hours: hours)
            debug(.cgm, "Exponential smoothing fetched \(objectIDs.count) glucose readings")

            try await context.perform(schedule: .immediate) {
                // Load managed objects from object IDs
                // Filtering (isManual, date) already done at DB level in fetchGlucose
                let glucoseReadings = objectIDs.compactMap {
                    context.object(with: $0) as? GlucoseStored
                }

                guard !glucoseReadings.isEmpty else {
                    debug(.cgm, "Exponential smoothing found no usable glucose readings")
                    return
                }

                // Static method call to avoid self-capture
                Self.applyExponentialSmoothingAndStore(
                    glucoseReadings: glucoseReadings,
                    minimumWindowSize: 4,
                    maximumAllowedGapMinutes: 12,
                    xDripErrorGlucose: 38,
                    minimumSmoothedGlucose: 39,
                    firstOrderWeight: 0.4,
                    firstOrderAlpha: 0.5,
                    secondOrderAlpha: 0.4,
                    secondOrderBeta: 1.0
                )

                try context.save()
            }

            // Force viewContext to refresh so UI sees updated smoothed values immediately
            // The viewContext has automaticallyMergesChangesFromParent = false and relies
            // on persistent history tracking, which merges asynchronously
            let viewContext = CoreDataStack.shared.persistentContainer.viewContext
            await viewContext.perform {
                viewContext.refreshAllObjects()
            }

            let duration = Date().timeIntervalSince(startTime)
            debug(.cgm, String(format: "Glucose smoothing took %.3f s", duration))
        } catch {
            warning(.cgm, "Glucose smoothing failed", error: error)
        }
    }

    private static func applyExponentialSmoothingAndStore(
        glucoseReadings data: [GlucoseStored],
        minimumWindowSize: Int,
        maximumAllowedGapMinutes: Int,
        xDripErrorGlucose: Int,
        minimumSmoothedGlucose: Decimal,
        firstOrderWeight: Decimal,
        firstOrderAlpha: Decimal,
        secondOrderAlpha: Decimal,
        secondOrderBeta: Decimal
    ) {
        guard !data.isEmpty else { return }

        // First, set fallback smoothed values for ALL readings
        // This ensures no reading is left with nil smoothedGlucose
        for object in data {
            let raw = Decimal(Int(object.glucose))
            object.smoothedGlucose = max(raw, minimumSmoothedGlucose) as NSDecimalNumber
        }

        // Determine the size of the valid most-recent smoothing window.
        // We walk adjacent pairs from newest -> oldest to preserve the same window semantics
        // as the original implementation, but avoid manual reverse indexing.
        var validWindowCount = max(data.count - 1, 0)

        for (recentOffset, pair) in zip(data.dropFirst().reversed(), data.dropLast().reversed()).enumerated() {
            let (newer, older) = pair

            guard let newerDate = newer.date, let olderDate = older.date else { continue }

            let gapSeconds = newerDate.timeIntervalSince(olderDate)
            let gapMinutesRounded = Int((gapSeconds / 60.0).rounded())
            if gapMinutesRounded >= maximumAllowedGapMinutes {
                validWindowCount = recentOffset + 1 // include the more recent reading
                let dateFormatter = ISO8601DateFormatter()
                debug(
                    .cgm,
                    "Exponential smoothing found a \(gapMinutesRounded) min gap between \(dateFormatter.string(from: olderDate)) and \(dateFormatter.string(from: newerDate)), window \(validWindowCount) readings"
                )
                break
            }

            // Ported from AAPS: 38 mg/dL may represent an xDrip error state.
            if Int(newer.glucose) == xDripErrorGlucose {
                validWindowCount = recentOffset // exclude this 38 value
                debug(
                    .cgm,
                    "Exponential smoothing found xDrip error glucose 38 mg/dL, window \(validWindowCount) readings"
                )
                break
            }
        }

        // Not enough recent contiguous readings to smooth (e.g. after CGM gap).
        // Fallback values already set above, so just return
        guard validWindowCount >= minimumWindowSize else {
            debug(
                .cgm,
                "Exponential smoothing skipped, only \(validWindowCount) of \(minimumWindowSize) readings, keeping raw values"
            )
            return
        }

        // Restrict smoothing to the valid most-recent window, still in chronological order.
        let validWindow = data.suffix(validWindowCount)

        guard let oldest = validWindow.first else { return }

        // ---- 1st order smoothing ----
        var firstOrderSmoothed: [Decimal] = []
        firstOrderSmoothed.reserveCapacity(validWindow.count)

        var firstOrderCurrent = Decimal(Int(oldest.glucose))
        firstOrderSmoothed.append(firstOrderCurrent)

        for sample in validWindow.dropFirst() {
            let raw = Decimal(Int(sample.glucose))
            firstOrderCurrent = firstOrderCurrent + firstOrderAlpha * (raw - firstOrderCurrent)
            firstOrderSmoothed.append(firstOrderCurrent)
        }

        // ---- 2nd order smoothing ----
        let secondOrderInput = Array(validWindow)
        guard secondOrderInput.count >= 2 else { return }

        var secondOrderSmoothed: [Decimal] = []
        secondOrderSmoothed.reserveCapacity(secondOrderInput.count)

        var secondOrderDeltas: [Decimal] = []
        secondOrderDeltas.reserveCapacity(secondOrderInput.count)

        var previousSecondOrderSmoothed = Decimal(Int(secondOrderInput[0].glucose))
        var previousSecondOrderDelta =
            Decimal(Int(secondOrderInput[1].glucose) - Int(secondOrderInput[0].glucose))

        secondOrderSmoothed.append(previousSecondOrderSmoothed)
        secondOrderDeltas.append(previousSecondOrderDelta)

        for sample in secondOrderInput.dropFirst() {
            let raw = Decimal(Int(sample.glucose))

            let nextSmoothed =
                secondOrderAlpha * raw
                    + (1 - secondOrderAlpha) * (previousSecondOrderSmoothed + previousSecondOrderDelta)
            let newLevel = secondOrderAlpha * raw + (1 - secondOrderAlpha) *
                (previousSecondOrderSmoothed + previousSecondOrderDelta)
            let newDelta = secondOrderBeta * (newLevel - previousSecondOrderSmoothed) + (1 - secondOrderBeta) *
                previousSecondOrderDelta

            let nextDelta =
                secondOrderBeta * (nextSmoothed - previousSecondOrderSmoothed)
                    + (1 - secondOrderBeta) * previousSecondOrderDelta

            previousSecondOrderSmoothed = nextSmoothed
            previousSecondOrderDelta = nextDelta

            secondOrderSmoothed.append(nextSmoothed)
            secondOrderDeltas.append(nextDelta)
        }

        // ---- Weighted blend ----
        let blended = zip(firstOrderSmoothed, secondOrderSmoothed).map { firstOrder, secondOrder in
            firstOrderWeight * firstOrder + (1 - firstOrderWeight) * secondOrder
        }

        // Apply to the most recent valid-window readings.
        for (object, blendedValue) in zip(validWindow, blended) {
            let rounded = blendedValue.rounded(toPlaces: 0) // nearest integer, ties away from zero
            let clamped = max(rounded, minimumSmoothedGlucose)
            object.smoothedGlucose = clamped as NSDecimalNumber
        }
        debug(.cgm, "Exponential smoothing stored \(validWindow.count) smoothed values")
    }

    /// UKF-based glucose smoothing + storage.
    /// - Important: Only stores `smoothedGlucose`. UI/alerts should still use `glucose`.
    ///
    private func ukfSmoothingGlucose(context: NSManagedObjectContext, hours: Double = 24) async {
        let startTime = Date()

        do {
            // get objectIDs
            let objectIDs = try await fetchGlucose(context: context, hours: hours)
            let objectIDsCount = objectIDs.count
            debug(.cgm, "UKF smoothing fetched \(objectIDsCount) glucose readings")

            try await context.perform(schedule: .immediate) {
                // Load managed objects from object IDs
                let glucoseReadings = objectIDs.compactMap {
                    context.object(with: $0) as? GlucoseStored
                }

                guard !glucoseReadings.isEmpty else {
                    debug(.cgm, "UKF smoothing found no usable glucose readings")
                    return
                }


                // Convert GlucoseStored to BloodGlucose array
                let bloodGlucoseArray: [BloodGlucose] = glucoseReadings.compactMap { stored -> BloodGlucose? in
                    guard let date = stored.date else { return nil }
                    let direction = stored.direction.flatMap { BloodGlucose.Direction(from: $0) }
                    return BloodGlucose(
                        id: stored.id?.uuidString ?? UUID().uuidString,
                        sgv: Int(stored.glucose),
                        direction: direction,
                        date: Decimal(date.timeIntervalSince1970 * 1000), // milliseconds
                        dateString: date,
                        unfiltered: nil,
                        filtered: nil,
                        noise: nil,
                        glucose: Int(stored.glucose),
                        type: nil,
                        sessionStartDate: nil // UKF can work without sensor session info
                    )
                }

                guard bloodGlucoseArray.count >= 2 else {
                    debug(.cgm, "UKF smoothing skipped, only \(bloodGlucoseArray.count) readings, keeping raw values")
                    // Fallback: set smoothed = raw for insufficient data
                    for reading in glucoseReadings {
                        reading.smoothedGlucose = NSDecimalNumber(value: Int(reading.glucose))
                    }
                    try context.save()
                    return
                }

                // Apply UKF smoothing
                var ukf = UnscentedKalmanFilter()
                let smoothed = ukf.smooth(bloodGlucoseArray)


                // Store smoothed values back to CoreData
                for (idx, bloodGlucose) in smoothed.enumerated() where idx < glucoseReadings.count {
                    if let smoothedValue = bloodGlucose.glucose {
                        glucoseReadings[idx].smoothedGlucose = NSDecimalNumber(value: smoothedValue)
                    } else {
                        // Fallback: if UKF didn't produce a smoothed value, use raw
                        debug(.cgm, "UKF smoothing has no value for reading \(idx), keeping raw value")
                        glucoseReadings[idx].smoothedGlucose = NSDecimalNumber(value: Int(glucoseReadings[idx].glucose))
                    }
                }

                try context.save()
                debug(.cgm, "UKF smoothing stored \(smoothed.count) smoothed values")
            }

            // Force viewContext to refresh so UI sees updated smoothed values immediately
            // The viewContext has automaticallyMergesChangesFromParent = false and relies
            // on persistent history tracking, which merges asynchronously
            let viewContext = CoreDataStack.shared.persistentContainer.viewContext
            await viewContext.perform {
                viewContext.refreshAllObjects()
            }

            let duration = Date().timeIntervalSince(startTime)
            debug(.cgm, String(format: "UKF smoothing took %0.04f s", duration))
        } catch {
            warning(.cgm, "UKF glucose smoothing failed", error: error)
        }
    }

    /// Adaptive UKF glucose smoothing + storage (port of the nightscout/Trio#1302 core).
    /// - Important: Only stores `smoothedGlucose`. UI/alerts should still use `glucose`.
    /// - Note: internal (not private) so the ordering-regression test can drive the production path.
    ///
    func adaptiveUkfSmoothingGlucose(context: NSManagedObjectContext, hours: Double = 24) async {
        let startTime = Date()

        do {
            // get objectIDs (oldest-first, see fetchGlucose)
            let objectIDs = try await fetchGlucose(context: context, hours: hours)
            debug(.cgm, "Adaptive UKF smoothing fetched \(objectIDs.count) glucose readings")

            // IOB timeline for the compression-low gate: Tai re-smooths the full window every
            // run, so each reading is judged with the IOB that was current at its own time
            // (nearest determination ≤30 min before it). Fail-safe: readings without a nearby
            // determination get a large IOB, i.e. gate off — a steep low is always followed,
            // never masked by stale or missing IOB.
            let iobTimeline = await iobTimelineForSmoothing(context: context, hours: hours)

            try await context.perform(schedule: .immediate) {
                let glucoseReadings = objectIDs.compactMap {
                    context.object(with: $0) as? GlucoseStored
                }

                guard glucoseReadings.count >= 2 else {
                    debug(
                        .cgm,
                        "Adaptive UKF smoothing skipped, only \(glucoseReadings.count) readings, keeping raw values"
                    )
                    for reading in glucoseReadings {
                        reading.smoothedGlucose = NSDecimalNumber(value: Int(reading.glucose))
                    }
                    try context.save()
                    return
                }

                // The engine requires NEWEST-first input; fetchGlucose returns oldest-first.
                // Reverse once and keep readings/timestamps aligned for the write-back.
                let newestFirst = Array(glucoseReadings.reversed())
                let input = newestFirst.map { stored in
                    AdaptiveUKFGlucoseValue(
                        timestamp: Int64((stored.date ?? Date()).timeIntervalSince1970 * 1000),
                        value: Double(stored.glucose)
                    )
                }

                // AAPS feeds its smoother 5-min-BUCKETED data, not raw readings. Bucketing regularises
                // sub-2-min-spaced backfills/catch-ups onto a 5-min grid, which stops `findDataSegments`
                // from breaking the segment and re-initialising the filter from a raw value (the
                // "V-spike" glitch). Pure preprocessing — the smoother core is untouched.
                let bucketed = GlucoseBucketing.bucketed(input)

                let engine = AdaptiveUKFSmoother(iobAt: { timestamp in
                    Self.iobAt(timestamp, in: iobTimeline)
                })
                let grid = engine.smooth(bucketed)

                // Write-back: AAPS displays bucketed data directly, but Trio stores `smoothedGlucose`
                // per `GlucoseStored` row (oref doses off `recalculated = smoothed ?? value`), so each
                // raw row samples the smoothed grid at its own timestamp by linear interpolation.
                // Store as integer mg/dL, consistent with the raw values and the other algorithms;
                // fractional filter output is false precision for oref, which rounds on read anyway.
                for (stored, value) in zip(newestFirst, input) {
                    // `Int(_: Double)` traps on NaN/infinity, so a non-finite filter output would kill the
                    // app rather than degrade. Fall back to the raw reading, which is what oref uses when
                    // `smoothedGlucose` is unset anyway.
                    let interpolated = GlucoseBucketing.interpolatedSmoothed(at: value.timestamp, grid: grid)
                    let smoothed = interpolated.flatMap { $0.isFinite ? $0 : nil } ?? value.value
                    stored.smoothedGlucose = NSDecimalNumber(value: Int(max(smoothed, 39.0).rounded()))
                }

                try context.save()
                debug(
                    .cgm,
                    "Adaptive UKF smoothing stored \(newestFirst.count) smoothed values from \(bucketed.count) buckets"
                )
            }

            // Force viewContext to refresh so UI sees updated smoothed values immediately
            // The viewContext has automaticallyMergesChangesFromParent = false and relies
            // on persistent history tracking, which merges asynchronously
            let viewContext = CoreDataStack.shared.persistentContainer.viewContext
            await viewContext.perform {
                viewContext.refreshAllObjects()
            }

            let duration = Date().timeIntervalSince(startTime)
            debug(.cgm, String(format: "Adaptive UKF smoothing took %0.04f s", duration))
        } catch {
            warning(.cgm, "Adaptive UKF glucose smoothing failed", error: error)
        }
    }

    /// IOB timeline for the Adaptive UKF compression gate: `(timestamp ms, iob)` pairs from the
    /// determinations covering the smoothing window, sorted ascending by time. Empty on fetch
    /// failure (every lookup then fails safe to gate-off).
    private func iobTimelineForSmoothing(
        context: NSManagedObjectContext,
        hours: Double
    ) async -> [(timestamp: Int64, iob: Double)] {
        do {
            // Matches the glucose fetch window; determinations up to 30 min older can still gate
            // the oldest reading, hence the extra half hour.
            let cutoff = Date().addingTimeInterval(-(hours + 0.5) * 3600)
            let results = try await CoreDataStack.shared.fetchEntitiesAsync(
                ofType: OrefDetermination.self,
                onContext: context,
                predicate: NSPredicate(format: "deliverAt >= %@", cutoff as NSDate),
                key: "deliverAt",
                ascending: true
            )

            return await context.perform {
                guard let determinations = results as? [OrefDetermination] else { return [] }
                return determinations.compactMap { determination in
                    guard let deliverAt = determination.deliverAt, let iob = determination.iob else { return nil }
                    return (Int64(deliverAt.timeIntervalSince1970 * 1000), iob.doubleValue)
                }
            }
        } catch {
            warning(.cgm, "Adaptive UKF smoothing could not fetch IOB, compression detection off", error: error)
            return []
        }
    }

    /// IOB (units) at a reading time: the latest determination at or before `timestamp` that is at
    /// most 30 minutes older. No such determination (loop outage, app not running) returns a large
    /// value, i.e. compression gate off for that reading.
    private static func iobAt(_ timestamp: Int64, in timeline: [(timestamp: Int64, iob: Double)]) -> Double {
        let maxAgeMs: Int64 = 30 * 60000

        // Binary search: last entry with entry.timestamp <= timestamp.
        var low = 0
        var high = timeline.count
        while low < high {
            let mid = (low + high) / 2
            if timeline[mid].timestamp <= timestamp {
                low = mid + 1
            } else {
                high = mid
            }
        }
        guard low > 0 else { return 99.0 }

        let entry = timeline[low - 1]
        guard timestamp - entry.timestamp <= maxAgeMs else { return 99.0 }
        return entry.iob
    }
}
