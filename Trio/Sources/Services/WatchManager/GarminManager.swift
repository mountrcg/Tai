import Combine
import ConnectIQ
import CoreData
import Foundation
import Swinject

// MARK: - GarminManager Protocol

/// Manages Garmin devices, allowing the app to select devices, update a known device list,
/// and send watch-state data to connected Garmin watch apps.
protocol GarminManager {
    /// Prompts the user to select Garmin devices, returning the chosen devices in a publisher.
    /// - Returns: A publisher that eventually outputs an array of selected `IQDevice` objects.
    func selectDevices() -> AnyPublisher<[IQDevice], Never>

    /// Updates the currently tracked device list. This typically persists the device list and
    /// triggers re-registration for any relevant ConnectIQ events.
    /// - Parameter devices: The new array of `IQDevice` objects to track.
    func updateDeviceList(_ devices: [IQDevice])

    /// Takes raw JSON-encoded watch-state data and dispatches it to any connected watch apps.
    /// - Parameter data: The JSON-encoded data representing the watch state.
    func sendWatchStateData(_ data: Data)

    /// The devices currently known to the app. May be loaded from disk or user selection.
    var devices: [IQDevice] { get }
}

// MARK: - BaseGarminManager

/// Concrete implementation of `GarminManager` that handles:
///  - Device registration/unregistration with Garmin ConnectIQ
///  - Data persistence for selected devices
///  - Generating & sending watch-state updates (glucose, IOB, COB, etc.) to Garmin watch apps.
final class BaseGarminManager: NSObject, GarminManager, Injectable {
    // MARK: - Dependencies & Properties

    /// Observes system-wide notifications, including `.openFromGarminConnect`.
    @Injected() private var notificationCenter: NotificationCenter!

    /// Broadcaster used for publishing or subscribing to global events (e.g., unit changes).
    @Injected() private var broadcaster: Broadcaster!

    /// APSManager containing insulin pump logic, e.g., for making bolus requests, reading basal info, etc.
    @Injected() private var apsManager: APSManager!

    /// Manages local user settings, such as glucose units (mg/dL or mmol/L).
    @Injected() private var settingsManager: SettingsManager!

    /// Stores, retrieves, and updates glucose data in CoreData.
    @Injected() private var glucoseStorage: GlucoseStorage!

    /// Stores, retrieves, and updates insulin dose determinations in CoreData.
    @Injected() private var determinationStorage: DeterminationStorage!

    @Injected() private var iobService: IOBService!

    /// Persists the user's device list between app launches.
    @Persisted(key: "BaseGarminManager.persistedDevices") private var persistedDevices: [GarminDevice] = []

    /// Router for presenting alerts or navigation flows (injected via Swinject).
    private let router: Router

    /// Garmin ConnectIQ shared instance for watch interactions.
    private let connectIQ = ConnectIQ.sharedInstance()

    /// Keeps references to watch apps (both watchface & data field) for each registered device.
    private var watchApps: [IQApp] = []

    /// A set of Combine cancellables for managing the lifecycle of various subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Holds a promise used when the user is selecting devices (via `showDeviceSelection()`).
    private var deviceSelectionPromise: Future<[IQDevice], Never>.Promise?

    /// Subject for debouncing watch state updates. Carries data and an optional target app UUID
    /// (nil = broadcast to all, non-nil = send only to that app).
    private let watchStateSubject = PassthroughSubject<(Data, UUID?), Never>()

    /// Current glucose units, either mg/dL or mmol/L, read from user settings.
    private var units: GlucoseUnits = .mgdL

    // MARK: - Debug Logging

    /// Enable/disable watch state preparation and throttling logs:
    /// - Glucose/IOB received, waiting for determination
    /// - Determination arrived, cancelled timer
    /// - Preparing/Prepared watch state, Skipping - data unchanged
    /// - Settings throttle timer started/running/fired
    private let debugWatchState = true

    /// Enable/disable watch status and communication logs:
    /// - Device status changes (connected, notConnected, etc.)
    /// - Registered watchface/datafield
    /// - Sending to / Successfully sent
    /// - Watchface/datafield config changed
    private let debugGarminEnabled = true

    /// Helper method for conditional watch status/comms logging.
    /// Logs messages only if debugGarminEnabled is true.
    /// - Parameter message: The debug message to log.
    private func debugGarmin(_ message: String) {
        guard debugGarminEnabled else { return }
        debug(.watchManager, message)
    }

    // MARK: - Device Ready State (SDK 1.8+)

    /// Tracks which devices have completed characteristic discovery and are ready for communication.
    /// In SDK 1.8+, `deviceStatusChanged: connected` does NOT mean the device is ready.
    /// We must wait for `deviceCharacteristicsDiscovered:` before sending messages.
    private var readyDevices: Set<UUID> = []

    // MARK: - Deduplication

    /// Hash of last sent data to prevent duplicate broadcasts
    private var lastSentDataHash: Int?

    /// Hash of last prepared data to skip redundant preparation
    private var lastPreparedDataHash: Int?
    private var lastPreparedWatchState: [GarminWatchState]?

    // MARK: - Glucose/Determination Coordination

    /// Delay before sending glucose if determination hasn't arrived (seconds)
    /// Based on log analysis: avg delay ~5s, max ~11s with new timer coordination
    private let glucoseFallbackDelay: TimeInterval = 10

    /// Pending glucose fallback task - cancelled if determination arrives first
    private var pendingGlucoseFallback: DispatchWorkItem?

    /// Queue for glucose fallback timer
    private let timerQueue = DispatchQueue(label: "BaseGarminManager.timerQueue", qos: .utility)

    // MARK: - Settings Change Throttle

    /// Track previous Garmin settings to detect what specifically changed
    private var previousGarminSettings = GarminWatchSettings()

    /// Pending settings update task - waits for user to finish making changes
    private var pendingSettingsUpdate: DispatchWorkItem?

    /// Latest settings data to send when throttle timer fires
    private var pendingSettingsData: Data?

    /// How long to wait for additional settings changes before sending (seconds)
    private let settingsThrottleDuration: TimeInterval = 10

    // MARK: - Watchface Activity Tracking

    /// Tracks when the watchface last sent a "status" request (keep-alive).
    /// Used to detect if watch background service is active and receiving messages.
    private var lastWatchfaceRequestTime: Date?

    /// How long since last watchface request before we consider it inactive (seconds).
    /// If no request in this period, we skip sending to avoid queue buildup.
    /// Note: Watch OS naturally suspends watchface background during activities,
    /// so this timeout handles both normal inactivity and activity-based suppression.
    private let watchfaceActiveTimeout: TimeInterval = 5 * 60 // 5 minutes

    /// Tracks if watchface is suppressed because datafield is active (user in activity).
    /// When datafield sends request → watchface suppressed (Garmin OS suspends it during activities)
    /// When watchface sends request → activity ended, immediately send fresh data
    private var watchfaceSuppressedDuringActivity: Bool = false

    /// Tracks when the datafield last sent a status request.
    /// Used as fallback to detect activity end when no watchface is installed.
    private var lastDatafieldRequestTime: Date?

    /// How long since last datafield request before we assume activity ended (seconds).
    /// Fallback for when no watchface is installed to detect "activity ended".
    private let datafieldInactiveTimeout: TimeInterval = 15 * 60 // 15 minutes

    // MARK: - BLE Flapping Detection

    /// Tracks recent connection state changes for flapping detection.
    /// Format: (timestamp, isConnected) where isConnected distinguishes connected vs disconnected states.
    private var connectionStateHistory: [(Date, Bool)] = []

    /// How many disconnects within the detection window constitutes flapping.
    /// Based on log analysis (Feb 06, Feb 12): flapping shows 4+ disconnects in rapid succession.
    private let flappingThreshold: Int = 4

