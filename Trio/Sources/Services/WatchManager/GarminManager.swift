import Combine
import ConnectIQ
import CoreData
import Foundation
import LoopKit
import Swinject
import UIKit

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

// MARK: - Connect IQ Client

/// The Connect IQ calls that register apps and reach them, behind a protocol so message targeting
/// and retries can be verified without a paired watch.
protocol GarminConnectIQClient: AnyObject {
    func registerDevice(_ device: IQDevice, delegate: IQDeviceEventDelegate)
    func unregisterDevice(_ device: IQDevice, delegate: IQDeviceEventDelegate)
    func deviceStatus(of device: IQDevice) -> IQDeviceStatus
    func registerApp(_ app: IQApp, delegate: IQAppMessageDelegate)
    func unregisterApp(_ app: IQApp, delegate: IQAppMessageDelegate)
    func send(_ message: Any, to app: IQApp, completion: @escaping (IQSendMessageResult) -> Void)
}

extension ConnectIQ: GarminConnectIQClient {
    func registerDevice(_ device: IQDevice, delegate: IQDeviceEventDelegate) {
        register(forDeviceEvents: device, delegate: delegate)
    }

    func unregisterDevice(_ device: IQDevice, delegate: IQDeviceEventDelegate) {
        unregister(forDeviceEvents: device, delegate: delegate)
    }

    func deviceStatus(of device: IQDevice) -> IQDeviceStatus {
        getDeviceStatus(device)
    }

    func registerApp(_ app: IQApp, delegate: IQAppMessageDelegate) {
        register(forAppMessages: app, delegate: delegate)
    }

    func unregisterApp(_ app: IQApp, delegate: IQAppMessageDelegate) {
        unregister(forAppMessages: app, delegate: delegate)
    }

    func send(_ message: Any, to app: IQApp, completion: @escaping (IQSendMessageResult) -> Void) {
        sendMessage(message, to: app, progress: { _, _ in }, completion: completion)
    }
}

// MARK: - Send Stall Recovery

enum GarminStallHookStatus: String {
    case installed
    case off
    case skipped
}

/// Connect IQ 1.8.0 only (exact package pin): finishes an `IQSendDataTask` stuck in its write-without-response
/// retry loop. Uses private SDK symbols; a dependency bump must remove or re-review this, never loosen the pin.
enum GarminSendStallRecovery {
    /// `taskState` is only read once the retry count passes the threshold, as in PR #49.
    static func shouldFinishSend(retryCount: Int32, taskState: @autoclosure () -> UInt) -> Bool {
        retryCount > 100 && taskState() == 1
    }

    static func install() -> GarminStallHookStatus {
        installation
    }

    private static let installation: GarminStallHookStatus = {
        guard let taskClass = NSClassFromString("IQSendDataTask") else {
            warning(.watch, "Garmin send stall recovery skipped: class")
            return .skipped
        }

        let retryCountSelector = NSSelectorFromString("writeWithoutResponseRetryCount")
        let finishSelector = NSSelectorFromString("finishWithResult:")
        let taskStateSelector = NSSelectorFromString("taskState")

        guard let retryCountMethod = class_getInstanceMethod(taskClass, retryCountSelector),
              let finishMethod = class_getInstanceMethod(taskClass, finishSelector),
              let taskStateMethod = class_getInstanceMethod(taskClass, taskStateSelector)
        else {
            warning(.watch, "Garmin send stall recovery skipped: method")
            return .skipped
        }

        func encoding(of method: Method) -> String? {
            method_getTypeEncoding(method).map { String(cString: $0) }
        }

        guard encoding(of: retryCountMethod) == "i16@0:8",
              encoding(of: finishMethod) == "v24@0:8Q16",
              encoding(of: taskStateMethod) == "Q16@0:8"
        else {
            warning(.watch, "Garmin send stall recovery skipped: encoding")
            return .skipped
        }

        typealias RetryCountFunction = @convention(c) (AnyObject, Selector) -> Int32
        typealias FinishFunction = @convention(c) (AnyObject, Selector, UInt) -> Void
        typealias TaskStateFunction = @convention(c) (AnyObject, Selector) -> UInt

        let originalRetryCount = unsafeBitCast(method_getImplementation(retryCountMethod), to: RetryCountFunction.self)
        let finish = unsafeBitCast(method_getImplementation(finishMethod), to: FinishFunction.self)
        let taskState = unsafeBitCast(method_getImplementation(taskStateMethod), to: TaskStateFunction.self)

        let recoveringRetryCount: @convention(block) (AnyObject) -> Int32 = { task in
            let retryCount = originalRetryCount(task, retryCountSelector)
            if GarminSendStallRecovery.shouldFinishSend(retryCount: retryCount, taskState: taskState(task, taskStateSelector)) {
                let activatedMS = GarminTransportRuntime.uptimeMS()
                // private result 6, not the public IQSendMessageResult raw value 6
                finish(task, finishSelector, 6)
                DispatchQueue.main.async {
                    debug(
                        .watch,
                        "garmin.stall.hook_activated ts_ms=\(activatedMS) source=sdk_hook elapsed_ms=unavailable attribution=unavailable"
                    )
                }
            }
            return retryCount
        }

        method_setImplementation(retryCountMethod, imp_implementationWithBlock(recoveringRetryCount))
        debug(.watch, "Garmin send stall recovery installed")
        return .installed
    }()
}

// MARK: - Transport Runtime

/// Clock, timers and startup seams of the Garmin transport; tests replace them with a fake.
struct GarminTransportRuntime {
    /// Monotonic milliseconds, never wall-clock or sensor time.
    let nowMS: () -> UInt64
    let scheduler: (TimeInterval, DispatchWorkItem) -> Void
    /// Mirrors every `garmin.*` transport line for tests; production leaves it nil.
    let logSink: ((String) -> Void)?
    /// Initializes the shared SDK and loads/saves the persisted device list.
    let usesSharedConnectIQ: Bool
    /// Builds real watch state on refresh triggers; tests submit their own payloads instead.
    let preparesWatchState: Bool
    /// Samples the application state on main when the transport starts.
    let isApplicationActive: () -> Bool
    /// Runs at most once per launch, only when the setting is on.
    let installStallRecovery: () -> GarminStallHookStatus

    init(
        nowMS: @escaping () -> UInt64 = GarminTransportRuntime.uptimeMS,
        scheduler: @escaping (TimeInterval, DispatchWorkItem) -> Void = GarminTransportRuntime.mainQueueScheduler,
        logSink: ((String) -> Void)? = nil,
        usesSharedConnectIQ: Bool = false,
        preparesWatchState: Bool = true,
        isApplicationActive: @escaping () -> Bool = { UIApplication.shared.applicationState == .active },
        installStallRecovery: @escaping () -> GarminStallHookStatus = { .skipped }
    ) {
        self.nowMS = nowMS
        self.scheduler = scheduler
        self.logSink = logSink
        self.usesSharedConnectIQ = usesSharedConnectIQ
        self.preparesWatchState = preparesWatchState
        self.isApplicationActive = isApplicationActive
        self.installStallRecovery = installStallRecovery
    }

    func schedule(after delay: TimeInterval, _ work: DispatchWorkItem) {
        scheduler(delay, work)
    }

    static func uptimeMS() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds / 1_000_000
    }

    static func mainQueueScheduler(_ delay: TimeInterval, _ work: DispatchWorkItem) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    static let live = GarminTransportRuntime(
        usesSharedConnectIQ: true,
        installStallRecovery: GarminSendStallRecovery.install
    )

    /// Real clock and main-queue timers around an injected client, without the shared SDK or persisted devices.
    static let detached = GarminTransportRuntime()
}

// MARK: - Delivery State

/// Internal routing identity of one app on one device; never logged.
private struct DeliveryKey: Hashable {
    let deviceID: UUID
    let appID: UUID
}

private enum GarminLinkStatus {
    case unknown
    case connected
    case disconnected
}

private enum GarminAppKind {
    /// Includes the Complication app.
    case watchface
    case datafield
}

private enum GarminSendKind: String {
    case state
    case targeted
}

private struct GarminDeliveryTarget {
    let appID: UUID
    let kind: GarminAppKind
    let label: String
}

/// One debounced watch state; `generation` is the operational `payload_id`.
private struct GarminStateSnapshot {
    let generation: UInt64
    let canonicalData: Data
    let payload: Any
}

/// Identity of one SDK send, fixed at start so its completion can be fenced against newer registrations.
private struct GarminSendContext {
    let key: DeliveryKey
    let kind: GarminSendKind
    let selectionToken: UInt64
    let deviceRegistration: UInt64
    let linkEpoch: UInt64
    let appRegistration: UInt64
    let appLabel: String
    let payloadID: UInt64
    let attemptID: UInt64
    let retryOf: UInt64?
    let startMS: UInt64

    var fields: [(String, String)] {
        [
            ("device_id", String(selectionToken)),
            ("link_epoch", String(linkEpoch)),
            ("app", appLabel),
            ("payload_id", String(payloadID)),
            ("attempt_id", String(attemptID)),
            ("kind", kind.rawValue),
            ("attempt", retryOf == nil ? "first" : "retry"),
            ("retry_of", retryOf.map(String.init) ?? "unavailable"),
            ("start_ms", String(startMS))
        ]
    }
}

private struct StateAttempt {
    let context: GarminSendContext
    /// The bytes actually handed to the SDK, recorded as delivered only on its own success.
    let canonicalData: Data
    /// A failure of an attempt begun before the latest proof is diagnostic only.
    let proofEpoch: UInt64
}

/// A reserved state retry; holds no payload, the newest debounced snapshot is chosen at expiry.
private struct ScheduledStateRetry {
    let work: DispatchWorkItem
    let workToken: UInt64
    let originAttemptID: UInt64
    let deviceRegistration: UInt64
    let linkEpoch: UInt64
    let appRegistration: UInt64
}

private struct PendingReplyRetry {
    let work: DispatchWorkItem
    let key: DeliveryKey
    let appRegistration: UInt64
    let linkEpoch: UInt64
}

/// An armed device re-registration, bound to the link and proof it was armed for.
private struct ScheduledLinkRecovery {
    let work: DispatchWorkItem
    let token: UInt64
    let deviceRegistration: UInt64
    let linkEpoch: UInt64
    let proofEpoch: UInt64
    let results: [IQSendMessageResult]
    let step: Int
    let delay: TimeInterval
}

/// Evidence for one selected device: a strict pair of final link failures since the last proof.
private struct LinkRecoveryState {
    var proofEpoch: UInt64 = 0
    var failures: [IQSendMessageResult] = []
    var backoffStep = 0
    var recoveryWork: ScheduledLinkRecovery?
}

private struct GarminDeviceRegistration {
    /// The runtime object first selected for this UUID; reused for every app and re-registration.
    let device: IQDevice
    /// Stable for the selection, logged as `device_id`.
    let selectionToken: UInt64
    var deviceRegistration: UInt64
    var relay: GarminDeviceEventRelay
    var linkEpoch: UInt64 = 1
    var linkStatus: GarminLinkStatus = .unknown
    var lastStatusLog: (raw: Int, atMS: UInt64)?
    var readyLog: (deviceRegistration: UInt64, linkEpoch: UInt64, atMS: UInt64)?
    var recovery = LinkRecoveryState()
}