    /// Time window for detecting flapping (seconds).
    /// Based on log analysis: problematic flapping occurs within 30 seconds (Feb 12: 6 changes in 15s).
    private let flappingDetectionWindow: TimeInterval = 30

    /// Maximum gap between consecutive state changes to be considered "rapid" (seconds).
    /// Based on log analysis: Feb 06 had 1-2s gaps, Feb 12 had 0-4s gaps during flapping.
    private let rapidTransitionThreshold: TimeInterval = 5

    /// How many consecutive rapid disconnects indicates flapping.
    /// Based on log analysis: 3+ rapid disconnects in a row is a strong flapping indicator.
    private let consecutiveRapidThreshold: Int = 3

    /// How long the connection must remain stable after flapping before re-registration (seconds).
    /// Gives time for BLE to fully stabilize before attempting recovery.
    private let flappingStabilizationTime: TimeInterval = 30

    /// When flapping was last detected (used to trigger re-registration after stabilization).
    private var lastFlappingDetectedTime: Date?

    /// Pending re-registration work item after flapping stabilizes.
    private var pendingFlappingReregistration: DispatchWorkItem?

    /// Track if we're currently in a flapping state.
    private var isFlapping: Bool = false

    /// Track if we've already triggered re-registration for the current flapping episode.
    /// Prevents multiple re-registrations for a single flapping event.
    private var hasTriggeredFlappingReregistration: Bool = false

    // MARK: - Missed Status Request Detection (Pattern 3)

    /// Expected interval between watchface status requests (seconds).
    /// Watchface polls every 5 minutes when active.
    private let expectedStatusRequestInterval: TimeInterval = 5 * 60

    /// Number of missed status requests before triggering proactive recovery.
    /// 3 missed = 15 minutes of silence, recovery triggers 30s before 4th would be missed.
    private let missedRequestThreshold: Int = 3

    /// How long before the next expected request to trigger recovery (seconds).
    /// Gives time for re-registration to complete before the watchface would poll again.
    private let proactiveRecoveryLeadTime: TimeInterval = 30

    /// Pending proactive recovery work item for missed status requests.
    private var pendingProactiveRecovery: DispatchWorkItem?

    /// Track if proactive recovery has been triggered for the current silence period.
    /// Resets when a status request is received.
    private var hasTriggeredProactiveRecovery: Bool = false

    // MARK: - CoreData & Subscriptions

    /// Queue for handling Core Data change notifications
    private let queue = DispatchQueue(label: "BaseGarminManager.queue", qos: .utility)

    /// Publishes any changed CoreData objects that match our filters (e.g., OrefDetermination, GlucoseStored).
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?

    /// Additional local subscriptions (separate from `cancellables`) for CoreData events.
    private var subscriptions = Set<AnyCancellable>()

    /// Represents the context for background tasks in CoreData.
    let backgroundContext = CoreDataStack.shared.newTaskContext()

    /// Represents the main (view) context for CoreData, typically used on the main thread.
    let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    /// Array of Garmin `IQDevice` objects currently tracked.
    /// Changing this property triggers re-registration and updates persisted devices.
    private(set) var devices: [IQDevice] = [] {
        didSet {
            // Persist newly updated device list
            persistedDevices = devices.map(GarminDevice.init)
            // Re-register for events, app messages, etc.
            registerDevices(devices)
        }
    }

    // MARK: - Initialization

    /// Creates a new `BaseGarminManager`, injecting required services, restoring any persisted devices,
    /// and setting up watchers for data changes (e.g., glucose updates).
    /// - Parameter resolver: Swinject resolver for injecting dependencies like the Router.
    init(resolver: Resolver) {
        router = resolver.resolve(Router.self)!
        super.init()
        injectServices(resolver)

        connectIQ?.initialize(withUrlScheme: "Trio", uiOverrideDelegate: self)

        restoreDevices()

        subscribeToOpenFromGarminConnect()
        subscribeToWatchState()

        units = settingsManager.settings.units
        previousGarminSettings = settingsManager.settings.garminSettings

        broadcaster.register(SettingsObserver.self, observer: self)

        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        // Glucose updates - start 20s fallback timer
        // When loop is working: determination arrives within ~5s, cancels timer, sends complete data
        // When loop is slow/failing: timer fires after 20s, sends glucose with stale loop data
        // This ensures watch gets fresh glucose even if loop doesn't complete
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                self?.handleGlucoseUpdate()
            }
            .store(in: &subscriptions)

        // IOB updates - also wait for determination like glucose does
        iobService.iobPublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                self?.handleIOBUpdate()
            }
            .store(in: &subscriptions)

        registerHandlers()
    }

    // MARK: - Settings Helpers

    /// Returns the currently configured Garmin watchface from settings
    private var currentWatchface: GarminWatchface {
        settingsManager.settings.garminSettings.watchface
    }

    /// Returns the currently configured Garmin datafield from settings
    private var currentDatafield: GarminDatafield {
        settingsManager.settings.garminSettings.datafield
    }

    /// Returns whether watchface data transmission is enabled in settings
    private var isWatchfaceDataEnabled: Bool {
        settingsManager.settings.garminSettings.isWatchfaceDataEnabled
    }

    /// Returns whether smart message switching is enabled in settings.
    /// When enabled, automatically switches between watchface and datafield based on activity detection.
    /// When disabled, broadcasts to all configured apps simultaneously.
    private var isSmartMessageSwitchingEnabled: Bool {
        settingsManager.settings.garminSettings.smartGarminMessageSwitching
    }

    /// SwissAlpine watchface uses historical glucose data (24 entries)
    /// Trio watchface only uses current reading
    private var needsHistoricalGlucoseData: Bool {
        currentWatchface == .swissalpine
    }

    /// Returns the display name for an app UUID (watchface or datafield).
    /// Use this for routine log messages where UUID adds noise.
    private func appDisplayName(for uuid: UUID) -> String {
        if uuid == currentWatchface.watchfaceUUID {
            return "watchface:\(currentWatchface.displayName)"
        } else if uuid == currentDatafield.datafieldUUID {
            return "datafield:\(currentDatafield.displayName)"
        } else {
            return "unknown app"
        }
    }

    /// Returns the detailed display name including UUID for an app.
    /// Use this for registration/connection messages and error scenarios where UUID identification is valuable.
    /// This helps with debugging when multiple versions/distributions exist (local, test, live builds).
    private func appDetailedName(for uuid: UUID) -> String {
        if uuid == currentWatchface.watchfaceUUID {
            return "watchface:\(currentWatchface.displayName) (\(uuid.uuidString))"
        } else if uuid == currentDatafield.datafieldUUID {
            return "datafield:\(currentDatafield.displayName) (\(uuid.uuidString))"
        } else {
            return "unknown app (\(uuid.uuidString))"
        }
    }

    // MARK: - Internal Setup / Handlers

    /// Sets up handlers for OrefDetermination and GlucoseStored entity changes in CoreData.
    /// When these change, we re-compute the Garmin watch state and send updates to the watch.
    private func registerHandlers() {
        // OrefDetermination changes - debounce at CoreData level
        coreDataPublisher?
            .filteredByEntityName("OrefDetermination")
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.triggerWatchStateUpdate(triggeredBy: "Determination")
            }
            .store(in: &subscriptions)

        // GlucoseStored changes - catches single glucose inserts that updatePublisher misses
        // (updatePublisher only fires for batch inserts, not single glucose readings)
        // Debounce at subscriber level to collapse multiple rapid CoreData notifications into one
        coreDataPublisher?
            .filteredByEntityName("GlucoseStored")
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleGlucoseUpdate()
            }
            .store(in: &subscriptions)
    }

    /// Handles glucose updates with delayed fallback
    /// Waits up to 10 seconds for determination to arrive before sending glucose-only update
    /// This ensures we send complete data when loop is working, but still update watch if loop is slow/failing
    private func handleGlucoseUpdate() {
        guard !devices.isEmpty else { return }

        // Cancel any existing fallback timer
        pendingGlucoseFallback?.cancel()

        // Create new fallback task
        let fallback = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            Task {
                do {
                    if self.debugWatchState {
                        debug(
                            .watchManager,
                            "Garmin: Glucose fallback timer fired (no determination in \(Int(self.glucoseFallbackDelay))s)"
                        )
                    }

                    let watchState = try await self.setupGarminWatchState(triggeredBy: "Glucose")
                    let watchStateData = try JSONEncoder().encode(watchState)
                    self.watchStateSubject.send((watchStateData, nil))
                } catch {
                    debug(.watchManager, "Garmin: Error in glucose fallback: \(error)")
                }
            }
        }

        pendingGlucoseFallback = fallback
        timerQueue.asyncAfter(deadline: .now() + glucoseFallbackDelay, execute: fallback)

        if debugWatchState {
            debug(.watchManager, "Garmin: Glucose received - waiting \(Int(glucoseFallbackDelay))s for determination")
        }
    }

    /// Handles IOB updates with delayed fallback
    /// Also waits up to 10 seconds for determination to arrive, restarting the shared timer
    /// This prevents IOB changes from triggering premature watch updates before determination arrives
    private func handleIOBUpdate() {
        guard !devices.isEmpty else { return }

        // Cancel any existing fallback timer (restart the 20s window)
        pendingGlucoseFallback?.cancel()

        // Create new fallback task
        let fallback = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            Task {
                do {
                    if self.debugWatchState {
                        debug(
                            .watchManager,
                            "Garmin: IOB fallback timer fired (no determination in \(Int(self.glucoseFallbackDelay))s)"
                        )
                    }

                    let watchState = try await self.setupGarminWatchState(triggeredBy: "IOB")
                    let watchStateData = try JSONEncoder().encode(watchState)
                    self.watchStateSubject.send((watchStateData, nil))
                } catch {
                    debug(.watchManager, "Garmin: Error in IOB fallback: \(error)")
                }
            }
        }

        pendingGlucoseFallback = fallback
        timerQueue.asyncAfter(deadline: .now() + glucoseFallbackDelay, execute: fallback)

        if debugWatchState {
            debug(.watchManager, "Garmin: IOB received - waiting \(Int(glucoseFallbackDelay))s for determination")
        }
    }

    /// Triggers watch state preparation and sends to debounce subject.
    /// If triggered by Determination, cancels pending glucose fallback timer.
    /// - Parameters:
    ///   - trigger: Description of what triggered this update (for logging).
    ///   - targetAppUUID: If provided, only send to this app. If nil, broadcast to all.
    private func triggerWatchStateUpdate(triggeredBy trigger: String, targetAppUUID: UUID? = nil) {
        guard !devices.isEmpty else { return }

        // If determination arrived, cancel the glucose fallback timer
        // Determination includes both fresh glucose and loop data
        if trigger == "Determination" {
            if pendingGlucoseFallback != nil {
                pendingGlucoseFallback?.cancel()
                pendingGlucoseFallback = nil
                if debugWatchState {
                    debug(.watchManager, "Garmin: Determination arrived - cancelled glucose fallback timer")
                }
            }
        }

        Task {
            do {
                let watchState = try await setupGarminWatchState(triggeredBy: trigger)
                let watchStateData = try JSONEncoder().encode(watchState)
                watchStateSubject.send((watchStateData, targetAppUUID))
            } catch {
                debug(.watchManager, "Garmin: Error preparing watch state (\(trigger)): \(error)")
            }
        }
    }

    /// Sends settings update with throttle - waits for user to finish making changes
    /// If timer already running, just updates data without rescheduling
    /// When timer fires, sends the latest collected data
    private func sendSettingsUpdateThrottled() {
        guard !devices.isEmpty else { return }

        // If timer already scheduled, just log and return - data will be fresh when timer fires
        if pendingSettingsUpdate != nil {
            if debugWatchState {
                debug(.watchManager, "Garmin: Settings throttle timer running, waiting for more changes")
            }
            return
        }

        // Create new throttled task
        let throttledTask = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            if self.debugWatchState {
                debug(.watchManager, "Garmin: Settings throttle timer fired - sending update")
            }

            Task {
                do {
                    let watchState = try await self.setupGarminWatchState(triggeredBy: "Settings")
                    let watchStateData = try JSONEncoder().encode(watchState)
                    self.watchStateSubject.send((watchStateData, nil))
                } catch {
                    debug(.watchManager, "Garmin: Error preparing settings watch state: \(error)")
                }
            }

            // Clean up
            self.pendingSettingsUpdate = nil
            self.pendingSettingsData = nil
        }

        pendingSettingsUpdate = throttledTask
        timerQueue.asyncAfter(deadline: .now() + settingsThrottleDuration, execute: throttledTask)

        if debugWatchState {
            debug(.watchManager, "Garmin: Settings throttle timer started (\(Int(settingsThrottleDuration))s)")
        }
    }

    // MARK: - CoreData Fetch Methods

    /// Fetches recent glucose readings from CoreData, up to specified limit.
    /// - Parameter limit: Maximum number of glucose entries to fetch (default: 2)
    /// - Returns: An array of `NSManagedObjectID`s for glucose readings.
    private func fetchGlucose(limit: Int = 2) async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: false,
            fetchLimit: limit
        )

        return try await backgroundContext.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetchedResults.map(\.objectID)
        }
    }

    /// Fetches the most recent temporary basal rate from CoreData pump history.
    /// - Returns: An array containing the NSManagedObjectID of the latest temp basal event, if any.
    private func fetchTempBasals() async throws -> [NSManagedObjectID] {
        let tempBasalPredicate = NSPredicate(format: "tempBasal != nil")
        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate.pumpHistoryLast24h,
            tempBasalPredicate
        ])

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: backgroundContext,
            predicate: compoundPredicate,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1
        )

        return try await backgroundContext.perform {
            guard let pumpEvents = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return pumpEvents.map(\.objectID)
        }
    }

    /// Fetches all determinations from the last 30 minutes (no fetch limit).
    /// Returns them sorted newest first, allowing us to find both enacted and suggested determinations.
    /// - Returns: An array of `NSManagedObjectID`s for all determinations in the 30-minute window.
    private func fetchDeterminations30Min() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: backgroundContext,
            predicate: NSPredicate.predicateFor30MinAgoForDetermination,
            key: "deliverAt",
            ascending: false,
            fetchLimit: 0 // No limit - get all determinations in 30min window
        )

        return try await backgroundContext.perform {
            guard let fetchedResults = results as? [OrefDetermination] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetchedResults.map(\.objectID)
        }
    }

    // MARK: - Watch State Setup

    /// Builds an array of GarminWatchState objects containing current glucose, trend, loop data, and historical readings.
    /// Historical data is included for watchfaces that support it (e.g., SwissAlpine).
    /// - Parameter triggeredBy: A string describing what triggered this update (for debugging/logging).
    /// - Returns: An array of `GarminWatchState` objects with the latest watch data.
    func setupGarminWatchState(triggeredBy: String = #function) async throws -> [GarminWatchState] {
        // Skip if no devices connected
        guard !devices.isEmpty else {
            return []
        }

        let shouldDebug = debugWatchState
        if shouldDebug {
            debug(.watchManager, "Garmin: Preparing watch state [Trigger: \(triggeredBy)]")
        }

        // Extract all needed values from self before entering perform block (Sendable compliance)
        let unitsValue = units
        let iobValue = formatIOB(iobService.currentIOB ?? Decimal(0))
        let basalProfile = settingsManager.preferences.basalProfile as? [BasalProfileEntry] ?? []
        let displayPrimaryChoice = settingsManager.settings.garminSettings.primaryAttributeChoice.rawValue
        let displaySecondaryChoice = settingsManager.settings.garminSettings.secondaryAttributeChoice.rawValue
        let needsHistoricalData = needsHistoricalGlucoseData
        let previousHash = lastPreparedDataHash
        let previousWatchState = lastPreparedWatchState

        // Fetch glucose - SwissAlpine needs 24, Trio needs 2 (for delta calculation)
        let glucoseLimit = needsHistoricalData ? 24 : 2
        let glucoseIds = try await fetchGlucose(limit: glucoseLimit)

        // Fetch all determinations from last 30 minutes (no limit)
        // This ensures we get both enacted and suggested determinations
        let allDeterminationIds = try await fetchDeterminations30Min()

        let tempBasalIds = try await fetchTempBasals()

        // Capture context locally for use in perform block
        let context = backgroundContext

        // Single perform block: Fetch objects from IDs and extract all values
        // All self properties extracted above to avoid capturing non-Sendable BaseGarminManager
        let watchStates: [GarminWatchState] = await context.perform {
            // Fetch Core Data objects inside perform block
            let glucoseObjects = glucoseIds.compactMap { context.object(with: $0) as? GlucoseStored }
            let allDeterminationObjects = allDeterminationIds.compactMap {
                context.object(with: $0) as? OrefDetermination
            }
            let tempBasalObjects = tempBasalIds.compactMap { context.object(with: $0) as? PumpEventStored }
            var states: [GarminWatchState] = []

            let unitsHint = unitsValue == .mgdL ? "mgdl" : "mmol"

            // Find enacted determination for timestamp (when loop actually ran)
            // If no enacted determination exists in last 30 min, use a synthetic timestamp
            // of "31 minutes ago" so watchface can distinguish between:
            //   - nil = no data received yet (watch startup)
            //   - 31+ min old = loop is stale
            let enactedDetermination = allDeterminationObjects.first(where: { $0.enacted })
            let enactedTimestamp: Date = enactedDetermination?.timestamp ?? Date().addingTimeInterval(-31 * 60)

            // Extract data values from most recent determination (enacted or suggested)
            // Suggested sets provide latest calculations even if loop hasn't run yet
            var cobValue: Double?
            var sensRatioValue: Double?
            var isfValue: Int16?
            var eventualBGValue: Int16?

            if let latestDetermination = allDeterminationObjects.first {
                cobValue = Double(latestDetermination.cob)

                if let ratio = latestDetermination.autoISFratio {
                    sensRatioValue = Double(truncating: ratio)
                }

                if let isf = latestDetermination.insulinSensitivity {
                    isfValue = Int16(truncating: isf)
                }

                if let eventualBG = latestDetermination.eventualBG {
                    eventualBGValue = Int16(truncating: eventualBG)
                }
            }

            // TBR from temp basal or profile
            var tbrValue: Double?
            if let firstTempBasal = tempBasalObjects.first,
               let tempBasalData = firstTempBasal.tempBasal,
               let tempRate = tempBasalData.rate
            {
                tbrValue = Double(truncating: tempRate)
            } else {
                // Fall back to scheduled basal from profile
                if !basalProfile.isEmpty {
                    let now = Date()
                    let calendar = Calendar.current
                    let currentTimeMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

                    for entry in basalProfile.reversed() {
                        if entry.minutes <= currentTimeMinutes {
                            tbrValue = Double(entry.rate)
                            break
                        }
                    }
                }
            }

            // Process glucose readings
            let entriesToSend = needsHistoricalData ? glucoseObjects.count : 1

            for (index, glucose) in glucoseObjects.enumerated() {
                guard index < entriesToSend else { break }

                let glucoseValue = glucose.glucose

                var watchState = GarminWatchState()

                // Loop timestamp: Only use enacted determination timestamp (never glucose timestamp)
                // This shows when the loop actually executed, not when glucose was received
                if index == 0 {
                    watchState.date = UInt64(enactedTimestamp.timeIntervalSince1970 * 1000)
                } else {
                    watchState.date = glucose.date.map { UInt64($0.timeIntervalSince1970 * 1000) }
                }

                watchState.sgv = glucoseValue

                // Only add extended data for first entry
                if index == 0 {
                    watchState.direction = glucose.direction ?? "--"

                    // Delta calculation
                    if glucoseObjects.count > 1 {
                        watchState.delta = glucose.glucose - glucoseObjects[1].glucose
                    } else {
                        watchState.delta = 0
                    }

                    // Glucose timestamp: Used by watchface to determine if glucose is fresh
                    // Enables green coloring when: enacted loop is 6+ min old but glucose is <10 min old
                    watchState.glucoseDate = glucose.date.map { UInt64($0.timeIntervalSince1970 * 1000) }

                    watchState.units_hint = unitsHint
                    watchState.iob = iobValue
                    watchState.cob = cobValue
                    watchState.tbr = tbrValue
                    watchState.isf = isfValue
                    watchState.eventualBG = eventualBGValue
                    watchState.sensRatio = sensRatioValue
                    watchState.displayPrimaryAttributeChoice = displayPrimaryChoice
                    watchState.displaySecondaryAttributeChoice = displaySecondaryChoice
                }

                states.append(watchState)
            }

            return states
        }

        // Deduplicate: Check if data is unchanged from last preparation (outside perform block)
        let currentHash = watchStates.hashValue
        if currentHash == previousHash {
            if shouldDebug {
                debug(.watchManager, "Garmin: Skipping - data unchanged")
            }
            return previousWatchState ?? watchStates
        }

        if shouldDebug {
            let iobFormatted = String(format: "%.1f", watchStates.first?.iob ?? 0)
            let cobFormatted = String(format: "%.0f", watchStates.first?.cob ?? 0)
            let tbrFormatted = String(format: "%.2f", watchStates.first?.tbr ?? 0)
            let sensRatioFormatted = String(format: "%.2f", watchStates.first?.sensRatio ?? 0)
            debug(
                .watchManager,
                "Garmin: Prepared \(watchStates.count) entries - sgv: \(watchStates.first?.sgv ?? 0), iob: \(iobFormatted), cob: \(cobFormatted), tbr: \(tbrFormatted), eventualBG: \(watchStates.first?.eventualBG ?? 0), sensRatio: \(sensRatioFormatted)"
            )
        }

        // Cache for deduplication (outside perform block)
        lastPreparedDataHash = currentHash
        lastPreparedWatchState = watchStates

        return watchStates
    }

    /// Formats IOB (Insulin On Board) value with 1 decimal precision for display.
    /// Prevents small values from rounding to zero by enforcing a minimum magnitude of 0.1.
    /// - Parameter value: The IOB value to format.
    /// - Returns: The formatted IOB value as a Double with 1 decimal place.
    private func formatIOB(_ value: Decimal) -> Double {
        let doubleValue = NSDecimalNumber(decimal: value).doubleValue
        if doubleValue.magnitude < 0.1, doubleValue != 0 {
            return doubleValue > 0 ? 0.1 : -0.1
        }
        return (doubleValue * 10).rounded() / 10
    }

    // MARK: - Device & App Registration

    /// Registers the given devices for ConnectIQ events (device status changes) and watch app messages.
    /// It also creates and registers watch apps (watchface + data field) for each device.
    /// - Parameter devices: The devices to register.
    private func registerDevices(_ devices: [IQDevice]) {
        watchApps.removeAll()

        // Reset broadcast hash so newly registered apps receive data
        // Without this, hash deduplication could skip sending to new apps if data unchanged
        lastSentDataHash = nil

        // Note: Do NOT clear readyDevices here. The device ready state is based on BLE
        // characteristic discovery, which only happens on new connections. Re-registering
        // for app messages doesn't affect the underlying BLE connection state.

        for device in devices {
            connectIQ?.register(forDeviceEvents: device, delegate: self)

            // Register watchface if enabled
            if isWatchfaceDataEnabled,
               let watchfaceUUID = currentWatchface.watchfaceUUID,
               let watchfaceApp = IQApp(uuid: watchfaceUUID, store: UUID(), device: device)
            {
                debugGarmin("Garmin: Registered \(appDetailedName(for: watchfaceUUID))")
                watchApps.append(watchfaceApp)
                connectIQ?.register(forAppMessages: watchfaceApp, delegate: self)
                // Seed the inactivity timeout on first registration (e.g. after app restart).
                // This allows initial sends for up to watchfaceActiveTimeout seconds,
                // after which isWatchfaceInactive() will block further sends unless
                // a status request from the watchface resets the timer.
                // Only set when nil to avoid overwriting a valid timestamp from a recent status request.
                if lastWatchfaceRequestTime == nil {
                    lastWatchfaceRequestTime = Date()
                }
            } else if !isWatchfaceDataEnabled {
                debugGarmin("Garmin: Watchface data disabled - skipping watchface registration")
            }

            // Always register datafield (if configured)
            if let datafieldUUID = currentDatafield.datafieldUUID,
               let datafieldApp = IQApp(uuid: datafieldUUID, store: UUID(), device: device)
            {
                debugGarmin("Garmin: Registered \(appDetailedName(for: datafieldUUID))")
                watchApps.append(datafieldApp)
                connectIQ?.register(forAppMessages: datafieldApp, delegate: self)
            }
        }
    }

    /// Restores previously persisted devices from local storage into `devices`.
    private func restoreDevices() {
        devices = persistedDevices.map(\.iqDevice)
    }

    // MARK: - Simulator Support

    #if targetEnvironment(simulator)
        /// Mock IQDevice class for simulator testing
        /// Minimal implementation just for testing - no actual Garmin functionality
        class MockIQDevice: IQDevice {
            private let _uuid: UUID
            private let _friendlyName: String
            private let _modelName: String

            override var uuid: UUID { _uuid }
            override var friendlyName: String { _friendlyName }
            override var modelName: String { _modelName }
            var status: IQDeviceStatus { .connected }

            init(uuid: UUID, friendlyName: String, modelName: String) {
                _uuid = uuid
                _friendlyName = friendlyName
                _modelName = modelName
                super.init()
            }

            @available(*, unavailable) required init?(coder _: NSCoder) {
                fatalError("init(coder:) not implemented for mock device")
            }

            /// Shared simulated device UUID for consistency across the app
            static let simulatedUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")
                ?? UUID()

            /// Creates the standard simulated Enduro 3 device
            static func createSimulated() -> MockIQDevice {
                MockIQDevice(
                    uuid: simulatedUUID,
                    friendlyName: "Enduro 3 Sim",
                    modelName: "Enduro 3"
                )
            }
        }
    #endif

    // MARK: - Combine Subscriptions

    /// Subscribes to the `.openFromGarminConnect` notification, parsing devices from the given URL
    /// and updating the device list accordingly.
    private func subscribeToOpenFromGarminConnect() {
        notificationCenter
            .publisher(for: .openFromGarminConnect)
            .sink { [weak self] notification in
                guard let self = self, let url = notification.object as? URL else { return }
                self.parseDevices(for: url)
            }
            .store(in: &cancellables)
    }

    /// Subscribes to watch state updates with debouncing
    private func subscribeToWatchState() {
        watchStateSubject
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { [weak self] data, targetAppUUID in
                self?.broadcastWatchStateData(data, targetAppUUID: targetAppUUID)
            }
            .store(in: &cancellables)
    }

    // MARK: - Parsing & Broadcasting

    /// Parses devices from a Garmin Connect URL and updates our `devices` property.
    /// - Parameter url: The URL provided by Garmin Connect containing device selection info.
    private func parseDevices(for url: URL) {
        let parsed = connectIQ?.parseDeviceSelectionResponse(from: url) as? [IQDevice]
        devices = parsed ?? []
        deviceSelectionPromise?(.success(devices))
        deviceSelectionPromise = nil
    }

    /// Broadcasts watch state data to registered apps.
    /// - Parameters:
    ///   - data: JSON-encoded watch state data.
    ///   - targetAppUUID: If provided, only send to this app. If nil, send to all.
    private func broadcastWatchStateData(_ data: Data, targetAppUUID: UUID? = nil) {
        // Skip sends during active BLE flapping - wait for status request or timeout
        if isFlapping {
            debug(.watchManager, "Garmin: Skipping send - BLE flapping in progress")
            return
        }

        // Deduplicate: Use stable content-based hash (sorted JSON bytes)
        let currentHash: Int
        if let sortedData = try? JSONSerialization.data(
            withJSONObject: JSONSerialization.jsonObject(with: data, options: []),
            options: [.sortedKeys]
        ) {
            currentHash = sortedData.base64EncodedString().hashValue
        } else {
            currentHash = data.count // Fallback
        }

        if currentHash == lastSentDataHash {
            if debugWatchState {
                if let targetAppUUID = targetAppUUID {
                    debug(.watchManager, "Garmin: Skipping send to \(appDisplayName(for: targetAppUUID)) - data unchanged")
                } else {
                    debug(.watchManager, "Garmin: Skipping broadcast - data unchanged")
                }
            }
            return
        }

        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
            debug(.watchManager, "Garmin: Invalid JSON for watch-state data")
            return
        }

        let appsToSend = targetAppUUID != nil
            ? watchApps.filter { $0.uuid == targetAppUUID }
            : watchApps

        // Track if at least one send was initiated - only update hash if so
        var didInitiateSend = false

        appsToSend.forEach { app in
            guard let appUUID = app.uuid else {
                debug(.watchManager, "Garmin: Skipping app with undefined UUID")
                return
            }
            let appName = self.appDisplayName(for: appUUID)

            // Check if device is ready (SDK 1.8+ requirement)
            guard let device = app.device, readyDevices.contains(device.uuid) else {
                debugGarmin("Garmin: Skipping \(appName) - device not ready")
                return
            }

            // Gate sends based on activity to prevent queue buildup
            let isWatchface = appUUID == currentWatchface.watchfaceUUID
            let isDatafield = appUUID == currentDatafield.datafieldUUID

            // Only apply smart switching after we've received at least one status request
            // On app restart, broadcast to both until we know which one is active
            let hasReceivedAnyStatusRequest = lastWatchfaceRequestTime != nil || lastDatafieldRequestTime != nil

            if isSmartMessageSwitchingEnabled, hasReceivedAnyStatusRequest {
                // Fallback: if flag says activity running but datafield inactive for 15 min,
                // assume activity ended (handles case where no watchface is installed)
                if watchfaceSuppressedDuringActivity, isDatafieldInactive() {
                    debug(.watchManager, "Garmin: Datafield inactive for 15 min - assuming activity ended")
                    watchfaceSuppressedDuringActivity = false
                }

                // Skip watchface if suppressed during activity (datafield is active)
                if isWatchface, watchfaceSuppressedDuringActivity {
                    debug(.watchManager, "Garmin: Skipping watchface send - activity in progress (datafield active)")
                    return
                }

                // Skip watchface if inactive (no status request in 5 min)
                if isWatchface, isWatchfaceInactive() {
                    debug(
                        .watchManager,
                        "Garmin: Skipping watchface send - inactive (no status request in \(Int(watchfaceActiveTimeout / 60)) min)"
                    )
                    return
                }

                // Skip datafield if no activity running (watchface is active)
                if isDatafield, !watchfaceSuppressedDuringActivity {
                    debug(.watchManager, "Garmin: Skipping datafield send - no activity running (watchface active)")
                    return
                }
            }

            // Mark that we're initiating at least one send attempt
            didInitiateSend = true

            connectIQ?.getAppStatus(app) { [weak self] status in
                guard status?.isInstalled == true else {
                    debug(.watchManager, "Garmin: App not installed: \(appName)")
                    return
                }
                self?.debugGarmin("Garmin: Sending to \(appName)")
                self?.sendMessage(jsonObject as Any, to: app, appName: appName)
            }
        }

        // Only update hash if we actually initiated at least one send
        // If all apps were skipped (device not ready, activity logic), don't cache the hash
        // This ensures we retry sending when conditions change (device becomes ready, etc.)
        if didInitiateSend {
            lastSentDataHash = currentHash
        }
    }

    // MARK: - GarminManager Conformance

    /// Prompts the user to select one or more Garmin devices, returning a publisher that emits
    /// the final array of selected devices once the user finishes selection.
    /// - Returns: An `AnyPublisher` emitting `[IQDevice]` on success, or empty array on error/timeout.
    func selectDevices() -> AnyPublisher<[IQDevice], Never> {
        Future { [weak self] promise in
            guard let self = self else {
                promise(.success([]))
                return
            }
            self.deviceSelectionPromise = promise
            self.connectIQ?.showDeviceSelection()
        }
        .timeout(.seconds(120), scheduler: DispatchQueue.main)
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    /// Updates the manager's list of devices, typically after user selection or manual changes.
    /// - Parameter devices: The new array of `IQDevice` objects to track.
    func updateDeviceList(_ devices: [IQDevice]) {
        self.devices = devices
    }

    /// Sends the given watch state data to the debounce subject for eventual broadcast.
    /// - Parameter data: JSON-encoded data representing the latest watch state.
    func sendWatchStateData(_ data: Data) {
        watchStateSubject.send((data, nil))
    }

    // MARK: - Helper: Sending Messages

    /// Sends a message to a given IQApp with optional progress and completion callbacks.
    /// Retries once after a short delay if the first attempt fails (SDK may need time after re-registration).
    /// - Parameters:
    ///   - msg: The data to send to the watch app.
    ///   - app: The `IQApp` instance representing the watchface or data field.
    ///   - appName: The display name of the app for logging.
    ///   - isRetry: Whether this is a retry attempt (to prevent infinite retries).
    private func sendMessage(_ msg: Any, to app: IQApp, appName: String, isRetry: Bool = false) {
        connectIQ?.sendMessage(
            msg,
            to: app,
            progress: { _, _ in },
            completion: { [weak self] result in
                switch result {
                case .success:
                    debug(.watchManager, "Garmin: Successfully sent to \(appName)")
                default:
                    if isRetry {
                        debug(.watchManager, "Garmin: FAILED to send to \(appName) (retry also failed)")
                    } else {
                        debug(.watchManager, "Garmin: FAILED to send to \(appName) - will retry in 2s")
                        // Retry after delay - SDK may need time after re-registration
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self?.debugGarmin("Garmin: Retrying send to \(appName)")
                            self?.sendMessage(msg, to: app, appName: appName, isRetry: true)
                        }
                    }
                }
            }
        )
    }
}