private struct GarminAppRegistration {
    let app: IQApp
    let relay: GarminAppMessageRelay
    let appRegistration: UInt64
    let kind: GarminAppKind
    let appLabel: String
    var lastDeliveredState: Data?
    /// Always refers to the latest eligible snapshot, never to a queue of payloads.
    var owedState: Bool
    var stateAttempt: StateAttempt?
    var stateRetry: ScheduledStateRetry?
    /// A new app only takes state prepared for its configuration, i.e. the next debounced broadcast.
    var awaitsNextBroadcast = true
}

private enum GarminPendingEvaluation {
    case waitingForDeadline
    /// Past the deadline while not confirmed connected; re-armed only by a real connected or ready edge.
    case waitingForConnection
    case evaluated
}

private struct GarminPendingSlot: Hashable {
    let key: DeliveryKey
    let kind: GarminSendKind
}

/// The outstanding state attempt, or the oldest outstanding reply, of one key.
private struct GarminPendingSend {
    let context: GarminSendContext
    var evaluation: GarminPendingEvaluation = .waitingForDeadline
    var episodeOpened = false
}

private struct GarminStallObservation {
    let origin: GarminSendContext
    let openedMS: UInt64
}

private struct GarminReconnectObservation {
    let selectionToken: UInt64
    let recoveryID: UInt64
    let startMS: UInt64
}

/// Consumed on main so a duplicate SDK completion of the same attempt is dropped.
private final class GarminCompletionGate {
    var isConsumed = false
}

// MARK: - Connect IQ Relays

/// Device listener bound to one device registration; every callback is re-posted to main.
private final class GarminDeviceEventRelay: NSObject, IQDeviceEventDelegate {
    let deviceID: UUID
    let deviceRegistration: UInt64
    private weak var owner: BaseGarminManager?

    init(deviceID: UUID, deviceRegistration: UInt64, owner: BaseGarminManager) {
        self.deviceID = deviceID
        self.deviceRegistration = deviceRegistration
        self.owner = owner
    }

    func deviceStatusChanged(_ device: IQDevice!, status: IQDeviceStatus) {
        guard device?.uuid == deviceID, let owner else { return }
        let eventMS = owner.runtime.nowMS()
        let deviceID = self.deviceID, registration = deviceRegistration
        DispatchQueue.main.async { [weak owner] in
            owner?.handleDeviceStatus(status, deviceID: deviceID, registration: registration, eventMS: eventMS)
        }
    }

    func deviceCharacteristicsDiscovered(_ device: IQDevice!) {
        guard device?.uuid == deviceID, let owner else { return }
        let eventMS = owner.runtime.nowMS()
        let deviceID = self.deviceID, registration = deviceRegistration
        DispatchQueue.main.async { [weak owner] in
            owner?.handleDeviceReady(deviceID: deviceID, registration: registration, eventMS: eventMS)
        }
    }
}

/// App listener bound to one app registration; every callback is re-posted to main.
private final class GarminAppMessageRelay: NSObject, IQAppMessageDelegate {
    let key: DeliveryKey
    let appRegistration: UInt64
    private weak var owner: BaseGarminManager?

    init(key: DeliveryKey, appRegistration: UInt64, owner: BaseGarminManager) {
        self.key = key
        self.appRegistration = appRegistration
        self.owner = owner
    }

    func receivedMessage(_ message: Any!, from app: IQApp!) {
        guard app?.uuid == key.appID, app?.device?.uuid == key.deviceID, let owner else { return }
        let key = self.key, registration = appRegistration
        DispatchQueue.main.async { [weak owner] in
            owner?.handleInboundMessage(message as Any, key: key, registration: registration)
        }
    }
}

// MARK: - BaseGarminManager