// MARK: - Extensions

extension BaseGarminManager: IQUIOverrideDelegate, IQDeviceEventDelegate, IQAppMessageDelegate {
    // MARK: - IQUIOverrideDelegate

    /// Called if the Garmin Connect Mobile app is not installed or otherwise not available.
    /// Typically, you would show an alert or prompt the user to install the app from the store.
    func needsToInstallConnectMobile() {
        debug(.apsManager, "Garmin is not available")
        let messageCont = MessageContent(
            content: "The app Garmin Connect must be installed to use Trio.\nGo to the App Store to download it.",
            type: .warning,
            subtype: .misc,
            title: "Garmin is not available"
        )
        router.alertMessage.send(messageCont)
    }

    // MARK: - IQDeviceEventDelegate

    /// Called whenever the status of a registered Garmin device changes (e.g., connected, not found, etc.).
    /// Note: In SDK 1.8+, `connected` does NOT mean ready for communication.
    /// Wait for `deviceCharacteristicsDiscovered:` before sending messages.
    /// - Parameters:
    ///   - device: The device whose status has changed.
    ///   - status: The new status for the device.
    func deviceStatusChanged(_ device: IQDevice, status: IQDeviceStatus) {
        // Always log connection state changes - critical for diagnosing SDK issues
        let isConnectedState = (status == .connected)

        switch status {
        case .invalidDevice:
            debug(.watchManager, "Garmin: Device status -> invalidDevice")
            readyDevices.remove(device.uuid)
        case .bluetoothNotReady:
            debug(.watchManager, "Garmin: Device status -> bluetoothNotReady")
            readyDevices.remove(device.uuid)
        case .notFound:
            debug(.watchManager, "Garmin: Device status -> notFound")
            readyDevices.remove(device.uuid)
        case .notConnected:
            debug(.watchManager, "Garmin: Device status -> notConnected")
            readyDevices.remove(device.uuid)
        case .connected:
            debug(.watchManager, "Garmin: Device status -> connected (waiting for characteristics)")
        @unknown default:
            debug(.watchManager, "Garmin: Device status -> unknown(\(status.rawValue))")
        }

        // Track connection state for flapping detection
        trackConnectionStateChange(isConnected: isConnectedState)
    }

    /// Tracks connection state changes and detects BLE flapping.
    /// Flapping is detected when either:
    /// 1. 4+ disconnects occur within 30 seconds, OR
    /// 2. 3+ consecutive disconnects have gaps ≤5 seconds
    /// Only disconnects count toward flapping - connects are recovery attempts, not problems.
    /// When detected, schedules automatic re-registration once the connection stabilizes.
    /// - Parameter isConnected: Whether the device just connected (true) or disconnected (false).
    private func trackConnectionStateChange(isConnected: Bool) {
        let now = Date()

        // Only track disconnects for flapping detection - connects are recovery attempts
        if !isConnected {
            connectionStateHistory.append((now, isConnected))
        }

        // Remove entries older than the detection window (keep slightly longer for rapid detection)
        let cutoff = now.addingTimeInterval(-flappingDetectionWindow * 2)
        connectionStateHistory = connectionStateHistory.filter { $0.0 > cutoff }

        // Detection method 1: Count disconnects within the tight window
        let recentCutoff = now.addingTimeInterval(-flappingDetectionWindow)
        let recentDisconnects = connectionStateHistory.filter { $0.0 > recentCutoff }
        let disconnectCount = recentDisconnects.count

        // Detection method 2: Check for consecutive rapid disconnects (gaps ≤5s)
        let consecutiveRapidCount = countConsecutiveRapidDisconnects()

        // Detect flapping: either 4+ disconnects in 30s OR 3+ consecutive rapid disconnects
        let isFlappingDetected = disconnectCount >= flappingThreshold || consecutiveRapidCount >= consecutiveRapidThreshold

        if isFlappingDetected {
            if !isFlapping {
                // First detection of flapping - log which method triggered it
                isFlapping = true
                hasTriggeredFlappingReregistration = false
                if consecutiveRapidCount >= consecutiveRapidThreshold {
                    debug(
                        .watchManager,
                        "Garmin: BLE FLAPPING DETECTED - \(consecutiveRapidCount) consecutive rapid disconnects (≤\(Int(rapidTransitionThreshold))s gaps)"
                    )
                } else {
                    debug(
                        .watchManager,
                        "Garmin: BLE FLAPPING DETECTED - \(disconnectCount) disconnects in \(Int(flappingDetectionWindow))s window"
                    )
                }
            }
            lastFlappingDetectedTime = now

            // If flapping resumes while recovery is pending, cancel it and wait for true stability
            if pendingFlappingReregistration != nil {
                pendingFlappingReregistration?.cancel()
                pendingFlappingReregistration = nil
                debug(.watchManager, "Garmin: Flapping resumed - cancelled pending recovery, waiting for stability")
            }
        } else if isFlapping, isConnected {
            // Flapping has stopped AND we ended on a connected state - schedule re-registration
            // Don't schedule if we ended on disconnect - wait for the next connect event
            scheduleFlappingRecovery()
        }
    }