/// Concrete implementation of `GarminManager` that handles:
///  - Device registration/unregistration with Garmin ConnectIQ
///  - Data persistence for selected devices
///  - Generating & sending watch-state updates (glucose, IOB, COB, etc.) to Garmin watch apps.
///
/// Transport state is owned by the main queue; preparation stays on its own queues.
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

    /// JSON settings store, used here to read the glucose target profile.
    @Injected() private var fileStorage: FileStorage!

    @Injected() private var iobService: IOBService!
    @Injected() private var trioAlertManager: TrioAlertManager!

    /// Validates and executes watch commands; shared so its request-ID cache sees every request.
    @Injected() private var watchCommandProcessor: WatchCommandProcessor!

    /// Revoked by `BaseSettingsManager` itself; read here only to refresh the watch after a revocation.
    @Injected() private var watchCommandAuthorization: WatchCommandAuthorization!

    /// Persists the user's device list between app launches.
    @Persisted(key: "BaseGarminManager.persistedDevices") private var persistedDevices: [GarminDevice] = []

    /// Router for presenting alerts or navigation flows (injected via Swinject).
    private let router: Router

    /// Garmin ConnectIQ shared instance for watch interactions.
    private let connectIQ = ConnectIQ.sharedInstance()

    /// Registers and messages watch apps; the shared `connectIQ` unless a test injects a spy.
    private let connectIQClient: GarminConnectIQClient?

    let runtime: GarminTransportRuntime

    /// Wait before the single resend of a failed message.
    private let sendRetryDelay: TimeInterval

    /// Quiet period before a submitted watch state is broadcast.
    private let broadcastDebounce: TimeInterval = 2

    /// A set of Combine cancellables for managing the lifecycle of various subscriptions.
    private var cancellables = Set<AnyCancellable>()

    /// Holds a promise used when the user is selecting devices (via `showDeviceSelection()`).
    private var deviceSelectionPromise: Future<[IQDevice], Never>.Promise?

    /// Publishes the trigger name of every watch state refresh that is started.
    let stateRefreshTriggers = PassthroughSubject<String, Never>()

    /// Current glucose units, either mg/dL or mmol/L, read from user settings.
    private var units: GlucoseUnits = .mgdL

    /// Glucose color scheme, read from user settings and forwarded to watch apps
    /// that can color glucose themselves.
    private var glucoseColorScheme: GlucoseColorScheme = .staticColor

    // MARK: - Debug Logging

    /// Enable/disable watch state preparation and throttling logs:
    /// - Glucose/IOB received, waiting for determination
    /// - Determination arrived, cancelled timer
    /// - Preparing/Prepared watch state, Skipping - data unchanged
    /// - Settings throttle timer started/running/fired
    private let debugWatchState = true

    /// Enable/disable watch status and communication logs:
    /// - Registered watchface/datafield
    /// - Watchface/datafield config changed
    private let debugGarminEnabled = true

    /// Helper method for conditional watch status/comms logging.
    /// Logs messages only if debugGarminEnabled is true.
    /// - Parameter message: The debug message to log.
    private func debugGarmin(_ message: String) {
        guard debugGarminEnabled else { return }
        debug(.watch, message)
    }

    // MARK: - Transport State (main queue only)

    private var nextTransportToken: UInt64 = 0
    private var nextStateGeneration: UInt64 = 0
    private var deviceRegistrations: [UUID: GarminDeviceRegistration] = [:]
    private var appRegistrations: [DeliveryKey: GarminAppRegistration] = [:]
    /// Selected-device order, watchface first then configured datafields.
    private var deliveryOrder: [DeliveryKey] = []
    /// Set only from an accepted state `AppNotFound`.
    private var absentApps: Set<DeliveryKey> = []
    private var latestSubmittedState: GarminStateSnapshot?
    private var lastBroadcast: GarminStateSnapshot?
    private var pendingBroadcast: (token: UInt64, work: DispatchWorkItem)?
    /// Keyed by the first reply attempt ID.
    private var pendingReplyRetries: [UInt64: PendingReplyRetry] = [:]
    /// Gates link recovery only; delivery behaves the same in the background.
    private var isForegroundActive = false

    // MARK: - Send Diagnostics

    /// Snapshot of the launch decision; toggling the setting only changes the next launch.
    private(set) var stallHookStatus: GarminStallHookStatus = .off
    private var pendingSends: [GarminPendingSlot: GarminPendingSend] = [:]
    private var stallObservations: [DeliveryKey: GarminStallObservation] = [:]
    private var reconnectObservations: [UUID: GarminReconnectObservation] = [:]
    private var pendingDiagnosticsWork: (token: UInt64, work: DispatchWorkItem)?
    /// Lives as long as the app-lifetime manager, so it survives deselect and re-add.
    private var lastRestartGuidanceMS: UInt64?
    private let stallThresholdMS: UInt64 = 120_000
    private let observationWindowMS: UInt64 = 300_000
    private let restartGuidanceIntervalMS: UInt64 = 900_000

    // MARK: - Link Recovery

    private let requiredLinkFailures = 2
    private let linkRecoveryDelays: [TimeInterval] = [30, 60, 120, 240, 300]

    // MARK: - Deduplication

    /// Hash of last prepared data to skip redundant preparation
    private var lastPreparedDataHash: Int?
    private var lastPreparedWatchState: [GarminWatchState]?

    // MARK: - Glucose/Determination Coordination

    /// Delay before sending glucose if determination hasn't arrived (seconds)
    /// Based on log analysis: avg delay ~5s, max ~11s with new timer coordination
    private let glucoseFallbackDelay: TimeInterval = 10

    /// Pending glucose fallback task - cancelled if determination arrives first
    private var pendingGlucoseFallback: DispatchWorkItem?

    /// Serial queue owning `pendingGlucoseFallback` and `pendingSettingsUpdate`; only touch them on it
    private let timerQueue = DispatchQueue(label: "BaseGarminManager.timerQueue", qos: .utility)

    // MARK: - Settings Change Throttle

    /// Track previous Garmin settings to detect what specifically changed
    private var previousGarminSettings = GarminWatchSettings()

    /// Max carbs at the last settings notification; the complication caps its carbs picker with it.
    private var previousMaxCarbs: Decimal = 0

    /// Revocation epoch at the last settings notification; a newer one means a command setting was
    /// switched off since, even if the notification's settings show it back on.
    private var lastSeenCommandRevocation: UInt64 = 0

    /// Pending settings update task - waits for user to finish making changes
    private var pendingSettingsUpdate: DispatchWorkItem?

    /// Latest settings data to send when throttle timer fires
    private var pendingSettingsData: Data?

    /// How long to wait for additional settings changes before sending (seconds)
    private let settingsThrottleDuration: TimeInterval = 10

    // MARK: - CoreData & Subscriptions

    /// Queue for handling Core Data change notifications
    private let queue = DispatchQueue(label: "BaseGarminManager.queue", qos: .utility)

    /// Publishes any changed CoreData objects that match our filters (e.g., OrefDetermination, GlucoseStored).
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?

    /// Additional local subscriptions (separate from `cancellables`) for CoreData events.
    private var subscriptions = Set<AnyCancellable>()

    /// Represents the main (view) context for CoreData, typically used on the main thread.
    let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    /// Array of Garmin `IQDevice` objects currently tracked.
    /// Written only by `applyDeviceList` on main, read from timerQueue and watch state tasks.
    @SyncAccess private(set) var devices: [IQDevice] = []

    // MARK: - Initialization

    /// Creates a new `BaseGarminManager`, injecting required services, restoring any persisted devices,
    /// and setting up watchers for data changes (e.g., glucose updates).
    /// - Parameters:
    ///   - resolver: Swinject resolver for injecting dependencies like the Router.
    ///   - connectIQClient: Replaces the Connect IQ SDK for registration and sending.
    ///   - presetChanges: Replaces the Core Data preset change signal.
    ///   - sendRetryDelay: Wait before resending a failed message.
    ///   - runtime: Replaces the transport clock, timers and startup; defaults to `.detached` for an injected client.
    init(
        resolver: Resolver,
        connectIQClient: GarminConnectIQClient? = nil,
        presetChanges: AnyPublisher<Void, Never>? = nil,
        sendRetryDelay: TimeInterval = 2,
        runtime: GarminTransportRuntime? = nil
    ) {
        router = resolver.resolve(Router.self)!
        self.runtime = runtime ?? (connectIQClient == nil ? .live : .detached)
        self.connectIQClient = connectIQClient ?? ConnectIQ.sharedInstance()
        self.sendRetryDelay = sendRetryDelay
        super.init()
        injectServices(resolver)

        subscribeToOpenFromGarminConnect()

        units = settingsManager.settings.units
        glucoseColorScheme = settingsManager.settings.glucoseColorScheme
        previousGarminSettings = settingsManager.settings.garminSettings
        previousMaxCarbs = settingsManager.settings.maxCarbs
        lastSeenCommandRevocation = watchCommandAuthorization.current

        broadcaster.register(SettingsObserver.self, observer: self)
        // Glucose targets are not part of TrioSettings, so editing the target profile
        // notifies this observer rather than firing settingsDidChange.
        broadcaster.register(BGTargetsObserver.self, observer: self)

        // Upload flags change nothing the watchface shows.
        coreDataPublisher =
            CoreDataStack.shared.contentChangePublisher
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        // Glucose updates - start 20s fallback timer
        // When loop is working: determination arrives within ~5s, cancels timer, sends complete data
        // When loop is slow/failing: timer fires after 20s, sends glucose with stale loop data
        // This ensures watch gets fresh glucose even if loop doesn't complete
        glucoseStorage.updatePublisher
            .receive(on: timerQueue)
            .sink { [weak self] _ in
                self?.handleGlucoseUpdate()
            }
            .store(in: &subscriptions)

        // IOB updates - also wait for determination like glucose does
        iobService.iobPublisher
            .receive(on: timerQueue)
            .sink { [weak self] _ in
                self?.handleIOBUpdate()
            }
            .store(in: &subscriptions)

        registerHandlers(presetChanges: presetChanges)

        Foundation.NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.onMain { $0.handleApplicationActivity(isActive: false) } }
            .store(in: &cancellables)
        Foundation.NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.onMain { $0.handleApplicationActivity(isActive: true) } }
            .store(in: &cancellables)

        onMain { $0.startTransport() }
    }

    /// Runs inline on main, otherwise posts to main; never blocks the caller.
    private func onMain(_ work: @escaping (BaseGarminManager) -> Void) {
        if Thread.isMainThread {
            work(self)
        } else {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                work(self)
            }
        }
    }

    private func startTransport() {
        dispatchPrecondition(condition: .onQueue(.main))
        isForegroundActive = runtime.isApplicationActive()
        // read before the SDK initializes; the hook is never installed or removed later in this process
        if settingsManager.settings.garminSettings.isSendStallRecoveryEnabled {
            stallHookStatus = runtime.installStallRecovery()
        } else {
            stallHookStatus = .off
            debug(.watch, "Garmin send stall recovery disabled by settings for this launch")
        }
        if runtime.usesSharedConnectIQ {
            connectIQ?.initialize(withUrlScheme: "Trio", uiOverrideDelegate: self)
            restoreDevices()
        }
    }

    private func allocateToken() -> UInt64 {
        nextTransportToken += 1
        return nextTransportToken
    }

    // MARK: - Settings Helpers

    /// Returns the currently configured Garmin watchface from settings
    private var currentWatchface: GarminWatchface {
        settingsManager.settings.garminSettings.watchface
    }

    /// Returns the currently configured Garmin datafields from settings.
    /// Empty when the user has not selected any datafield.
    private var currentDatafields: [GarminDatafield] {
        settingsManager.settings.garminSettings.datafields
    }

    /// Returns the configured datafield registered under the given app UUID, if any
    private func datafield(for uuid: UUID) -> GarminDatafield? {
        currentDatafields.first { $0.datafieldUUID == uuid }
    }

    /// Returns whether watchface data transmission is enabled in settings
    private var isWatchfaceDataEnabled: Bool {
        settingsManager.settings.garminSettings.isWatchfaceDataEnabled
    }

    /// SwissAlpine watchface, the Loop Graph datafield and the complication app use
    /// historical glucose data (24 entries). Trio watchface only uses current reading.
    ///
    /// The complication app needs it for the 2 h graph in its own view; the complications
    /// it publishes read only element 0 and work without history.
    ///
    /// Note: the payload is built once and broadcast to every registered app, so enabling
    /// this for either app also sends the full array to the other. Both the Trio watchface
    /// and the Trio datafield read only element 0 and ignore the rest, and SwissAlpine caps
    /// at 24 entries — so 24 is the maximum that is safe to send here.
    private var needsHistoricalGlucoseData: Bool {
        currentWatchface == .swissalpine
            || currentWatchface == .complication
            || currentDatafields.contains(.loopgraph)
    }

    /// Returns the display name for an app UUID (watchface or datafield).
    /// Use this for routine log messages where UUID adds noise.
    private func appDisplayName(for uuid: UUID) -> String {
        if uuid == currentWatchface.watchfaceUUID {
            return "watchface:\(currentWatchface.displayName)"
        } else if let datafield = datafield(for: uuid) {
            return "datafield:\(datafield.displayName)"
        } else {
            return "unknown app"
        }
    }

    // MARK: - Internal Setup / Handlers

    /// Sets up handlers for OrefDetermination and GlucoseStored entity changes in CoreData.
    /// When these change, we re-compute the Garmin watch state and send updates to the watch.
    private func registerHandlers(presetChanges: AnyPublisher<Void, Never>?) {
        // edits and activations both land in these entities, and both change the watch's preset list
        let storedPresetChanges = coreDataPublisher.map { publisher in
            publisher.filteredByEntityName("OverrideStored")
                .merge(with: publisher.filteredByEntityName("TempTargetStored"))
                .map { _ in () }
                .eraseToAnyPublisher()
        }
        (presetChanges ?? storedPresetChanges)?
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.pushPresetsToComplications(triggeredBy: "PresetStorage")
            }
            .store(in: &subscriptions)

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
            .debounce(for: .milliseconds(500), scheduler: timerQueue)
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
                            .watch,
                            "Garmin glucose fallback fired, no determination within \(Int(self.glucoseFallbackDelay)) s"
                        )
                    }

                    let watchState = try await self.setupGarminWatchState(triggeredBy: "Glucose")
                    let watchStateData = try JSONEncoder().encode(watchState)
                    self.sendWatchStateData(watchStateData)
                } catch {
                    warning(.watch, "Garmin glucose fallback update failed", error: error)
                }
            }
        }

        pendingGlucoseFallback = fallback
        timerQueue.asyncAfter(deadline: .now() + glucoseFallbackDelay, execute: fallback)

        if debugWatchState {
            debug(.watch, "Garmin update waiting up to \(Int(glucoseFallbackDelay)) s for determination after new glucose")
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
                        debug(.watch, "Garmin IOB fallback fired, no determination within \(Int(self.glucoseFallbackDelay)) s")
                    }

                    let watchState = try await self.setupGarminWatchState(triggeredBy: "IOB")
                    let watchStateData = try JSONEncoder().encode(watchState)
                    self.sendWatchStateData(watchStateData)
                } catch {
                    warning(.watch, "Garmin IOB fallback update failed", error: error)
                }
            }
        }

        pendingGlucoseFallback = fallback
        timerQueue.asyncAfter(deadline: .now() + glucoseFallbackDelay, execute: fallback)

        if debugWatchState {
            debug(.watch, "Garmin update waiting up to \(Int(glucoseFallbackDelay)) s for determination after IOB change")
        }
    }

    /// Triggers watch state preparation and sends to debounce subject
    /// If triggered by Determination, cancels pending glucose fallback timer
    private func triggerWatchStateUpdate(triggeredBy trigger: String) {
        guard !devices.isEmpty else { return }
        stateRefreshTriggers.send(trigger)
        guard runtime.preparesWatchState else { return }

        // If determination arrived, cancel the glucose fallback timer
        // Determination includes both fresh glucose and loop data
        if trigger == "Determination" {
            timerQueue.async { [weak self] in
                guard let self = self, self.pendingGlucoseFallback != nil else { return }
                self.pendingGlucoseFallback?.cancel()
                self.pendingGlucoseFallback = nil
                if self.debugWatchState {
                    debug(.watch, "Garmin fallback cancelled, determination arrived")
                }
            }
        }

        Task {
            do {
                let watchState = try await setupGarminWatchState(triggeredBy: trigger)
                let watchStateData = try JSONEncoder().encode(watchState)
                sendWatchStateData(watchStateData)
            } catch {
                warning(.watch, "Preparing Garmin watch state failed, trigger \(trigger)", error: error)
            }
        }
    }

    /// Sends settings update with throttle - waits for user to finish making changes
    /// If timer already running, just updates data without rescheduling
    /// When timer fires, sends the latest collected data
    private func sendSettingsUpdateThrottled() {
        guard !devices.isEmpty else { return }
        timerQueue.async { [weak self] in
            self?.scheduleSettingsUpdate()
        }
    }

    private func scheduleSettingsUpdate() {
        // If timer already scheduled, just log and return - data will be fresh when timer fires
        if pendingSettingsUpdate != nil {
            if debugWatchState {
                debug(.watch, "Garmin settings update already scheduled")
            }
            return
        }

        // Create new throttled task
        let throttledTask = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            if self.debugWatchState {
                debug(.watch, "Sending throttled Garmin settings update")
            }

            Task {
                do {
                    let watchState = try await self.setupGarminWatchState(triggeredBy: "Settings")
                    let watchStateData = try JSONEncoder().encode(watchState)
                    self.sendWatchStateData(watchStateData)
                } catch {
                    warning(.watch, "Preparing Garmin settings update failed", error: error)
                }
            }

            // Clean up
            self.pendingSettingsUpdate = nil
            self.pendingSettingsData = nil
        }

        pendingSettingsUpdate = throttledTask
        timerQueue.asyncAfter(deadline: .now() + settingsThrottleDuration, execute: throttledTask)

        if debugWatchState {
            debug(.watch, "Garmin settings update scheduled in \(Int(settingsThrottleDuration)) s")
        }
    }

    // MARK: - CoreData Fetch Methods

    /// Fetches recent glucose readings from CoreData, up to specified limit.
    /// - Parameter limit: Maximum number of glucose entries to fetch (default: 2)
    /// - Returns: An array of `NSManagedObjectID`s for glucose readings.
    private func fetchGlucose(limit: Int = 2) async throws -> [NSManagedObjectID] {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "fetchGlucose"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.glucose,
            key: "date",
            ascending: false,
            fetchLimit: limit
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetchedResults.map(\.objectID)
        }
    }

    /// Fetches the most recent temporary basal rate from CoreData pump history.
    /// - Returns: An array containing the NSManagedObjectID of the latest temp basal event, if any.
    private func fetchTempBasals() async throws -> [NSManagedObjectID] {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "fetchTempBasals"
        // a scheduled-basal row is a rate assertion, not a running temp basal: with fetchLimit 1
        // it would otherwise become "the current temp basal" on the watch
        let tempBasalPredicate = NSPredicate(format: "tempBasal != nil AND tempBasal.isScheduledBasal == NO")
        let compoundPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate.pumpHistoryLast24h,
            tempBasalPredicate
        ])

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: compoundPredicate,
            key: "timestamp",
            ascending: false,
            fetchLimit: 1,
            relationshipKeyPathsForPrefetching: ["tempBasal"]
        )

        return try await context.perform {
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
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "fetchDeterminations30Min"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: context,
            predicate: NSPredicate.predicateFor30MinAgoForDetermination,
            key: "deliverAt",
            ascending: false,
            fetchLimit: 0 // No limit - get all determinations in 30min window
        )

        return try await context.perform {
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

        if debugWatchState {
            debug(.watch, "Preparing Garmin watch state, trigger \(triggeredBy)")
        }

        // Fetch glucose - SwissAlpine needs 24, Trio needs 2 (for delta calculation)
        let glucoseLimit = needsHistoricalGlucoseData ? 24 : 2
        let glucoseIds = try await fetchGlucose(limit: glucoseLimit)

        // Fetch all determinations from last 30 minutes (no limit)
        // This ensures we get both enacted and suggested determinations
        let allDeterminationIds = try await fetchDeterminations30Min()

        let tempBasalIds = try await fetchTempBasals()

        // Scheduled profile target only, matching the Home chart -- overrides and temp
        // targets are not reflected.
        let bgTargets = await fileStorage.retrieveAsync(OpenAPS.Settings.bgTargets, as: BGTargets.self)
            ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
            ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
        let targetGlucoseValue = bgTargets.currentTarget().map { Int16(truncating: $0 as NSDecimalNumber) }

        // Extract all needed values from self before entering perform block (Sendable compliance)
        let unitsValue = units
        let iobValue = formatIOB(iobService.currentIOB ?? Decimal(0))
        let basalProfile = settingsManager.preferences.basalProfile as? [BasalProfileEntry] ?? []
        let displayPrimaryChoice = settingsManager.settings.garminSettings.primaryAttributeChoice.rawValue
        let displaySecondaryChoice = settingsManager.settings.garminSettings.secondaryAttributeChoice.rawValue
        // Short form, not the enum raw value: this is the wire format the watchface reads.
        let colorSchemeValue = glucoseColorScheme == .dynamicColor ? "dynamic" : "static"
        let needsHistoricalData = needsHistoricalGlucoseData
        let shouldDebug = debugWatchState
        let previousHash = lastPreparedDataHash
        let previousWatchState = lastPreparedWatchState

        // Capture context locally for use in perform block
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "setupGarminWatchState"

        let watchStates = await context.perform {
            // Fetch Core Data objects inside perform block
            let glucoseObjects = glucoseIds.compactMap { context.object(with: $0) as? GlucoseStored }
            let allDeterminationObjects = allDeterminationIds.compactMap { context.object(with: $0) as? OrefDetermination }
            let tempBasalObjects = tempBasalIds.compactMap { context.object(with: $0) as? PumpEventStored }
            var watchStates: [GarminWatchState] = []

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

                // Tai sends the AutoISF ratio - the "final" factor from the autoISF
                // calculations screen, the same number the home header shows as
                // aiSR. NOT sensitivityRatio, which carries only the autosens
                // value and sits at 1.0 while AutoISF does the adjusting.
                //
                // Upstream Trio has no AutoISF, so it reads sensitivityRatio here;
                // that upstream form arrived with the updateGarmin rewrite and
                // left every Garmin app showing 1.0.
                sensRatioValue = Double(truncating: latestDetermination.autoISFratio ?? 1)

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
                    watchState.glucoseColorScheme = colorSchemeValue
                    watchState.targetGlucose = targetGlucoseValue
                }

                watchStates.append(watchState)
            }

            // Deduplicate: Check if data is unchanged from last preparation
            let currentHash = watchStates.hashValue
            if currentHash == previousHash {
                if shouldDebug {
                    debug(.watch, "Garmin watch state unchanged")
                }
                return previousWatchState ?? watchStates
            }

            if shouldDebug {
                let iobFormatted = String(format: "%.1f", watchStates.first?.iob ?? 0)
                let cobFormatted = String(format: "%.0f", watchStates.first?.cob ?? 0)
                let tbrFormatted = String(format: "%.2f", watchStates.first?.tbr ?? 0)
                let sensRatioFormatted = String(format: "%.2f", watchStates.first?.sensRatio ?? 0)
                let targetFormatted = watchStates.first?.targetGlucose.map { "\($0)" } ?? "none"
                debug(
                    .watch,
                    "Garmin watch state prepared: \(watchStates.count) entries, BG \(watchStates.first?.sgv ?? 0), IOB \(iobFormatted) U, COB \(cobFormatted) g, temp basal \(tbrFormatted) U/h, eventual BG \(watchStates.first?.eventualBG ?? 0), sensitivity ratio \(sensRatioFormatted), color scheme \(watchStates.first?.glucoseColorScheme ?? "none"), target \(targetFormatted)"
                )
            }

            return watchStates
        }

        // Cache for deduplication (outside perform block)
        lastPreparedDataHash = watchStates.hashValue
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

    /// The apps to register on every selected device: the watchface when enabled, then configured datafields.
    private func configuredTargets() -> [GarminDeliveryTarget] {
        let settings = settingsManager.settings.garminSettings
        var targets: [GarminDeliveryTarget] = []
        if settings.isWatchfaceDataEnabled, let uuid = settings.watchface.watchfaceUUID {
            targets.append(GarminDeliveryTarget(appID: uuid, kind: .watchface, label: "watchface.\(settings.watchface.rawValue)"))
        } else if !settings.isWatchfaceDataEnabled {
            debugGarmin("Garmin watchface data disabled, watchface not registered")
        }
        for datafield in GarminDatafield.sanitizedSelection(settings.datafields) {
            guard let uuid = datafield.datafieldUUID else { continue }
            targets.append(GarminDeliveryTarget(appID: uuid, kind: .datafield, label: "datafield.\(datafield.rawValue)"))
        }
        var seen = Set<UUID>()
        return targets.filter { seen.insert($0.appID).inserted }
    }

    /// The only writer of `devices`: normalizes the selection, persists it and reconciles registrations.
    private func applyDeviceList(_ selection: [IQDevice]) {
        dispatchPrecondition(condition: .onQueue(.main))
        var seen = Set<UUID>()
        let normalized = selection.filter { device in
            guard let uuid = device.uuid else { return false }
            return seen.insert(uuid).inserted
        }
        devices = normalized
        if runtime.usesSharedConnectIQ {
            persistedDevices = normalized.map(GarminDevice.init)
        }
        if registerDevices(normalized) {
            triggerWatchStateUpdate(triggeredBy: "GarminRegistration")
        }
    }

    /// Reconciles device and app listeners with the selection and configuration.
    /// Records are published or retired before any SDK call, so a callback raised inline never sees a half state.
    /// - Returns: Whether a device was added or an app configuration changed, which needs fresh watch state.
    @discardableResult private func registerDevices(_ selected: [IQDevice]) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))
        let selectedIDs = Set(selected.compactMap(\.uuid))
        let targets = configuredTargets()
        var removedApps: [(IQApp, GarminAppMessageRelay)] = []
        var removedDevices: [(IQDevice, GarminDeviceEventRelay)] = []
        var addedDevices: [(IQDevice, GarminDeviceEventRelay)] = []
        var addedApps: [(IQApp, GarminAppMessageRelay, String)] = []
        var reconfiguredDevices: Set<UUID> = []

        for deviceID in deviceRegistrations.keys where !selectedIDs.contains(deviceID) {
            for key in appRegistrations.keys where key.deviceID == deviceID {
                if let record = retireApp(key) { removedApps.append((record.app, record.relay)) }
            }
            if let record = retireDevice(deviceID) { removedDevices.append((record.device, record.relay)) }
        }

        for device in selected {
            guard let deviceID = device.uuid else { continue }
            let isNewDevice = deviceRegistrations[deviceID] == nil
            if isNewDevice {
                let registration = allocateToken()
                let relay = GarminDeviceEventRelay(deviceID: deviceID, deviceRegistration: registration, owner: self)
                deviceRegistrations[deviceID] = GarminDeviceRegistration(
                    device: device,
                    selectionToken: allocateToken(),
                    deviceRegistration: registration,
                    relay: relay
                )
                addedDevices.append((device, relay))
            }
            guard let runtimeDevice = deviceRegistrations[deviceID]?.device else { continue }

            let wantedKeys = Set(targets.map { DeliveryKey(deviceID: deviceID, appID: $0.appID) })
            for key in appRegistrations.keys where key.deviceID == deviceID && !wantedKeys.contains(key) {
                if let record = retireApp(key) {
                    removedApps.append((record.app, record.relay))
                    reconfiguredDevices.insert(deviceID)
                }
            }
            for target in targets {
                let key = DeliveryKey(deviceID: deviceID, appID: target.appID)
                guard appRegistrations[key] == nil,
                      let app = IQApp(uuid: target.appID, store: UUID(), device: runtimeDevice)
                else { continue }
                let registration = allocateToken()
                let relay = GarminAppMessageRelay(key: key, appRegistration: registration, owner: self)
                appRegistrations[key] = GarminAppRegistration(
                    app: app,
                    relay: relay,
                    appRegistration: registration,
                    kind: target.kind,
                    appLabel: target.label,
                    owedState: lastBroadcast != nil
                )
                addedApps.append((app, relay, target.label))
                if !isNewDevice { reconfiguredDevices.insert(deviceID) }
            }
        }

        deliveryOrder = selected.compactMap(\.uuid).flatMap { deviceID in
            targets.map { DeliveryKey(deviceID: deviceID, appID: $0.appID) }
        }.filter { appRegistrations[$0] != nil }

        for deviceID in reconfiguredDevices {
            invalidateRecovery(deviceID, resetStep: true)
        }

        if deviceRegistrations.isEmpty {
            cancelBroadcastDebounce()
            latestSubmittedState = nil
            lastBroadcast = nil
        }

        // the SDK listener of a removed app is released before its device listener
        for (app, relay) in removedApps {
            connectIQClient?.unregisterApp(app, delegate: relay)
        }
        for (device, relay) in removedDevices {
            connectIQClient?.unregisterDevice(device, delegate: relay)
        }
        for (device, relay) in addedDevices {
            connectIQClient?.registerDevice(device, delegate: relay)
        }
        for (app, relay, label) in addedApps {
            debugGarmin("Registered Garmin \(label)")
            connectIQClient?.registerApp(app, delegate: relay)
        }

        return !addedDevices.isEmpty || !reconfiguredDevices.isEmpty
    }

    /// Removes an app record and every pending piece of work bound to it.
    private func retireApp(_ key: DeliveryKey) -> GarminAppRegistration? {
        guard let record = appRegistrations.removeValue(forKey: key) else { return nil }
        record.stateRetry?.work.cancel()
        absentApps.remove(key)
        cancelReplyRetries { $0.appRegistration == record.appRegistration }
        clearPendingSends { $0.key == key }
        closeStallObservation(key, success: nil, reason: "invalidated")
        return record
    }

    private func retireDevice(_ deviceID: UUID) -> GarminDeviceRegistration? {
        guard let record = deviceRegistrations.removeValue(forKey: deviceID) else { return nil }
        record.recovery.recoveryWork?.work.cancel()
        cancelReplyRetries { $0.key.deviceID == deviceID }
        closeReconnectObservation(deviceID, outcome: nil, reason: "deselected")
        return record
    }

    private func cancelReplyRetries(where matches: (PendingReplyRetry) -> Bool) {
        for (attemptID, retry) in pendingReplyRetries where matches(retry) {
            retry.work.cancel()
            pendingReplyRetries[attemptID] = nil
        }
    }

    /// Drops a still-debouncing submission prepared for the old app configuration.
    private func discardPendingSubmission() {
        guard latestSubmittedState?.generation != lastBroadcast?.generation else { return }
        cancelBroadcastDebounce()
        latestSubmittedState = lastBroadcast
    }

    /// Restores previously persisted devices from local storage into `devices`.
    private func restoreDevices() {
        applyDeviceList(persistedDevices.map(\.iqDevice))
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
                self.onMain { $0.parseDevices(for: url) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Parsing & Broadcasting

    /// Parses devices from a Garmin Connect URL and updates our `devices` property.
    /// - Parameter url: The URL provided by Garmin Connect containing device selection info.
    private func parseDevices(for url: URL) {
        let parsed = connectIQ?.parseDeviceSelectionResponse(from: url) as? [IQDevice]
        applyDeviceList(parsed ?? [])
        deviceSelectionPromise?(.success(devices))
        deviceSelectionPromise = nil
    }

    /// Canonicalizes a submitted state and restarts the broadcast debounce, also for identical input.
    private func submitWatchState(_ data: Data) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let payload = try? JSONSerialization.jsonObject(with: data, options: []),
              let canonicalData = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        else {
            warning(.watch, "Garmin watch state is not valid JSON")
            return
        }
        let generation: UInt64
        if let latest = latestSubmittedState, latest.canonicalData == canonicalData {
            generation = latest.generation
        } else {
            nextStateGeneration += 1
            generation = nextStateGeneration
        }
        latestSubmittedState = GarminStateSnapshot(generation: generation, canonicalData: canonicalData, payload: payload)

        pendingBroadcast?.work.cancel()
        let token = allocateToken()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pendingBroadcast?.token == token else { return }
            self.pendingBroadcast = nil
            self.broadcastWatchStateData(generation: generation)
        }
        pendingBroadcast = (token, work)
        runtime.schedule(after: broadcastDebounce, work)
    }

    private func cancelBroadcastDebounce() {
        pendingBroadcast?.work.cancel()
        pendingBroadcast = nil
    }

    /// Takes the debounced snapshot as the state every registered app owes, then sends where eligible.
    private func broadcastWatchStateData(generation: UInt64) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let snapshot = latestSubmittedState, snapshot.generation == generation else { return }
        lastBroadcast = snapshot
        for key in deliveryOrder {
            guard var record = appRegistrations[key] else { continue }
            record.awaitsNextBroadcast = false
            record.owedState = record.lastDeliveredState != snapshot.canonicalData
            appRegistrations[key] = record
        }
        flushOwedState()
    }

    private func flushOwedState(on deviceID: UUID? = nil) {
        for key in deliveryOrder where deviceID == nil || key.deviceID == deviceID {
            offerOwedState(to: key)
        }
    }

    /// The newest debounced snapshot, unless a newer submission is still waiting on the debounce.
    private var eligibleSnapshot: GarminStateSnapshot? {
        guard let snapshot = lastBroadcast, latestSubmittedState?.generation == snapshot.generation else { return nil }
        return snapshot
    }

    /// Starts a first state attempt when the key owes the latest state and nothing blocks it.
    /// No status preflight or ready gate: an unknown link is tried right away.
    private func offerOwedState(to key: DeliveryKey) {
        guard var record = appRegistrations[key], record.owedState, !record.awaitsNextBroadcast,
              record.stateAttempt == nil, record.stateRetry == nil,
              let device = deviceRegistrations[key.deviceID], device.linkStatus != .disconnected,
              !absentApps.contains(key),
              let snapshot = eligibleSnapshot
        else { return }
        if record.lastDeliveredState == snapshot.canonicalData {
            record.owedState = false
            appRegistrations[key] = record
            return
        }
        startStateAttempt(key, snapshot: snapshot, retryOf: nil)
    }

    private func startStateAttempt(_ key: DeliveryKey, snapshot: GarminStateSnapshot, retryOf: UInt64?) {
        guard let client = connectIQClient, var record = appRegistrations[key],
              let device = deviceRegistrations[key.deviceID]
        else { return }
        let context = GarminSendContext(
            key: key,
            kind: .state,
            selectionToken: device.selectionToken,
            deviceRegistration: device.deviceRegistration,
            linkEpoch: device.linkEpoch,
            appRegistration: record.appRegistration,
            appLabel: record.appLabel,
            payloadID: snapshot.generation,
            attemptID: allocateToken(),
            retryOf: retryOf,
            startMS: runtime.nowMS()
        )
        // marked before entering the SDK, whose completion may run inline
        record.stateAttempt = StateAttempt(
            context: context,
            canonicalData: snapshot.canonicalData,
            proofEpoch: device.recovery.proofEpoch
        )
        appRegistrations[key] = record
        submit(snapshot.payload, to: record.app, context: context, client: client)
    }

    /// The one SDK send path for state and replies; completions are always re-posted to main.
    private func submit(_ message: Any, to app: IQApp, context: GarminSendContext, client: GarminConnectIQClient) {
        logGarminTransportEvent("send.start", at: context.startMS, context.fields)
        let slot = GarminPendingSlot(key: context.key, kind: context.kind)
        if context.kind == .state || pendingSends[slot] == nil {
            pendingSends[slot] = GarminPendingSend(context: context)
            scheduleDiagnosticsSweep()
        }
        let gate = GarminCompletionGate()
        let runtime = self.runtime
        client.send(message, to: app) { [weak self] result in
            let resultMS = runtime.nowMS()
            DispatchQueue.main.async { [weak self] in
                guard let self, !gate.isConsumed else { return }
                gate.isConsumed = true
                self.handleSendCompletion(result, context: context, resultMS: resultMS, message: message)
            }
        }
    }

    private func handleSendCompletion(
        _ result: IQSendMessageResult,
        context: GarminSendContext,
        resultMS: UInt64,
        message: Any
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        let accepted = isCurrent(context)
        logGarminTransportEvent("send.result", at: resultMS, context.fields + [
            ("result_ms", String(resultMS)),
            ("elapsed_ms", String(resultMS >= context.startMS ? resultMS - context.startMS : 0)),
            ("sdk_result", Self.sdkResultLabel(result.rawValue)),
            ("sdk_raw", String(result.rawValue)),
            ("accepted", String(accepted))
        ])
        let slot = GarminPendingSlot(key: context.key, kind: context.kind)
        var pending: GarminPendingSend?
        if pendingSends[slot]?.context.attemptID == context.attemptID {
            pending = pendingSends.removeValue(forKey: slot)
            scheduleDiagnosticsSweep()
        }
        guard accepted else { return }
        if result == .success {
            closeStallObservation(context.key, success: (context, resultMS), reason: "observed")
            closeReconnectObservation(context.key.deviceID, outcome: ("sdk_success", resultMS), reason: "observed")
        } else if result.rawValue == Self.timeoutRaw, pending?.episodeOpened != true {
            openStallObservation(context, source: "sdk_timeout", atMS: resultMS)
        }
        switch context.kind {
        case .state:
            handleStateCompletion(result, context: context)
        case .targeted:
            handleTargetedCompletion(result, context: context, message: message)
        }
    }

    private func isCurrent(_ context: GarminSendContext) -> Bool {
        guard let record = appRegistrations[context.key], record.appRegistration == context.appRegistration,
              let device = deviceRegistrations[context.key.deviceID], device.linkEpoch == context.linkEpoch
        else { return false }
        switch context.kind {
        case .state:
            return device.deviceRegistration == context.deviceRegistration
                && record.stateAttempt?.context.attemptID == context.attemptID
        case .targeted:
            return true
        }
    }

    private func handleStateCompletion(_ result: IQSendMessageResult, context: GarminSendContext) {
        let key = context.key
        guard var record = appRegistrations[key], let attempt = record.stateAttempt else { return }
        record.stateAttempt = nil

        if result == .success {
            record.lastDeliveredState = attempt.canonicalData
            // an older success records what physically arrived but cannot settle newer bytes
            if let snapshot = lastBroadcast, snapshot.canonicalData == attempt.canonicalData {
                record.owedState = false
            }
            appRegistrations[key] = record
            markLinkProof(key.deviceID)
            offerOwedState(to: key)
            return
        }

        record.owedState = lastBroadcast.map { record.lastDeliveredState != $0.canonicalData } ?? true
        if result.rawValue == Self.appNotFoundRaw {
            appRegistrations[key] = record
            absentApps.insert(key)
            classifyFinalStateResult(result, attempt: attempt, kind: record.kind)
            return
        }

        guard context.retryOf == nil else {
            // final failure: a newer debounced state blocked by this attempt gets one new first attempt
            appRegistrations[key] = record
            classifyFinalStateResult(result, attempt: attempt, kind: record.kind)
            if let snapshot = eligibleSnapshot, snapshot.generation != context.payloadID {
                offerOwedState(to: key)
            }
            return
        }

        let workToken = allocateToken()
        let work = DispatchWorkItem { [weak self] in
            self?.retryState(key, workToken: workToken)
        }
        record.stateRetry = ScheduledStateRetry(
            work: work,
            workToken: workToken,
            originAttemptID: context.attemptID,
            deviceRegistration: context.deviceRegistration,
            linkEpoch: context.linkEpoch,
            appRegistration: context.appRegistration
        )
        appRegistrations[key] = record
        runtime.schedule(after: sendRetryDelay, work)
    }

    /// Resends the newest debounced snapshot once; never the old one while a newer submission is debouncing.
    private func retryState(_ key: DeliveryKey, workToken: UInt64) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard var record = appRegistrations[key], let retry = record.stateRetry, retry.workToken == workToken,
              record.appRegistration == retry.appRegistration,
              let device = deviceRegistrations[key.deviceID],
              device.deviceRegistration == retry.deviceRegistration, device.linkEpoch == retry.linkEpoch
        else { return }
        record.stateRetry = nil
        appRegistrations[key] = record

        guard device.linkStatus != .disconnected, !absentApps.contains(key), let snapshot = eligibleSnapshot else { return }
        if record.lastDeliveredState == snapshot.canonicalData {
            record.owedState = false
            appRegistrations[key] = record
            return
        }
        startStateAttempt(key, snapshot: snapshot, retryOf: retry.originAttemptID)
    }

    // MARK: - Link Events

    fileprivate func handleDeviceStatus(_ status: IQDeviceStatus, deviceID: UUID, registration: UInt64, eventMS: UInt64) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard var device = deviceRegistrations[deviceID], device.deviceRegistration == registration else { return }

        let label: String
        switch status {
        case .invalidDevice: label = "invalidDevice"
        case .bluetoothNotReady: label = "bluetoothNotReady"
        case .notFound: label = "notFound"
        case .notConnected: label = "notConnected"
        case .connected: label = "connected"
        @unknown default: label = "unknown"
        }
        let isRepeat = device.lastStatusLog?.raw == status.rawValue
        if !isRepeat || device.lastStatusLog.map({ eventMS >= $0.atMS + Self.repeatedEventLogIntervalMS }) == true {
            device.lastStatusLog = (status.rawValue, eventMS)
            deviceRegistrations[deviceID] = device
            logGarminTransportEvent("device.status", at: eventMS, [
                ("device_id", String(device.selectionToken)),
                ("link_epoch", String(device.linkEpoch)),
                ("status", label),
                ("sdk_raw", String(status.rawValue))
            ])
        }

        switch status {
        case .bluetoothNotReady,
             .invalidDevice,
             .notConnected,
             .notFound:
            if device.linkStatus != .disconnected {
                markLinkLost(deviceID)
            }
        case .connected:
            if device.linkStatus == .disconnected {
                reopenLink(deviceID)
            } else if device.linkStatus == .unknown {
                deviceRegistrations[deviceID]?.linkStatus = .connected
            }
            resumePendingEvaluation(on: deviceID)
        @unknown default:
            invalidateRecovery(deviceID)
        }
    }

    fileprivate func handleDeviceReady(deviceID: UUID, registration: UInt64, eventMS: UInt64) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let device = deviceRegistrations[deviceID], device.deviceRegistration == registration else { return }
        if device.linkStatus == .disconnected {
            // a late ready after a confirmed loss only counts while the SDK still reports the link up
            guard connectIQClient?.deviceStatus(of: device.device) == .connected,
                  deviceRegistrations[deviceID]?.deviceRegistration == registration
            else { return }
            reopenLink(deviceID)
        } else {
            deviceRegistrations[deviceID]?.linkStatus = .connected
        }

        guard var current = deviceRegistrations[deviceID] else { return }
        let isFirst = current.readyLog.map {
            $0.deviceRegistration != current.deviceRegistration || $0.linkEpoch != current.linkEpoch
        } ?? true
        if isFirst || current.readyLog.map({ eventMS >= $0.atMS + Self.repeatedEventLogIntervalMS }) == true {
            current.readyLog = (current.deviceRegistration, current.linkEpoch, eventMS)
            deviceRegistrations[deviceID] = current
            logGarminTransportEvent("device.ready", at: eventMS, [
                ("device_id", String(current.selectionToken)),
                ("link_epoch", String(current.linkEpoch))
            ])
        }
        markLinkProof(deviceID)
        closeReconnectObservation(deviceID, outcome: ("ready", eventMS), reason: "observed")
        resumePendingEvaluation(on: deviceID)

        flushOwedState(on: deviceID)
        triggerWatchStateUpdate(triggeredBy: "DeviceReady")
    }

    /// A known loss: retire this link's attempts and confirmed bytes so the latest state is owed again.
    private func markLinkLost(_ deviceID: UUID) {
        guard var device = deviceRegistrations[deviceID] else { return }
        device.linkStatus = .disconnected
        device.linkEpoch += 1
        deviceRegistrations[deviceID] = device
        invalidateRecovery(deviceID)
        resetDelivery(on: deviceID)
    }

    private func reopenLink(_ deviceID: UUID) {
        deviceRegistrations[deviceID]?.linkStatus = .connected
        absentApps = absentApps.filter { $0.deviceID != deviceID }
        flushOwedState(on: deviceID)
    }

    /// Clears attempts, reserved retries and confirmed bytes of one device; other devices keep theirs.
    private func resetDelivery(on deviceID: UUID) {
        for key in deliveryOrder where key.deviceID == deviceID {
            guard var record = appRegistrations[key] else { continue }
            record.stateRetry?.work.cancel()
            record.stateRetry = nil
            record.stateAttempt = nil
            record.lastDeliveredState = nil
            record.owedState = lastBroadcast != nil
            appRegistrations[key] = record
        }
        cancelReplyRetries { $0.key.deviceID == deviceID }
        clearPendingSends { $0.key.deviceID == deviceID }
    }

    // MARK: - Link Recovery

    func handleApplicationActivity(isActive: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isActive != isForegroundActive else { return }
        isForegroundActive = isActive
        guard !isActive else { return }
        // attempts started before going inactive cannot bank evidence once active again
        for deviceID in deviceRegistrations.keys {
            invalidateRecovery(deviceID, bumpProof: true)
        }
    }

    /// Positive evidence that the link works: drops the streak and any armed recovery, resets the backoff.
    private func markLinkProof(_ deviceID: UUID) {
        guard var device = deviceRegistrations[deviceID] else { return }
        device.recovery.recoveryWork?.work.cancel()
        device.recovery = LinkRecoveryState(proofEpoch: device.recovery.proofEpoch + 1)
        deviceRegistrations[deviceID] = device
    }

    /// Drops the streak and armed work; the backoff step survives unless the configuration changed.
    private func invalidateRecovery(_ deviceID: UUID, resetStep: Bool = false, bumpProof: Bool = false) {
        guard var device = deviceRegistrations[deviceID] else { return }
        device.recovery.recoveryWork?.work.cancel()
        device.recovery.recoveryWork = nil
        device.recovery.failures = []
        if resetStep { device.recovery.backoffStep = 0 }
        if bumpProof { device.recovery.proofEpoch += 1 }
        deviceRegistrations[deviceID] = device
    }

    /// Only a final watchface-class state result can bank evidence, and only DeviceNotAvailable or MaxRetries.
    /// Timeout stays diagnostic: an HFP call cannot be told apart from a broken link.
    private func classifyFinalStateResult(_ result: IQSendMessageResult, attempt: StateAttempt, kind: GarminAppKind) {
        let deviceID = attempt.context.key.deviceID
        guard var device = deviceRegistrations[deviceID], attempt.proofEpoch == device.recovery.proofEpoch else { return }
        let qualifies = kind == .watchface
            && (result.rawValue == Self.deviceNotAvailableRaw || result.rawValue == Self.maxRetriesRaw)
        guard qualifies else {
            device.recovery.recoveryWork?.work.cancel()
            device.recovery.recoveryWork = nil
            device.recovery.failures = []
            deviceRegistrations[deviceID] = device
            return
        }
        guard device.recovery.failures.count < requiredLinkFailures else { return }
        device.recovery.failures.append(result)
        deviceRegistrations[deviceID] = device
        if device.recovery.failures.count == requiredLinkFailures {
            scheduleLinkRecovery(deviceID)
        }
    }

    private func canRecoverLink(_ device: GarminDeviceRegistration) -> Bool {
        isForegroundActive && device.linkStatus == .connected && connectIQClient != nil
            && deliveryOrder.contains { $0.deviceID == device.device.uuid && appRegistrations[$0]?.kind == .watchface }
    }

    private func scheduleLinkRecovery(_ deviceID: UUID) {
        guard var device = deviceRegistrations[deviceID], device.recovery.recoveryWork == nil,
              device.recovery.failures.count == requiredLinkFailures
        else { return }
        guard canRecoverLink(device) else {
            invalidateRecovery(deviceID)
            return
        }
        let step = min(device.recovery.backoffStep, linkRecoveryDelays.count - 1)
        let delay = linkRecoveryDelays[step]
        let token = allocateToken()
        let work = DispatchWorkItem { [weak self] in
            self?.recoverLink(deviceID, token: token)
        }
        device.recovery.recoveryWork = ScheduledLinkRecovery(
            work: work,
            token: token,
            deviceRegistration: device.deviceRegistration,
            linkEpoch: device.linkEpoch,
            proofEpoch: device.recovery.proofEpoch,
            results: device.recovery.failures,
            step: step,
            delay: delay
        )
        deviceRegistrations[deviceID] = device
        runtime.schedule(after: delay, work)
    }

    private func armedRecovery(_ deviceID: UUID, token: UInt64) -> (GarminDeviceRegistration, ScheduledLinkRecovery)? {
        guard let device = deviceRegistrations[deviceID], let recovery = device.recovery.recoveryWork,
              recovery.token == token, recovery.deviceRegistration == device.deviceRegistration,
              recovery.linkEpoch == device.linkEpoch, recovery.proofEpoch == device.recovery.proofEpoch,
              device.recovery.failures.count == requiredLinkFailures, canRecoverLink(device)
        else { return nil }
        return (device, recovery)
    }

    /// Samples the public status, then decides on the next main turn, after any callback the sample raised inline.
    private func recoverLink(_ deviceID: UUID, token: UInt64) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard case let (device, _)? = armedRecovery(deviceID, token: token), let client = connectIQClient else { return }
        let status = client.deviceStatus(of: device.device)
        DispatchQueue.main.async { [weak self] in
            self?.reconnectDevice(deviceID, token: token, sampledStatus: status)
        }
    }

    /// One device-only unregister/register pair; app listeners and `IQApp` objects stay as they are.
    private func reconnectDevice(_ deviceID: UUID, token: UInt64, sampledStatus: IQDeviceStatus) {
        guard case let (device, recovery)? = armedRecovery(deviceID, token: token), let client = connectIQClient else { return }
        guard sampledStatus == .connected else {
            invalidateRecovery(deviceID)
            return
        }

        let oldRelay = device.relay
        let registration = allocateToken()
        let newRelay = GarminDeviceEventRelay(deviceID: deviceID, deviceRegistration: registration, owner: self)
        var updated = device
        updated.deviceRegistration = registration
        updated.relay = newRelay
        updated.linkEpoch += 1
        updated.linkStatus = .unknown
        updated.recovery.recoveryWork = nil
        updated.recovery.failures = []
        updated.recovery.backoffStep = min(recovery.step + 1, linkRecoveryDelays.count - 1)
        deviceRegistrations[deviceID] = updated
        resetDelivery(on: deviceID)
        absentApps = absentApps.filter { $0.deviceID != deviceID }

        logGarminTransportEvent("reconnect.start", at: runtime.nowMS(), [
            ("device_id", String(device.selectionToken)),
            ("link_epoch", String(device.linkEpoch)),
            ("recovery_id", String(recovery.token)),
            ("trigger", "final_link_failures"),
            ("result_1", Self.sdkResultLabel(recovery.results[0].rawValue)),
            ("result_2", Self.sdkResultLabel(recovery.results[1].rawValue)),
            ("backoff_step", String(recovery.step)),
            ("delay_s", String(Int(recovery.delay)))
        ])

        let startMS = runtime.nowMS()
        closeReconnectObservation(deviceID, outcome: nil, reason: "superseded")
        reconnectObservations[deviceID] = GarminReconnectObservation(
            selectionToken: device.selectionToken,
            recoveryID: recovery.token,
            startMS: startMS
        )
        scheduleDiagnosticsSweep()

        client.unregisterDevice(device.device, delegate: oldRelay)
        client.registerDevice(device.device, delegate: newRelay)

        // never re-armed here: the next step needs two fresh final failures on the new link
        DispatchQueue.main.async { [weak self] in
            guard let self, self.deviceRegistrations[deviceID]?.deviceRegistration == registration else { return }
            self.flushOwedState(on: deviceID)
        }
    }

    // MARK: - Send Diagnostics

    private func clearPendingSends(where matches: (GarminPendingSlot) -> Bool) {
        let slots = pendingSends.keys.filter(matches)
        guard !slots.isEmpty else { return }
        slots.forEach { pendingSends[$0] = nil }
        scheduleDiagnosticsSweep()
    }

    private func isCurrentRegistration(_ context: GarminSendContext) -> Bool {
        guard let record = appRegistrations[context.key], record.appRegistration == context.appRegistration,
              let device = deviceRegistrations[context.key.deviceID]
        else { return false }
        return device.deviceRegistration == context.deviceRegistration && device.linkEpoch == context.linkEpoch
    }

    /// Arms one timer for the earliest diagnostic deadline; none while nothing is pending or observed.
    private func scheduleDiagnosticsSweep() {
        pendingDiagnosticsWork?.work.cancel()
        pendingDiagnosticsWork = nil
        let deadlines = pendingSends.values.filter { $0.evaluation == .waitingForDeadline }
            .map { $0.context.startMS + stallThresholdMS }
            + stallObservations.values.map { $0.openedMS + observationWindowMS }
            + reconnectObservations.values.map { $0.startMS + observationWindowMS }
        guard let earliest = deadlines.min() else { return }
        let now = runtime.nowMS()
        let token = allocateToken()
        let work = DispatchWorkItem { [weak self] in
            self?.sweepGarminDiagnostics(token: token)
        }
        pendingDiagnosticsWork = (token, work)
        runtime.schedule(after: earliest > now ? TimeInterval(earliest - now) / 1000 : 0, work)
    }

    /// Closes expired observations and samples the link for sends pending past the threshold.
    /// Never fails, retries or re-registers anything.
    private func sweepGarminDiagnostics(token: UInt64) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard pendingDiagnosticsWork?.token == token else { return }
        pendingDiagnosticsWork = nil
        let now = runtime.nowMS()

        for (key, observation) in stallObservations where now >= observation.openedMS + observationWindowMS {
            closeStallObservation(key, success: nil, reason: "window_expired")
        }
        for (deviceID, observation) in reconnectObservations where now >= observation.startMS + observationWindowMS {
            closeReconnectObservation(deviceID, outcome: nil, reason: "window_expired")
        }

        var due: [(GarminPendingSlot, UInt64)] = []
        var statuses: [UUID: IQDeviceStatus] = [:]
        for (slot, pending) in pendingSends
            where pending.evaluation == .waitingForDeadline && now >= pending.context.startMS + stallThresholdMS
        {
            guard isCurrentRegistration(pending.context) else {
                pendingSends[slot] = nil
                continue
            }
            let deviceID = slot.key.deviceID
            if statuses[deviceID] == nil, let device = deviceRegistrations[deviceID] {
                statuses[deviceID] = connectIQClient?.deviceStatus(of: device.device) ?? .notConnected
            }
            due.append((slot, pending.context.attemptID))
        }
        guard !due.isEmpty else {
            scheduleDiagnosticsSweep()
            return
        }
        // decide after any callback the status sample raised inline has been processed
        DispatchQueue.main.async { [weak self] in
            self?.evaluatePendingSends(due, statuses: statuses, atMS: now)
        }
    }

    private func evaluatePendingSends(_ due: [(GarminPendingSlot, UInt64)], statuses: [UUID: IQDeviceStatus], atMS now: UInt64) {
        for (slot, attemptID) in due {
            guard var pending = pendingSends[slot], pending.context.attemptID == attemptID,
                  pending.evaluation == .waitingForDeadline, isCurrentRegistration(pending.context)
            else { continue }
            let context = pending.context
            guard statuses[slot.key.deviceID] == .connected,
                  deviceRegistrations[slot.key.deviceID]?.linkStatus != .disconnected
            else {
                pending.evaluation = .waitingForConnection
                pendingSends[slot] = pending
                continue
            }
            pending.evaluation = .evaluated
            if stallObservations[slot.key] == nil {
                openStallObservation(context, source: "completion_missing", atMS: now)
                pending.episodeOpened = true
            }
            pendingSends[slot] = pending

            if lastRestartGuidanceMS.map({ now >= $0 + restartGuidanceIntervalMS }) ?? true {
                lastRestartGuidanceMS = now
                logGarminTransportEvent(
                    "stall.restart_guidance",
                    at: now,
                    [
                        ("device_id", String(context.selectionToken)),
                        ("app", context.appLabel),
                        ("attempt_id", String(context.attemptID)),
                        ("elapsed_ms", String(now - context.startMS)),
                        ("hook", stallHookStatus.rawValue)
                    ],
                    warningText: "Garmin send has no SDK result. If the watch still is not updating, restart Tai."
                )
            }
        }
        scheduleDiagnosticsSweep()
    }

    /// A pending send past its deadline gets another look only on a real current connected or ready edge.
    private func resumePendingEvaluation(on deviceID: UUID) {
        var resumed = false
        for (slot, pending) in pendingSends where slot.key.deviceID == deviceID && pending.evaluation == .waitingForConnection {
            pendingSends[slot]?.evaluation = .waitingForDeadline
            resumed = true
        }
        if resumed { scheduleDiagnosticsSweep() }
    }

    private func openStallObservation(_ context: GarminSendContext, source: String, atMS: UInt64) {
        guard stallObservations[context.key] == nil else { return }
        stallObservations[context.key] = GarminStallObservation(origin: context, openedMS: atMS)
        logGarminTransportEvent("stall.observed", at: atMS, [
            ("device_id", String(context.selectionToken)),
            ("link_epoch", String(context.linkEpoch)),
            ("app", context.appLabel),
            ("payload_id", String(context.payloadID)),
            ("attempt_id", String(context.attemptID)),
            ("start_ms", String(context.startMS)),
            ("elapsed_ms", String(atMS >= context.startMS ? atMS - context.startMS : 0)),
            ("source", source),
            ("hook", stallHookStatus.rawValue)
        ])
        scheduleDiagnosticsSweep()
    }

    /// Closes the episode of a key once: on the first accepted success inside its window, or without one.
    private func closeStallObservation(_ key: DeliveryKey, success: (GarminSendContext, UInt64)?, reason: String) {
        guard let observation = stallObservations.removeValue(forKey: key) else { return }
        let origin = observation.origin
        let windowEnd = observation.openedMS + observationWindowMS
        var fields: [(String, String)] = [
            ("device_id", String(origin.selectionToken)),
            ("app", origin.appLabel),
            ("attempt_id", String(origin.attemptID))
        ]
        let timestamp: UInt64
        if case let (context, successMS)? = success, successMS <= windowEnd {
            timestamp = successMS
            fields += [
                ("outcome", "sdk_success"),
                ("success_ms", String(successMS)),
                ("elapsed_ms", String(successMS >= observation.openedMS ? successMS - observation.openedMS : 0)),
                ("success_attempt_id", String(context.attemptID)),
                ("success_kind", context.kind.rawValue),
                ("reason", "observed")
            ]
        } else {
            timestamp = success == nil ? runtime.nowMS() : windowEnd
            fields += [
                ("outcome", "no_success_observed"),
                ("success_ms", "unavailable"),
                ("elapsed_ms", "unavailable"),
                ("success_attempt_id", "unavailable"),
                ("success_kind", "unavailable"),
                ("reason", success == nil ? reason : "window_expired")
            ]
        }
        logGarminTransportEvent("stall.outcome", at: timestamp, fields)
        scheduleDiagnosticsSweep()
    }

    private func closeReconnectObservation(_ deviceID: UUID, outcome: (String, UInt64)?, reason: String) {
        guard let observation = reconnectObservations.removeValue(forKey: deviceID) else { return }
        let windowEnd = observation.startMS + observationWindowMS
        var fields: [(String, String)] = [
            ("device_id", String(observation.selectionToken)),
            ("recovery_id", String(observation.recoveryID)),
            ("start_ms", String(observation.startMS))
        ]
        let timestamp: UInt64
        if case let (label, observedMS)? = outcome, observedMS <= windowEnd {
            timestamp = observedMS
            fields += [
                ("outcome", label),
                ("observed_ms", String(observedMS)),
                ("elapsed_ms", String(observedMS >= observation.startMS ? observedMS - observation.startMS : 0)),
                ("reason", "observed")
            ]
        } else {
            timestamp = outcome == nil ? runtime.nowMS() : windowEnd
            fields += [
                ("outcome", "no_success_observed"),
                ("observed_ms", "unavailable"),
                ("elapsed_ms", "unavailable"),
                ("reason", outcome == nil ? reason : "window_expired")
            ]
        }
        logGarminTransportEvent("reconnect.outcome", at: timestamp, fields)
        scheduleDiagnosticsSweep()
    }

    // MARK: - Logging

    /// Emits one `garmin.<event>` line through the existing logger; fields carry no raw identifiers.
    private func logGarminTransportEvent(
        _ event: String,
        at timestampMS: UInt64,
        _ fields: [(String, String)],
        warningText: String? = nil
    ) {
        var line = (["garmin.\(event)", "ts_ms=\(timestampMS)"] + fields.map { "\($0.0)=\($0.1)" })
            .joined(separator: " ")
        if let warningText {
            line += " \(warningText)"
            warning(.watch, line)
        } else {
            debug(.watch, line)
        }
        runtime.logSink?(line)
    }

    private static let deviceNotAvailableRaw = 3
    private static let appNotFoundRaw = 4
    private static let timeoutRaw = 8
    private static let maxRetriesRaw = 9
    private static let repeatedEventLogIntervalMS: UInt64 = 30000

    static func sdkResultLabel(_ raw: Int) -> String {
        switch raw {
        case 0: return "Success"
        case 1: return "Unknown"
        case 2: return "InternalError"
        case 3: return "DeviceNotAvailable"
        case 4: return "AppNotFound"
        case 5: return "DeviceIsBusy"
        case 6: return "UnsupportedType"
        case 7: return "InsufficientMemory"
        case 8: return "Timeout"
        case 9: return "MaxRetries"
        case 10: return "PromptNotDisplayed"
        case 11: return "AppAlreadyRunning"
        default: return "Unrecognized"
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
            self.onMain {
                $0.deviceSelectionPromise = promise
                $0.connectIQ?.showDeviceSelection()
            }
        }
        .timeout(.seconds(120), scheduler: DispatchQueue.main)
        .replaceEmpty(with: [])
        .eraseToAnyPublisher()
    }

    /// Updates the manager's list of devices, typically after user selection or manual changes.
    /// - Parameter devices: The new array of `IQDevice` objects to track.
    func updateDeviceList(_ devices: [IQDevice]) {
        onMain { $0.applyDeviceList(devices) }
    }

    /// Submits watch state data; it is broadcast after the debounce if no newer state arrives.
    /// - Parameter data: JSON-encoded data representing the latest watch state.
    func sendWatchStateData(_ data: Data) {
        onMain { $0.submitWatchState(data) }
    }

    // MARK: - Inbound Messages & Replies

    /// Status requests refresh the broadcast state; preset requests and commands are answered only
    /// to the requesting app.
    fileprivate func handleInboundMessage(_ message: Any, key: DeliveryKey, registration: UInt64) {
        dispatchPrecondition(condition: .onQueue(.main))
        let isRegistered = appRegistrations[key]?.appRegistration == registration
        let appName = appDisplayName(for: key.appID)
        debugGarmin("Message received from Garmin \(appName)")

        if isRegistered {
            markLinkProof(key.deviceID)
            // an app callback never overrides a confirmed link loss
            if deviceRegistrations[key.deviceID]?.linkStatus != .disconnected {
                absentApps.remove(key)
                offerOwedState(to: key)
            }
        }

        let router = GarminCommandRouter(processor: watchCommandProcessor)
        Task {
            let outcome = await router.route(message, from: key.appID, isRegistered: isRegistered, appName: appName)

            if let reply = outcome.reply {
                DispatchQueue.main.async { [weak self] in
                    self?.sendTargetedResponse(reply, to: key, registration: registration)
                }
            }
            // debounced path, so a request coinciding with a determination still sends once
            if let trigger = outcome.refreshTrigger {
                triggerWatchStateUpdate(triggeredBy: trigger)
            }
            if outcome.pushesPresets {
                DispatchQueue.main.async { [weak self] in
                    self?.pushPresetsToComplications(triggeredBy: "WatchCommand")
                }
            }
        }
    }

    /// Sends the preset list to every registered Complication app on every device, targeted like an
    /// ack so it never touches the state broadcast. Call on the main queue.
    private func pushPresetsToComplications(triggeredBy trigger: String) {
        dispatchPrecondition(condition: .onQueue(.main))
        let complicationUUID = GarminWatchface.complication.watchfaceUUID
        let targets = deliveryOrder.filter { $0.appID == complicationUUID }
            .compactMap { key in appRegistrations[key].map { (key, $0.appRegistration) } }
        guard !targets.isEmpty else { return }

        Task {
            do {
                let response = try await GarminCommandEnvelope.presetsResponse(watchCommandProcessor.presets())
                DispatchQueue.main.async { [weak self] in
                    for (key, registration) in targets {
                        self?.sendTargetedResponse(response, to: key, registration: registration)
                    }
                }
            } catch {
                warning(
                    .watch,
                    "Garmin presets for \(trigger) push could not be loaded (\(WatchCommandErrorCategory.name(for: error)))"
                )
            }
        }
    }

    /// Answers one app registration directly, never through the state broadcast or its owed queue.
    /// A reply to an app that was removed or replaced since is dropped, never retargeted.
    private func sendTargetedResponse(
        _ response: [String: Any],
        to key: DeliveryKey,
        registration: UInt64,
        payloadID: UInt64? = nil,
        retryOf: UInt64? = nil
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard let client = connectIQClient, let record = appRegistrations[key], record.appRegistration == registration,
              let device = deviceRegistrations[key.deviceID]
        else {
            debugGarmin("Dropped Garmin reply, app no longer registered")
            return
        }
        let kind = response[WatchMessageKeys.request] as? String ?? "response"
        debugGarmin("Sending \(kind) to Garmin \(appDisplayName(for: key.appID))")
        let attemptID = allocateToken()
        let context = GarminSendContext(
            key: key,
            kind: .targeted,
            selectionToken: device.selectionToken,
            deviceRegistration: device.deviceRegistration,
            linkEpoch: device.linkEpoch,
            appRegistration: registration,
            appLabel: record.appLabel,
            payloadID: payloadID ?? attemptID,
            attemptID: attemptID,
            retryOf: retryOf,
            startMS: runtime.nowMS()
        )
        submit(response, to: record.app, context: context, client: client)
    }

    /// The baseline single 2 s resend of a reply, only after a real SDK failure and only to the same registration.
    private func handleTargetedCompletion(_ result: IQSendMessageResult, context: GarminSendContext, message: Any) {
        guard result != .success else {
            markLinkProof(context.key.deviceID)
            return
        }
        guard context.retryOf == nil, let response = message as? [String: Any] else {
            warning(.watch, "Sending reply to Garmin \(context.appLabel) failed after retry")
            return
        }
        let firstAttemptID = context.attemptID
        let work = DispatchWorkItem { [weak self] in
            guard let self, let retry = self.pendingReplyRetries.removeValue(forKey: firstAttemptID),
                  self.appRegistrations[retry.key]?.appRegistration == retry.appRegistration,
                  self.deviceRegistrations[retry.key.deviceID]?.linkEpoch == retry.linkEpoch
            else { return }
            self.sendTargetedResponse(
                response,
                to: retry.key,
                registration: retry.appRegistration,
                payloadID: firstAttemptID,
                retryOf: firstAttemptID
            )
        }
        pendingReplyRetries[firstAttemptID] = PendingReplyRetry(
            work: work,
            key: context.key,
            appRegistration: context.appRegistration,
            linkEpoch: context.linkEpoch
        )
        warning(.watch, "Sending reply to Garmin \(context.appLabel) failed, retrying in \(sendRetryDelay) s")
        runtime.schedule(after: sendRetryDelay, work)
    }
}