    /// Counts the number of consecutive disconnects where each gap is ≤ rapidTransitionThreshold.
    /// Returns the maximum streak of rapid disconnects found in the history.
    private func countConsecutiveRapidDisconnects() -> Int {
        guard connectionStateHistory.count >= 2 else { return 0 }

        var maxStreak = 0
        var currentStreak = 0

        for i in 1 ..< connectionStateHistory.count {
            let gap = connectionStateHistory[i].0.timeIntervalSince(connectionStateHistory[i - 1].0)
            if gap <= rapidTransitionThreshold {
                currentStreak += 1
                maxStreak = max(maxStreak, currentStreak)
            } else {
                currentStreak = 0
            }
        }

        return maxStreak
    }

    /// Schedules a re-registration attempt after BLE flapping has stabilized.
    /// Waits for the stabilization period to ensure connection is truly stable.
    /// If flapping resumes, the pending recovery is cancelled and rescheduled when it subsides again.
    private func scheduleFlappingRecovery() {
        guard isFlapping, !hasTriggeredFlappingReregistration else { return }

        // Cancel any existing pending recovery (shouldn't happen with current logic, but defensive)
        pendingFlappingReregistration?.cancel()
        pendingFlappingReregistration = nil

        debug(.watchManager, "Garmin: BLE flapping subsided - scheduling recovery in \(Int(flappingStabilizationTime))s")

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Verify flapping state is still active (may have been reset by status request or toggle)
            guard self.isFlapping else {
                debug(.watchManager, "Garmin: Flapping recovery skipped - communication already restored")
                return
            }
            guard !self.hasTriggeredFlappingReregistration else {
                debug(.watchManager, "Garmin: Flapping recovery cancelled - already triggered")
                return
            }

            self.performFlappingRecovery()
        }

        pendingFlappingReregistration = workItem
        timerQueue.asyncAfter(deadline: .now() + flappingStabilizationTime, execute: workItem)
    }

    /// Performs recovery after BLE flapping by re-registering devices.
    /// This forces the SDK to re-establish communication channels that may have been
    /// corrupted during the flapping episode.
    private func performFlappingRecovery() {
        guard !devices.isEmpty else {
            debug(.watchManager, "Garmin: Flapping recovery skipped - no devices registered")
            resetFlappingState()
            return
        }

        debug(.watchManager, "Garmin: FLAPPING RECOVERY - Re-registering devices to restore communication")

        // Mark that we've triggered re-registration for this flapping episode
        hasTriggeredFlappingReregistration = true

        // Clear activity tracking state since watch service may have lost state
        lastWatchfaceRequestTime = nil
        lastDatafieldRequestTime = nil
        watchfaceSuppressedDuringActivity = false

        // Clear hash caches to ensure fresh data is sent after re-registration
        lastPreparedDataHash = nil
        lastSentDataHash = nil

        // Re-register devices - this will re-register for device events and app messages
        registerDevices(devices)

        debug(.watchManager, "Garmin: Flapping recovery complete - waiting for watch app status requests")

        // Reset flapping state after successful recovery
        resetFlappingState()
    }

    /// Resets flapping detection state after recovery or status request.
    private func resetFlappingState() {
        isFlapping = false
        hasTriggeredFlappingReregistration = false
        lastFlappingDetectedTime = nil
        connectionStateHistory.removeAll()
        pendingFlappingReregistration?.cancel()
        pendingFlappingReregistration = nil
    }

    // MARK: - Proactive Recovery (Pattern 3: Missed Status Requests)

    /// Schedules a proactive recovery check for when 3 status requests would be missed.
    /// Called each time a watchface status request is received.
    /// Recovery triggers 30 seconds before the 4th expected request would be missed.
    private func scheduleProactiveRecoveryCheck() {
        // Only schedule if watchface data is enabled
        guard isWatchfaceDataEnabled else { return }

        // Cancel any existing pending check
        pendingProactiveRecovery?.cancel()

        // Calculate when to trigger recovery:
        // After 3 missed requests, the 4th would be missed at (missedThreshold + 1) * interval
        // Trigger 30s before that: (3 + 1) * 5min - 30s = 20min - 30s = 19min 30s from now
        let recoveryDelay = (Double(missedRequestThreshold + 1) * expectedStatusRequestInterval) - proactiveRecoveryLeadTime

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.checkAndPerformProactiveRecovery()
        }

        pendingProactiveRecovery = workItem
        timerQueue.asyncAfter(deadline: .now() + recoveryDelay, execute: workItem)
    }

    /// Checks if proactive recovery is needed and performs it if so.
    /// Called after the scheduled delay when no status requests have been received.
    private func checkAndPerformProactiveRecovery() {
        // Verify conditions are still met
        guard isWatchfaceDataEnabled,
              !hasTriggeredProactiveRecovery,
              !devices.isEmpty
        else {
            return
        }

        // Verify the watchface has actually been silent for the expected time
        guard let lastRequest = lastWatchfaceRequestTime else {
            // No previous request recorded - this shouldn't happen, but skip recovery
            return
        }

        let silenceDuration = Date().timeIntervalSince(lastRequest)
        let expectedSilence = (Double(missedRequestThreshold + 1) * expectedStatusRequestInterval) - proactiveRecoveryLeadTime

        // Only recover if we've been silent for at least the expected duration (with some tolerance)
        guard silenceDuration >= expectedSilence - 10 else {
            // Request came in recently, no recovery needed
            return
        }

        performProactiveRecovery()
    }

    /// Performs proactive recovery by re-registering devices.
    /// Triggered when watchface stops sending status requests without BLE issues.
    /// This handles Pattern 3: Garmin OS suspending watchface service without BLE flapping.
    private func performProactiveRecovery() {
        hasTriggeredProactiveRecovery = true

        let silenceMinutes =
            Int((Double(missedRequestThreshold + 1) * expectedStatusRequestInterval - proactiveRecoveryLeadTime) / 60)
        debug(
            .watchManager,
            "Garmin: PROACTIVE RECOVERY - No watchface status requests for ~\(silenceMinutes) min (\(missedRequestThreshold) missed), re-registering devices"
        )

        // Clear activity tracking state
        lastWatchfaceRequestTime = nil
        watchfaceSuppressedDuringActivity = false

        // Clear hash caches to ensure fresh data is sent after re-registration
        lastPreparedDataHash = nil
        lastSentDataHash = nil

        // Re-register devices
        registerDevices(devices)

        debug(.watchManager, "Garmin: Proactive recovery complete - waiting for watch app status requests")
    }

    /// Called when device characteristics are discovered and the device is ready for communication.
    /// This is required in SDK 1.8+ - sending before this callback may fail.
    /// - Parameter device: The device whose characteristics have been discovered.
    func deviceCharacteristicsDiscovered(_ device: IQDevice) {
        debug(.watchManager, "Garmin: Device characteristics discovered - ready for communication")
        readyDevices.insert(device.uuid)

        // Trigger a data send now that device is ready
        // This ensures newly connected devices get data promptly
        triggerWatchStateUpdate(triggeredBy: "DeviceReady")
    }

    // MARK: - IQAppMessageDelegate

    /// Called when a message arrives from a Garmin watch app (watchface or data field).
    /// If the watch requests a "status" update, we call `setupGarminWatchState()` asynchronously
    /// and re-send the watch state data.
    /// - Parameters:
    ///   - message: The message content from the watch app.
    ///   - app: The watch app sending the message.
    func receivedMessage(_ message: Any, from app: IQApp) {
        guard let appUUID = app.uuid else {
            debug(.watchManager, "Garmin: Received message from app with undefined UUID - ignoring")
            return
        }
        let appName = appDisplayName(for: appUUID)
        debugGarmin("Garmin: Received message '\(message)' from \(appName)")

        // If watch requests status update, send current data via unified path
        guard let statusString = message as? String, statusString == "status" else {
            return
        }

        // Track app activity for queue prevention
        let isWatchface = appUUID == currentWatchface.watchfaceUUID
        let isDatafield = appUUID == currentDatafield.datafieldUUID

        if isWatchface {
            lastWatchfaceRequestTime = Date()

            // Reset proactive recovery state and schedule next check
            // This ensures we detect if watchface stops responding
            hasTriggeredProactiveRecovery = false
            scheduleProactiveRecoveryCheck()

            // Cancel pending flapping recovery - status request proves communication restored
            if isFlapping {
                debug(.watchManager, "Garmin: Watchface request received - cancelling flapping recovery (communication restored)")
                pendingFlappingReregistration?.cancel()
                resetFlappingState()
            }

            if isSmartMessageSwitchingEnabled {
                // Watchface request while activity was running = activity just ended
                // Send immediately with no hash checks
                if watchfaceSuppressedDuringActivity {
                    debug(.watchManager, "Garmin: Watchface request - activity ended, sending immediately")
                    watchfaceSuppressedDuringActivity = false
                    sendImmediateWatchState(to: appUUID, triggeredBy: "ActivityEnded")
                    return
                }

                if isWatchfaceInactive() {
                    // Watchface just woke up after being inactive - send fresh data
                    debug(.watchManager, "Garmin: Watchface resumed after inactivity - sending fresh data")
                    lastPreparedDataHash = nil
                    lastSentDataHash = nil
                }
            }
        } else if isDatafield {
            lastDatafieldRequestTime = Date()

            // Cancel pending flapping recovery - status request proves communication restored
            if isFlapping {
                debug(.watchManager, "Garmin: Datafield request received - cancelling flapping recovery (communication restored)")
                pendingFlappingReregistration?.cancel()
                resetFlappingState()
            }

            if isSmartMessageSwitchingEnabled {
                // Datafield request while no activity was running = activity just started
                // Send immediately with no hash checks (mirror of watchface logic)
                if !watchfaceSuppressedDuringActivity {
                    debug(.watchManager, "Garmin: Datafield request - activity started, sending immediately")
                    watchfaceSuppressedDuringActivity = true
                    sendImmediateWatchState(to: appUUID, triggeredBy: "ActivityStarted")
                    return
                }
                // Activity already running - send fresh data through normal pipeline
                lastSentDataHash = nil
            }
        }

        // Reply only to the requesting app through the full pipeline
        triggerWatchStateUpdate(triggeredBy: "WatchRequest", targetAppUUID: appUUID)
    }

    /// Checks if the watchface has been inactive (no status requests) for longer than the timeout.
    /// - Returns: true if watchface is considered inactive, false if recently active or never seen.
    private func isWatchfaceInactive() -> Bool {
        guard let lastRequest = lastWatchfaceRequestTime else {
            // No timestamp yet - seeded on registration, so nil here means
            // watchface is not registered. Consider inactive.
            return true
        }
        return Date().timeIntervalSince(lastRequest) > watchfaceActiveTimeout
    }

    /// Checks if the datafield has been inactive (no status requests) for longer than the timeout.
    /// Fallback for detecting "activity ended" when no watchface is installed.
    /// - Returns: true if datafield is inactive (activity likely ended), false if recently active.
    private func isDatafieldInactive() -> Bool {
        guard let lastRequest = lastDatafieldRequestTime else {
            // Never received a request - consider inactive
            return true
        }
        return Date().timeIntervalSince(lastRequest) > datafieldInactiveTimeout
    }

    /// Sends watch state immediately to a specific app, bypassing all hash checks.
    /// Used when activity transitions (start/end) - needs immediate fresh data.
    private func sendImmediateWatchState(to appUUID: UUID, triggeredBy: String) {
        Task {
            do {
                let watchState = try await setupGarminWatchState(triggeredBy: triggeredBy)
                let watchStateData = try JSONEncoder().encode(watchState)
                sendWatchStateToApp(watchStateData, appUUID: appUUID)
            } catch {
                debug(.watchManager, "Garmin: Cannot encode watch state: \(error)")
            }
        }
    }

    /// Sends data directly to a specific app without hash checks.
    private func sendWatchStateToApp(_ data: Data, appUUID: UUID) {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []) else {
            debug(.watchManager, "Garmin: Invalid JSON for immediate send")
            return
        }

        guard let app = watchApps.first(where: { $0.uuid == appUUID }) else {
            debug(.watchManager, "Garmin: App not found for immediate send")
            return
        }

        let appName = appDisplayName(for: appUUID)

        connectIQ?.getAppStatus(app) { [weak self] status in
            guard status?.isInstalled == true else {
                debug(.watchManager, "Garmin: App not installed: \(appName)")
                return
            }
            self?.debugGarmin("Garmin: Sending immediately to \(appName)")
            self?.sendMessage(jsonObject as Any, to: app, appName: appName)
        }
    }
}