// MARK: - Extensions

extension BaseGarminManager: IQUIOverrideDelegate {
    // MARK: - IQUIOverrideDelegate

    /// Called if the Garmin Connect Mobile app is not installed or otherwise not available.
    func needsToInstallConnectMobile() {
        DispatchQueue.main.async { [weak self] in
            self?.alertConnectMobileMissing()
        }
    }

    private func alertConnectMobileMissing() {
        warning(.watch, "Garmin Connect app not available")
        let content = Alert.Content(
            title: String(localized: "Garmin is not available"),
            body: String(
                localized:
                "The app Garmin Connect must be installed to use Trio.\nGo to the App Store to download it."
            ),
            acknowledgeActionButtonLabel: String(localized: "OK")
        )
        let alert = Alert(
            identifier: Alert.Identifier(
                managerIdentifier: "trio.garmin",
                alertIdentifier: "connect.mobile.missing"
            ),
            foregroundContent: content,
            backgroundContent: content,
            trigger: .immediate,
            interruptionLevel: .active,
            sound: nil
        )
        trioAlertManager?.issueAlert(alert)
    }
}

extension BaseGarminManager: SettingsObserver {
    /// Called whenever TrioSettings changes (e.g., user toggles mg/dL vs. mmol/L, watchface selection, etc.).
    /// Compares previous vs current settings to determine what changed and responds appropriately.
    /// - Parameter _: The updated TrioSettings instance.
    func settingsDidChange(_: TrioSettings) {
        onMain { $0.applySettingsChange() }
    }