extension BaseGarminManager: SettingsObserver {
    /// Called whenever TrioSettings changes (e.g., user toggles mg/dL vs. mmol/L, watchface selection, etc.).
    /// Compares previous vs current settings to determine what changed and responds appropriately.
    /// - Parameter _: The updated TrioSettings instance.
    func settingsDidChange(_: TrioSettings) {
        let currentGarminSettings = settingsManager.settings.garminSettings
        let currentUnits = settingsManager.settings.units

        // Detect what specifically changed
        let unitsChanged = currentUnits != units
        let watchfaceChanged = currentGarminSettings.watchface != previousGarminSettings.watchface
        let datafieldChanged = currentGarminSettings.datafield != previousGarminSettings.datafield
        let watchfaceDataEnabledChanged = currentGarminSettings.isWatchfaceDataEnabled != previousGarminSettings
            .isWatchfaceDataEnabled
        let displayAttributesChanged = currentGarminSettings.primaryAttributeChoice != previousGarminSettings
            .primaryAttributeChoice ||
            currentGarminSettings.secondaryAttributeChoice != previousGarminSettings.secondaryAttributeChoice

        // Update stored values
        units = currentUnits

        // Re-register devices only if watchface/datafield configuration changed
        if watchfaceChanged || datafieldChanged || watchfaceDataEnabledChanged {
            debugGarmin("Garmin: Watchface/datafield config changed - re-registering devices")
            if !devices.isEmpty {
                registerDevices(devices)
            }
        }

        // Send update for settings that affect displayed data
        // Watchface/datafield changes only need re-registration, not data update
        // Disabling watchface data doesn't need an update (nothing to send to)
        let watchfaceDataJustEnabled = watchfaceDataEnabledChanged && currentGarminSettings.isWatchfaceDataEnabled
        let datafieldJustEnabled = datafieldChanged && currentGarminSettings.datafield != .none

        if watchfaceDataJustEnabled || datafieldJustEnabled {
            // Send immediately to just the newly enabled app
            let targetUUID = datafieldJustEnabled
                ? currentGarminSettings.datafield.datafieldUUID
                : currentGarminSettings.watchface.watchfaceUUID
            if let targetUUID = targetUUID {
                let appName = appDisplayName(for: targetUUID)
                if debugWatchState {
                    debug(.watchManager, "Garmin: \(appName) enabled - sending update immediately")
                }

                // Reset watchface activity tracking when watchface data is toggled
                // This allows the send to bypass the inactivity check (manual remedy for queue issues)
                if watchfaceDataEnabledChanged {
                    lastWatchfaceRequestTime = Date()
                    resetFlappingState() // Clear any stuck flapping state
                    debug(.watchManager, "Garmin: Watchface data toggled - resetting activity and flapping state")
                }

                triggerWatchStateUpdate(triggeredBy: "Settings", targetAppUUID: targetUUID)
            }
        } else if unitsChanged || displayAttributesChanged {
            // Throttle other settings changes in case user makes multiple changes
            if debugWatchState {
                debug(.watchManager, "Garmin: Settings changed - scheduling throttled update")
            }
            sendSettingsUpdateThrottled()
        }

        // Store current Garmin settings for next comparison
        previousGarminSettings = currentGarminSettings
    }
}