    private func applySettingsChange() {
        let currentGarminSettings = settingsManager.settings.garminSettings
        let currentUnits = settingsManager.settings.units
        let currentColorScheme = settingsManager.settings.glucoseColorScheme

        // Detect what specifically changed
        let unitsChanged = currentUnits != units
        let colorSchemeChanged = currentColorScheme != glucoseColorScheme
        let watchfaceChanged = currentGarminSettings.watchface != previousGarminSettings.watchface
        let datafieldChanged = currentGarminSettings.datafields != previousGarminSettings.datafields
        let watchfaceDataEnabledChanged = currentGarminSettings.isWatchfaceDataEnabled != previousGarminSettings
            .isWatchfaceDataEnabled
        let displayAttributesChanged = currentGarminSettings.primaryAttributeChoice != previousGarminSettings
            .primaryAttributeChoice ||
            currentGarminSettings.secondaryAttributeChoice != previousGarminSettings.secondaryAttributeChoice
        let commandRevocation = watchCommandAuthorization.current
        let commandSettingsChanged = currentGarminSettings.isCommandControlEnabled != previousGarminSettings
            .isCommandControlEnabled ||
            currentGarminSettings.isBolusCommandEnabled != previousGarminSettings.isBolusCommandEnabled ||
            commandRevocation != lastSeenCommandRevocation
        lastSeenCommandRevocation = commandRevocation
        let maxCarbsChanged = settingsManager.settings.maxCarbs != previousMaxCarbs
        previousMaxCarbs = settingsManager.settings.maxCarbs

        // Update stored values
        units = currentUnits
        glucoseColorScheme = currentColorScheme

        // Re-register devices only if watchface/datafield configuration changed
        var registrationNeedsState = false
        if watchfaceChanged || datafieldChanged || watchfaceDataEnabledChanged {
            debugGarmin("Garmin watchface or data field changed, re-registering devices")
            discardPendingSubmission()
            if !devices.isEmpty {
                registrationNeedsState = registerDevices(devices)
            }
        }

        // Disabling watchface data doesn't need an update (nothing to send to)
        let watchfaceDataJustEnabled = watchfaceDataEnabledChanged && currentGarminSettings.isWatchfaceDataEnabled

        if watchfaceDataJustEnabled {
            // Send immediately when watchface data is enabled - user wants to see data now
            if debugWatchState {
                debug(.watch, "Garmin watchface data enabled, sending update")
            }
            triggerWatchStateUpdate(triggeredBy: "Settings")
        } else if commandSettingsChanged {
            triggerWatchStateUpdate(triggeredBy: "CommandSettings")
        } else if unitsChanged || displayAttributesChanged || colorSchemeChanged {
            // Throttle other settings changes in case user makes multiple changes
            if debugWatchState {
                debug(.watch, "Garmin display settings changed, scheduling update")
            }
            sendSettingsUpdateThrottled()
        }
        if registrationNeedsState, !watchfaceDataJustEnabled {
            triggerWatchStateUpdate(triggeredBy: "GarminRegistration")
        }

        // the complication builds its menu and pickers from these, so it gets them without asking;
        // max bolus and bolus increment live outside TrioSettings and reach it on the next app open
        if commandSettingsChanged || maxCarbsChanged {
            pushPresetsToComplications(triggeredBy: "CommandSettings")
        }

        // Store current Garmin settings for next comparison
        previousGarminSettings = currentGarminSettings
    }
}

extension BaseGarminManager: BGTargetsObserver {
    /// Called when the glucose target profile is edited.
    /// - Parameter _: The updated targets, re-read from storage during preparation.
    func bgTargetsDidChange(_: BGTargets) {
        if debugWatchState {
            debug(.watch, "Glucose targets changed, scheduling Garmin update")
        }
        sendSettingsUpdateThrottled()
    }
}
