import Combine
import ConnectIQ
import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

/// A task context whose saves fail the way a full disk or a validation error would.
final class FailingSaveContext: NSManagedObjectContext {
    override func save() throws {
        throw NSError(
            domain: NSCocoaErrorDomain,
            code: NSValidationMultipleErrorsError,
            userInfo: [NSLocalizedDescriptionKey: "carbs=40 \(SensitiveTestError.marker)"]
        )
    }
}

/// Counts saves, to prove a transaction wrote nothing.
final class CountingSaveContext: NSManagedObjectContext, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var saveCount: Int { lock.withLock { count } }

    override func save() throws {
        lock.withLock { count += 1 }
        try super.save()
    }
}

/// Holds a context's private queue from inside `perform`, so later transactions queue up behind it.
final class ContextQueueBlocker: @unchecked Sendable {
    private let released = DispatchSemaphore(value: 0)

    func block(_ context: NSManagedObjectContext) {
        context.perform { self.released.wait() }
    }

    func release() {
        released.signal()
    }
}

/// Overrides the storage and safety services the production watch actions use.
private final class WatchCommandOverrideAssembly: Assembly {
    private let carbsContext: () -> NSManagedObjectContext
    private let validator: BolusSafetyValidator
    private let processor: WatchCommandProcessor?
    private let apsManager: APSManager?
    private let adjustmentContext: (() -> NSManagedObjectContext)?

    init(
        carbsContext: @escaping () -> NSManagedObjectContext,
        validator: BolusSafetyValidator,
        processor: WatchCommandProcessor?,
        apsManager: APSManager?,
        adjustmentContext: (() -> NSManagedObjectContext)?
    ) {
        self.carbsContext = carbsContext
        self.validator = validator
        self.processor = processor
        self.apsManager = apsManager
        self.adjustmentContext = adjustmentContext
    }

    func assemble(container: Container) {
        container.register(CarbsStorage.self) { [carbsContext] r in
            BaseCarbsStorage(resolver: r, contextProvider: carbsContext)
        }.inObjectScope(.container)
        container.register(BolusSafetyValidator.self) { [validator] _ in validator }
        if let processor {
            container.register(WatchCommandProcessor.self) { _ in processor }.inObjectScope(.container)
        }
        if let apsManager {
            container.register(APSManager.self) { _ in apsManager }.inObjectScope(.container)
        }
        if let adjustmentContext {
            container.register(AdjustmentManager.self) { r in
                BaseAdjustmentManager(resolver: r, contextProvider: adjustmentContext, recompute: {})
            }.inObjectScope(.container)
        }
    }
}

private func makeResolver(
    stack: CoreDataStack,
    carbsContext: @escaping () -> NSManagedObjectContext,
    validator: BolusSafetyValidator = StubBolusSafetyValidator(),
    processor: WatchCommandProcessor? = nil,
    apsManager: APSManager? = nil,
    adjustmentContext: (() -> NSManagedObjectContext)? = nil
) -> Resolver {
    Assembler([
        StorageAssembly(),
        ServiceAssembly(),
        APSAssembly(),
        NetworkAssembly(),
        UIAssembly(),
        SecurityAssembly(),
        TestAssembly(testContext: stack.newTaskContext()),
        WatchCommandOverrideAssembly(
            carbsContext: carbsContext,
            validator: validator,
            processor: processor,
            apsManager: apsManager,
            adjustmentContext: adjustmentContext
        )
    ]).resolver
}

// MARK: - Carb Persistence

@Suite("Watch Command Carb Persistence Tests", .serialized) struct WatchCommandCarbPersistenceTests {
    let stack: CoreDataStack
    let failingContext: FailingSaveContext

    init() async throws {
        stack = try await CoreDataStack.createForTests()
        failingContext = FailingSaveContext(concurrencyType: .privateQueueConcurrencyType)
        failingContext.persistentStoreCoordinator = stack.persistentContainer.persistentStoreCoordinator
    }

    private func storedCarbRows() async throws -> Int {
        let context = stack.newTaskContext()
        return try await context.perform {
            try context.count(for: NSFetchRequest<CarbEntryStored>(entityName: "CarbEntryStored"))
        }
    }

    @Test("A failed save throws from the verified path but stays silent for existing callers") func testStorageBoundary(
    ) async throws {
        let context = failingContext
        let resolver = makeResolver(stack: stack, carbsContext: { context })
        let storage = try #require(resolver.resolve(CarbsStorage.self))

        await #expect(throws: NSError.self) {
            try await storage.storeVerifiedCarbs(storage.makeCarbEntry(carbs: 40, date: Date()), authorize: {})
        }
        // unchanged contract for the app's own callers
        try await storage.storeCarbs([storage.makeCarbEntry(carbs: 40, date: Date())], areFetchedFromRemote: false)
        #expect(try await storedCarbRows() == 0)
    }

    @Test("A successful verified save persists the carb row") func testStorageSuccess() async throws {
        let stack = self.stack
        let resolver = makeResolver(stack: stack, carbsContext: { stack.newTaskContext() })
        let storage = try #require(resolver.resolve(CarbsStorage.self))

        try await storage.storeVerifiedCarbs(storage.makeCarbEntry(carbs: 25, date: Date()), authorize: {})

        #expect(try await storedCarbRows() == 1)
    }

    @Test("A real carb save failure never acks carbs or reaches the bolus") func testProductionActionFailure() async throws {
        let context = failingContext
        let validator = StubBolusSafetyValidator()
        let resolver = makeResolver(stack: stack, carbsContext: { context }, validator: validator)
        let settings = try #require(resolver.resolve(SettingsManager.self))
        settings.settings.isGarminCommandControlEnabled = true
        settings.settings.isGarminBolusCommandEnabled = true

        let logs = LogCapture()
        let processor = BaseWatchCommandProcessor(
            resolver: resolver,
            actions: BaseWatchCommandActions(resolver: resolver),
            log: logs.record
        )
        let appUUID = UUID()

        let carbs = await processor.process(
            WatchCommandRequest(requestID: UUID(), appUUID: appUUID, date: Date(), command: .carbs(40))
        )
        let meal = await processor.process(
            WatchCommandRequest(requestID: UUID(), appUUID: appUUID, date: Date(), command: .mealBolus(carbs: 40, bolus: 2))
        )

        #expect(carbs.acknowledged == false)
        #expect(carbs.ackCode == .genericFailure)
        #expect(meal.acknowledged == false)
        #expect(meal.ackCode == .genericFailure, "No partial failure: nothing was logged")
        #expect(validator.validatedAmounts.isEmpty, "The bolus stage is never reached")
        #expect(try await storedCarbRows() == 0)
        #expect(logs.lines.contains { $0.contains("(cocoa(\(NSValidationMultipleErrorsError)))") })
        #expect(logs.lines.allSatisfy { !$0.contains(SensitiveTestError.marker) })
    }
}

// MARK: - Garmin Manager

/// Stands in for the Connect IQ SDK: records every message with the exact app it targeted, keeps the
/// registered listeners so tests deliver SDK callbacks through them, and completes sends on demand.
final class SpyConnectIQClient: GarminConnectIQClient, @unchecked Sendable {
    struct Sent {
        let message: Any
        let appUUID: UUID
        let deviceUUID: UUID

        var request: String? { (message as? [String: Any])?[WatchMessageKeys.request] as? String }
        /// The `glucose` value of a state payload, nil for replies.
        var stateValue: Int? { ((message as? [[String: Any]])?.first?["glucose"] as? Int) }
    }

    struct Call: Equatable {
        let name: String
        let target: UUID
        let listener: ObjectIdentifier
    }

    enum CompletionMode {
        case inline
        case offMain
        case held
        /// Completes inline twice, as a misbehaving SDK might.
        case duplicate
    }

    private struct Held {
        let appUUID: UUID
        let deviceUUID: UUID
        let completion: (IQSendMessageResult) -> Void
    }

    private let lock = NSLock()
    private var messages: [Sent] = []
    /// Remaining failures per app UUID + device UUID, to exercise the retry.
    private var failures: [String: Int] = [:]
    private var queuedResults: [String: [Int]] = [:]
    private var heldSends: [Held] = []
    private var deviceListeners: [UUID: IQDeviceEventDelegate] = [:]
    private var appListeners: [String: IQAppMessageDelegate] = [:]
    private var recordedCalls: [Call] = []
    private var statuses: [UUID: IQDeviceStatus] = [:]
    private var mode: CompletionMode = .inline
    private var statusQueryHook: ((IQDevice) -> Void)?
    private var registerHook: ((IQDevice, IQDeviceEventDelegate) -> Void)?

    var sent: [Sent] { lock.withLock { messages } }
    var calls: [Call] { lock.withLock { recordedCalls } }
    var heldCount: Int { lock.withLock { heldSends.count } }

    var completionMode: CompletionMode {
        get { lock.withLock { mode } }
        set { lock.withLock { mode = newValue } }
    }

    /// Runs inside `deviceStatus(of:)`, e.g. to raise an SDK callback while the status is sampled.
    var onStatusQuery: ((IQDevice) -> Void)? {
        get { lock.withLock { statusQueryHook } }
        set { lock.withLock { statusQueryHook = newValue } }
    }

    /// Runs inside `registerDevice`, e.g. to raise an SDK callback during registration.
    var onRegisterDevice: ((IQDevice, IQDeviceEventDelegate) -> Void)? {
        get { lock.withLock { registerHook } }
        set { lock.withLock { registerHook = newValue } }
    }

    private func target(_ appUUID: UUID, _ deviceUUID: UUID) -> String {
        "\(appUUID)-\(deviceUUID)"
    }

    func failNextSend(to appUUID: UUID, on deviceUUID: UUID) {
        lock.withLock { failures[target(appUUID, deviceUUID), default: 0] += 1 }
    }

    /// Queues raw SDK results for the next sends to one app; later sends succeed.
    func queueResults(_ raws: [Int], to appUUID: UUID, on deviceUUID: UUID) {
        lock.withLock { queuedResults[target(appUUID, deviceUUID), default: []] += raws }
    }

    func setStatus(_ status: IQDeviceStatus, of deviceUUID: UUID) {
        lock.withLock { statuses[deviceUUID] = status }
    }

    func deviceListener(_ deviceUUID: UUID) -> IQDeviceEventDelegate? {
        lock.withLock { deviceListeners[deviceUUID] }
    }

    func appListener(_ appUUID: UUID, on deviceUUID: UUID) -> IQAppMessageDelegate? {
        lock.withLock { appListeners[target(appUUID, deviceUUID)] }
    }

    func calls(_ name: String) -> [Call] {
        calls.filter { $0.name == name }
    }

    /// Delivers an inbound message through the listener registered for the app's UUIDs.
    @discardableResult func deliver(_ message: Any, from app: IQApp) -> Bool {
        guard let listener = appListener(app.uuid, on: app.device.uuid) else { return false }
        listener.receivedMessage?(message, from: app)
        return true
    }

    /// Completes the oldest held send, optionally only one for the given app.
    @discardableResult func completeHeld(
        _ raw: Int = 0,
        app appUUID: UUID? = nil,
        on deviceUUID: UUID? = nil
    ) -> Bool {
        let held: Held? = lock.withLock {
            guard let index = heldSends.firstIndex(where: {
                (appUUID == nil || $0.appUUID == appUUID) && (deviceUUID == nil || $0.deviceUUID == deviceUUID)
            }) else { return nil }
            return heldSends.remove(at: index)
        }
        guard let held else { return false }
        held.completion(IQSendMessageResult(rawValue: raw)!)
        return true
    }

    func registerDevice(_ device: IQDevice, delegate: IQDeviceEventDelegate) {
        let hook: ((IQDevice, IQDeviceEventDelegate) -> Void)? = lock.withLock {
            deviceListeners[device.uuid] = delegate
            recordedCalls.append(Call(name: "registerDevice", target: device.uuid, listener: ObjectIdentifier(delegate)))
            return registerHook
        }
        hook?(device, delegate)
    }

    func unregisterDevice(_ device: IQDevice, delegate: IQDeviceEventDelegate) {
        lock.withLock {
            if deviceListeners[device.uuid] === delegate { deviceListeners[device.uuid] = nil }
            recordedCalls.append(Call(name: "unregisterDevice", target: device.uuid, listener: ObjectIdentifier(delegate)))
        }
    }

    func deviceStatus(of device: IQDevice) -> IQDeviceStatus {
        let (status, hook) = lock.withLock { (statuses[device.uuid] ?? .connected, statusQueryHook) }
        hook?(device)
        return status
    }

    func registerApp(_ app: IQApp, delegate: IQAppMessageDelegate) {
        lock.withLock {
            appListeners[target(app.uuid, app.device.uuid)] = delegate
            recordedCalls.append(Call(name: "registerApp", target: app.uuid, listener: ObjectIdentifier(delegate)))
        }
    }

    func unregisterApp(_ app: IQApp, delegate: IQAppMessageDelegate) {
        lock.withLock {
            let key = target(app.uuid, app.device.uuid)
            if appListeners[key] === delegate { appListeners[key] = nil }
            recordedCalls.append(Call(name: "unregisterApp", target: app.uuid, listener: ObjectIdentifier(delegate)))
        }
    }

    func send(_ message: Any, to app: IQApp, completion: @escaping (IQSendMessageResult) -> Void) {
        let key = target(app.uuid, app.device.uuid)
        let (raw, mode): (Int?, CompletionMode) = lock.withLock {
            messages.append(Sent(message: message, appUUID: app.uuid, deviceUUID: app.device.uuid))
            if self.mode == .held {
                heldSends.append(Held(appUUID: app.uuid, deviceUUID: app.device.uuid, completion: completion))
                return (nil, .held)
            }
            if var queued = queuedResults[key], !queued.isEmpty {
                let raw = queued.removeFirst()
                queuedResults[key] = queued
                return (raw, self.mode)
            }
            if let remaining = failures[key], remaining > 0 {
                failures[key] = remaining - 1
                // raw value 1 is IQSendMessageResult_Failure_Unknown
                return (1, self.mode)
            }
            return (0, self.mode)
        }
        guard let raw else { return }
        let result = IQSendMessageResult(rawValue: raw)!
        switch mode {
        case .held,
             .inline:
            completion(result)
        case .offMain:
            DispatchQueue.global().async { completion(result) }
        case .duplicate:
            completion(result)
            completion(result)
        }
    }
}

@Suite("Garmin Manager Command Integration Tests", .serialized) final class GarminManagerCommandIntegrationTests {
    let complicationUUID = GarminWatchface.complication.watchfaceUUID!
    let datafieldUUID = GarminDatafield.loopgraph.datafieldUUID!
    let deviceA = IQDevice(id: UUID(), modelName: "fenix 8", friendlyName: "A")!
    let deviceB = IQDevice(id: UUID(), modelName: "Enduro 3", friendlyName: "B")!

    let processor: SpyWatchCommandProcessor
    let client: SpyConnectIQClient
    let presetChanges: PassthroughSubject<Void, Never>
    let settings: SettingsManager
    let authorization: WatchCommandAuthorization
    let manager: BaseGarminManager

    init() async throws {
        let stack = try await CoreDataStack.createForTests()
        let processor = SpyWatchCommandProcessor()
        let client = SpyConnectIQClient()
        let presetChanges = PassthroughSubject<Void, Never>()
        let resolver = makeResolver(stack: stack, carbsContext: { stack.newTaskContext() }, processor: processor)

        let settings = try #require(resolver.resolve(SettingsManager.self))
        settings.settings.garminSettings.watchface = .complication
        settings.settings.garminSettings.isWatchfaceDataEnabled = true
        settings.settings.garminSettings.datafields = [.loopgraph]
        settings.settings.garminSettings.isCommandControlEnabled = true

        self.processor = processor
        self.client = client
        self.presetChanges = presetChanges
        self.settings = settings
        authorization = try #require(resolver.resolve(WatchCommandAuthorization.self))
        manager = BaseGarminManager(
            resolver: resolver,
            connectIQClient: client,
            presetChanges: presetChanges.eraseToAnyPublisher(),
            sendRetryDelay: 0.01
        )
        manager.updateDeviceList([deviceA, deviceB])
        let listening = await eventually {
            client.appListener(GarminWatchface.complication.watchfaceUUID!, on: self.deviceA.uuid) != nil &&
                client.appListener(GarminWatchface.complication.watchfaceUUID!, on: self.deviceB.uuid) != nil
        }
        #expect(listening)
    }

    deinit {
        let manager = manager
        DispatchQueue.main.async { manager.updateDeviceList([]) }
    }

    private func app(_ uuid: UUID, on device: IQDevice) -> IQApp {
        IQApp(uuid: uuid, store: UUID(), device: device)
    }

    private func command(_ name: String, payload: [String: Any], requestID: String) -> [String: Any] {
        [
            "v": 1,
            "req": "command",
            "requestId": requestID,
            "date": NSNumber(value: UInt64(Date().timeIntervalSince1970 * 1000)),
            "command": name,
            "payload": payload
        ]
    }

    private func sent(_ request: String) -> [SpyConnectIQClient.Sent] {
        client.sent.filter { $0.request == request }
    }

    @Test("An ack goes only to the app and device that sent the command") func testAckTargetsOriginatingApp() async {
        let requestID = UUID().uuidString
        client.deliver(
            command("carbs", payload: ["carbs": 20], requestID: requestID),
            from: app(complicationUUID, on: deviceB)
        )

        #expect(await eventually { !self.sent("ack").isEmpty })
        let acks = sent("ack")
        #expect(acks.count == 1)
        #expect(acks.allSatisfy { $0.appUUID == complicationUUID && $0.deviceUUID == deviceB.uuid })
        #expect(acks.first.flatMap { ($0.message as? [String: Any])?["requestId"] as? String } == requestID)
        #expect(processor.processed.map(\.appUUID) == [complicationUUID])
        #expect(
            client.sent.filter { $0.request != nil }.allSatisfy { $0.appUUID != datafieldUUID },
            "Nothing command-related is fanned out"
        )
    }

    @Test("A preset request is answered only to the requesting app") func testPresetsReplyTargeted() async {
        processor.presetsResult = WatchCommandPresets(
            overridePresets: [OverridePresetWatch(name: "Sport", isEnabled: false)],
            tempTargetPresets: []
        )
        client.deliver(["v": 1, "req": "presets"], from: app(complicationUUID, on: deviceA))

        #expect(await eventually { !self.sent("presets").isEmpty })
        let replies = sent("presets")
        #expect(replies.count == 1)
        #expect(replies.first?.appUUID == complicationUUID)
        #expect(replies.first?.deviceUUID == deviceA.uuid)
    }

    @Test("A failed ack is resent to the same app") func testAckRetryTarget() async {
        client.failNextSend(to: complicationUUID, on: deviceA.uuid)
        let requestID = UUID().uuidString
        client.deliver(
            command("carbs", payload: ["carbs": 20], requestID: requestID),
            from: app(complicationUUID, on: deviceA)
        )

        #expect(await eventually { self.sent("ack").count == 2 })
        let acks = sent("ack")
        #expect(acks.allSatisfy { $0.appUUID == complicationUUID && $0.deviceUUID == deviceA.uuid })
        #expect(acks.allSatisfy { ($0.message as? [String: Any])?["requestId"] as? String == requestID })
    }

    @Test("A started preset pushes the list to every Complication app, never to datafields") func testCommandPushesPresets() async {
        processor.result = .success(.overrideStarted, "Override started.")
        client.deliver(
            command("activateOverride", payload: ["name": "Sport"], requestID: UUID().uuidString),
            from: app(complicationUUID, on: deviceA)
        )

        #expect(await eventually { self.sent("presets").count == 2 })
        let pushes = sent("presets")
        #expect(Set(pushes.map(\.deviceUUID)) == [deviceA.uuid, deviceB.uuid])
        #expect(pushes.allSatisfy { $0.appUUID == complicationUUID })
        #expect(sent("ack").map(\.deviceUUID) == [deviceA.uuid])
        #expect(client.sent.filter { $0.request != nil }.allSatisfy { $0.appUUID != datafieldUUID })
    }

    @Test("Preset storage changes push to Complication apps only") func testStorageChangePushesPresets() async {
        presetChanges.send(())

        #expect(await eventually { self.sent("presets").count == 2 })
        #expect(sent("presets").allSatisfy { $0.appUUID == complicationUUID })
        #expect(Set(sent("presets").map(\.deviceUUID)) == [deviceA.uuid, deviceB.uuid])
        #expect(processor.processed.isEmpty)
    }

    @Test("Command switch and max carbs changes push presets to Complication apps only") func testSettingsPushPresets() async {
        settings.settings.garminSettings.isBolusCommandEnabled = true

        #expect(await eventually { self.sent("presets").count == 2 })
        #expect(sent("presets").allSatisfy { $0.appUUID == complicationUUID })

        settings.settings.maxCarbs = 99
        #expect(await eventually { self.sent("presets").count == 4 })

        settings.settings.garminSettings.primaryAttributeChoice = .isf
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(sent("presets").count == 4, "Display settings do not push presets")
    }

    @Test("A message from an unregistered device is ignored") func testUnregisteredDevice() async throws {
        let stranger = try #require(IQDevice(id: UUID(), modelName: "fenix 8", friendlyName: "C"))
        #expect(!client.deliver(
            command("carbs", payload: ["carbs": 20], requestID: UUID().uuidString),
            from: app(complicationUUID, on: stranger)
        ))
        // a registered listener rejects a message reporting another device
        client.appListener(complicationUUID, on: deviceA.uuid)?.receivedMessage?(
            command("carbs", payload: ["carbs": 20], requestID: UUID().uuidString),
            from: app(complicationUUID, on: stranger)
        )
        // a retired listener cannot admit a message once its device is removed
        let retired = try #require(client.appListener(complicationUUID, on: deviceB.uuid))
        manager.updateDeviceList([deviceA])
        #expect(await eventually { self.client.appListener(self.complicationUUID, on: self.deviceB.uuid) == nil })
        retired.receivedMessage?(
            command("carbs", payload: ["carbs": 20], requestID: UUID().uuidString),
            from: app(complicationUUID, on: deviceB)
        )

        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(client.sent.filter { $0.request != nil }.isEmpty)
        #expect(processor.processed.isEmpty)
    }

    @Test("Switching a command setting off revokes in the setter; changes refresh the watch") func testSettingsRevoke() async {
        let triggers = RefreshTriggerRecorder(manager)
        let start = authorization.current

        settings.settings.garminSettings.isCommandControlEnabled = false
        #expect(authorization.current == start + 1, "Revoked before the notification is even queued")
        #expect(await eventually { triggers.count("CommandSettings") == 1 })

        settings.settings.garminSettings.isCommandControlEnabled = true
        settings.settings.garminSettings.isBolusCommandEnabled = true
        #expect(authorization.current == start + 1, "Turning settings on revokes nothing")
        #expect(await eventually { triggers.count("CommandSettings") >= 2 })

        let refreshes = triggers.count("CommandSettings")
        settings.settings.garminSettings.primaryAttributeChoice = .isf
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(authorization.current == start + 1, "Display settings leave commands alone")
        #expect(triggers.count("CommandSettings") == refreshes)
    }
}

/// Collects the trigger names of the manager's watch state refreshes.
final class RefreshTriggerRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    private var subscription: AnyCancellable?

    init(_ manager: BaseGarminManager) {
        subscription = manager.stateRefreshTriggers.sink { [weak self] name in
            guard let self else { return }
            self.lock.withLock { self.names.append(name) }
        }
    }

    func count(_ name: String) -> Int {
        lock.withLock { names.filter { $0 == name }.count }
    }
}

// MARK: - Revocation And Final Boundaries

/// Runs revocation through the production settings manager, Garmin manager, processor, storage and
/// adjustment manager; only the pump, the safety validator and the Connect IQ SDK are stand-ins.
@Suite("Watch Command Revocation Integration Tests", .serialized) struct WatchCommandRevocationIntegrationTests {
    let stack: CoreDataStack

    init() async throws {
        stack = try await CoreDataStack.createForTests()
    }

    private func countingContext() -> CountingSaveContext {
        let context = CountingSaveContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = stack.persistentContainer.persistentStoreCoordinator
        return context
    }

    private func carbRows() async throws -> Int {
        let context = stack.newTaskContext()
        return try await context.perform {
            try context.count(for: NSFetchRequest<CarbEntryStored>(entityName: "CarbEntryStored"))
        }
    }

    private func enableCommands(_ settings: SettingsManager) {
        settings.settings.isGarminCommandControlEnabled = true
        settings.settings.isGarminBolusCommandEnabled = true
    }

    private func request(_ command: WatchCommand) -> WatchCommandRequest {
        WatchCommandRequest(requestID: UUID(), appUUID: UUID(), date: Date(), command: command)
    }

    // MARK: R1

    @Test(
        "Off-then-on before the settings notification drains still stops a suspended bolus",
        arguments: [false, true]
    ) func testRevokedBeforeNotificationDrains(isMeal: Bool) async throws {
        let stack = self.stack
        let validator = StubBolusSafetyValidator()
        validator.gate = TestGate()
        let pump = SpyAPSManager()
        let client = SpyConnectIQClient()
        let resolver = makeResolver(
            stack: stack,
            carbsContext: { stack.newTaskContext() },
            validator: validator,
            apsManager: pump
        )
        #expect(resolver.resolve(WatchCommandProcessor.self) is BaseWatchCommandProcessor)
        let settings = try #require(resolver.resolve(SettingsManager.self))
        let authorization = try #require(resolver.resolve(WatchCommandAuthorization.self))
        settings.settings.garminSettings.watchface = .complication
        settings.settings.garminSettings.isWatchfaceDataEnabled = true
        enableCommands(settings)

        let device = try #require(IQDevice(id: UUID(), modelName: "fenix 8", friendlyName: "R1"))
        let manager = BaseGarminManager(
            resolver: resolver,
            connectIQClient: client,
            presetChanges: Empty().eraseToAnyPublisher(),
            sendRetryDelay: 0.01
        )
        manager.updateDeviceList([device])
        defer { DispatchQueue.main.async { manager.updateDeviceList([]) } }
        let triggers = RefreshTriggerRecorder(manager)

        let complicationUUID = try #require(GarminWatchface.complication.watchfaceUUID)
        #expect(await eventually { client.appListener(complicationUUID, on: device.uuid) != nil })
        client.deliver(
            [
                "v": 1,
                "req": "command",
                "requestId": UUID().uuidString,
                "date": NSNumber(value: UInt64(Date().timeIntervalSince1970 * 1000)),
                "command": isMeal ? "mealBolus" : "bolus",
                "payload": isMeal ? ["carbs": 30, "bolus": 2] : ["bolus": 2]
            ] as [String: Any],
            from: IQApp(uuid: complicationUUID, store: UUID(), device: device)
        )
        await validator.gate.waitForArrivals()

        let start = authorization.current
        let revokedInsideBlock = await MainActor.run {
            // the main queue cannot deliver a settings notification before this block returns
            settings.settings.garminSettings.isCommandControlEnabled = false
            settings.settings.garminSettings.isCommandControlEnabled = true
            settings.settings.garminSettings.isBolusCommandEnabled = false
            settings.settings.garminSettings.isBolusCommandEnabled = true
            return authorization.current - start
        }
        #expect(revokedInsideBlock == 2)
        validator.gate.open()

        #expect(await eventually { client.sent.contains { $0.request == "ack" } })
        let ack = try #require(client.sent.first { $0.request == "ack" }?.message as? [String: Any])
        #expect(ack[WatchMessageKeys.ackCode] as? String == (isMeal ? "partial_failure" : "failure"))
        #expect(pump.bolusRequests.isEmpty, "No pump request after the revocation")
        #expect(try await carbRows() == (isMeal ? 1 : 0))
        #expect(
            await eventually { triggers.count("CommandSettings") >= 1 },
            "Settings ended where they started, but the revocation still refreshes the watch"
        )
    }

    // MARK: R2

    @Test(
        "A Garmin adjustment queued behind a busy context writes nothing once revoked",
        arguments: [
            WatchCommand.activateOverride(name: "Sport"), .cancelOverride,
            .activateTempTarget(name: "Walk"), .cancelTempTarget
        ]
    ) func testAdjustmentRevokedWhileQueued(command: WatchCommand) async throws {
        let stack = self.stack
        let context = countingContext()
        let transactions = TestGate(isOpen: true)
        let resolver = makeResolver(
            stack: stack,
            carbsContext: { stack.newTaskContext() },
            adjustmentContext: {
                transactions.arrive()
                return context
            }
        )
        let settings = try #require(resolver.resolve(SettingsManager.self))
        enableCommands(settings)

        let seed = stack.newTaskContext()
        let (overrideID, tempTargetID) = try await seed.perform {
            for (name, enabled) in [("Sport", false), ("Running", true)] {
                let row = OverrideStored(context: seed)
                row.id = UUID().uuidString
                row.name = name
                row.enabled = enabled
                row.date = Date().addingTimeInterval(-600)
                row.duration = NSDecimalNumber(value: 0)
                row.indefinite = true
                row.isPreset = true
                row.percentage = 100
            }
            for (name, enabled) in [("Walk", false), ("Hike", true)] {
                let row = TempTargetStored(context: seed)
                row.id = UUID()
                row.name = name
                row.enabled = enabled
                row.date = Date().addingTimeInterval(-600)
                row.duration = NSDecimalNumber(value: 60)
                row.target = NSDecimalNumber(value: 120)
                row.isPreset = true
                row.enteredBy = TempTarget.local
            }
            try seed.save()
            let overrides = try seed.fetch(NSFetchRequest<OverrideStored>(entityName: "OverrideStored"))
            let tempTargets = try seed.fetch(NSFetchRequest<TempTargetStored>(entityName: "TempTargetStored"))
            return (
                overrides.first { $0.name == "Sport" }!.id!,
                tempTargets.first { $0.name == "Walk" }!.id!.uuidString
            )
        }

        let actions = StubWatchCommandActions()
        actions.overrides = [WatchPresetEntry(name: "Sport", isActive: false, ref: .presetID(overrideID))]
        actions.tempTargets = [WatchPresetEntry(name: "Walk", isActive: false, ref: .presetID(tempTargetID))]
        let processor = BaseWatchCommandProcessor(resolver: resolver, actions: actions)

        let blocker = ContextQueueBlocker()
        blocker.block(context)
        let pending = Task { await processor.process(request(command)) }
        // past every processor check and inside the adjustment manager's transaction
        await transactions.waitForArrivals()

        settings.settings.isGarminCommandControlEnabled = false
        settings.settings.isGarminCommandControlEnabled = true
        blocker.release()
        let result = await pending.value

        #expect(result.acknowledged == false)
        #expect(result.ackCode == .genericFailure)
        #expect(context.saveCount == 0, "Nothing was saved")
        #expect(await context.perform { !context.hasChanges }, "Nothing was even staged")

        let enabled: [String] = try await seed.perform {
            seed.reset()
            let overrides = try seed.fetch(NSFetchRequest<OverrideStored>(entityName: "OverrideStored"))
                .filter(\.enabled).compactMap(\.name)
            let tempTargets = try seed.fetch(NSFetchRequest<TempTargetStored>(entityName: "TempTargetStored"))
                .filter(\.enabled).compactMap(\.name)
            return (overrides + tempTargets).sorted()
        }
        #expect(enabled == ["Hike", "Running"])

        // the same setup commits once nothing is revoked
        #expect(await processor.process(request(command)).acknowledged)
        #expect(context.saveCount == 1)
    }

    @Test(
        "Carbs queued behind a busy context are not stored once revoked",
        arguments: [false, true]
    ) func testCarbsRevokedWhileQueued(isMeal: Bool) async throws {
        let context = countingContext()
        let transactions = TestGate(isOpen: true)
        let pump = SpyAPSManager()
        let resolver = makeResolver(
            stack: stack,
            carbsContext: {
                transactions.arrive()
                return context
            },
            apsManager: pump
        )
        let settings = try #require(resolver.resolve(SettingsManager.self))
        enableCommands(settings)
        let processor = BaseWatchCommandProcessor(resolver: resolver, actions: BaseWatchCommandActions(resolver: resolver))

        let blocker = ContextQueueBlocker()
        blocker.block(context)
        let command: WatchCommand = isMeal ? .mealBolus(carbs: 40, bolus: 2) : .carbs(40)
        let pending = Task { await processor.process(request(command)) }
        await transactions.waitForArrivals()

        settings.settings.isGarminCommandControlEnabled = false
        settings.settings.isGarminCommandControlEnabled = true
        blocker.release()
        let result = await pending.value

        #expect(result.ackCode == .genericFailure, "Nothing was logged, so this is no partial failure")
        #expect(context.saveCount == 0)
        #expect(try await carbRows() == 0)
        #expect(pump.bolusRequests.isEmpty)

        #expect(await processor.process(request(.carbs(40))).acknowledged)
        #expect(try await carbRows() == 1)
    }

    @Test("The production bolus action checks right before it calls the pump") func testProductionIssuanceCheck() async throws {
        let stack = self.stack
        let pump = SpyAPSManager()
        let resolver = makeResolver(stack: stack, carbsContext: { stack.newTaskContext() }, apsManager: pump)
        let actions = BaseWatchCommandActions(resolver: resolver)

        await #expect(throws: WatchCommandRejection.self) {
            try await actions.enactBolus(2) { throw WatchCommandRejection(result: .failure("revoked")) }
        }
        #expect(pump.bolusRequests.isEmpty)

        let checks = LogCapture()
        let delivered = try await actions.enactBolus(2) {
            checks.record(.debug, pump.bolusRequests.isEmpty ? "before" : "after")
        }
        #expect(delivered)
        #expect(checks.lines == ["before"])
        #expect(pump.bolusRequests == [2])

        pump.bolusSucceeds = false
        let refused = try await actions.enactBolus(1) {}
        #expect(refused == false)
    }
}

// MARK: - Garmin Delivery And Recovery

/// Manual clock and timer queue for the Garmin transport; work only runs when a test advances time.
final class FakeGarminTransport: @unchecked Sendable {
    private struct Entry {
        let dueMS: UInt64
        let delay: TimeInterval
        let work: DispatchWorkItem
    }

    var nowMS: UInt64 = 1_000_000
    private var entries: [Entry] = []
    private(set) var lines: [String] = []

    func runtime(preparesWatchState: Bool = false) -> GarminTransportRuntime {
        GarminTransportRuntime(
            nowMS: { self.nowMS },
            scheduler: { delay, work in
                self.entries.append(Entry(dueMS: self.nowMS + UInt64(delay * 1000), delay: delay, work: work))
            },
            logSink: { line in self.lines.append(line) },
            preparesWatchState: preparesWatchState
        )
    }

    /// Delays of scheduled work that is neither cancelled nor run yet.
    var pendingDelays: [TimeInterval] {
        entries.filter { !$0.work.isCancelled }.map(\.delay)
    }

    /// Advances the clock, running due work in deadline order; cancelled work is skipped like GCD does.
    func advance(seconds: TimeInterval) {
        let target = nowMS + UInt64(seconds * 1000)
        while let index = entries.indices.filter({ entries[$0].dueMS <= target })
            .min(by: { entries[$0].dueMS < entries[$1].dueMS })
        {
            let entry = entries.remove(at: index)
            nowMS = max(nowMS, entry.dueMS)
            if !entry.work.isCancelled { entry.work.perform() }
        }
        nowMS = target
    }

    /// Runs every cancelled item anyway, to prove the transport's own tokens reject stale work.
    func forceRunCancelled() {
        let cancelled = entries.filter(\.work.isCancelled)
        entries.removeAll { $0.work.isCancelled }
        cancelled.forEach { $0.work.perform() }
    }

    func lines(_ event: String) -> [String] {
        lines.filter { $0.hasPrefix("garmin.\(event) ") }
    }

    func clearLines() {
        lines.removeAll()
    }
}

/// Reads one `key=value` field from a `garmin.*` line.
func garminField(_ key: String, in line: String) -> String? {
    line.split(separator: " ").first { $0.hasPrefix("\(key)=") }.map { String($0.dropFirst(key.count + 1)) }
}

/// Lets every block already queued on main, and the blocks they queue, run.
@MainActor func settleMain() async {
    for _ in 0 ..< 6 {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}

@MainActor final class GarminDeliveryFixture {
    let fake = FakeGarminTransport()
    let client = SpyConnectIQClient()
    let settings: SettingsManager
    let manager: BaseGarminManager
    let deviceA = IQDevice(id: UUID(), modelName: "fenix 8", friendlyName: "A")!
    let deviceB = IQDevice(id: UUID(), modelName: "Enduro 3", friendlyName: "B")!
    let watchfaceUUID: UUID
    let datafieldUUID = GarminDatafield.trio.datafieldUUID!

    init(
        watchface: GarminWatchface = .trio,
        datafields: [GarminDatafield] = [.trio],
        configure: (SettingsManager) -> Void = { _ in }
    ) async throws {
        let stack = try await CoreDataStack.createForTests()
        let resolver = makeResolver(stack: stack, carbsContext: { stack.newTaskContext() })
        let settings = try #require(resolver.resolve(SettingsManager.self))
        settings.settings.garminSettings.watchface = watchface
        settings.settings.garminSettings.isWatchfaceDataEnabled = true
        settings.settings.garminSettings.datafields = datafields
        configure(settings)
        self.settings = settings
        watchfaceUUID = watchface.watchfaceUUID!
        manager = BaseGarminManager(
            resolver: resolver,
            connectIQClient: client,
            presetChanges: Empty().eraseToAnyPublisher(),
            sendRetryDelay: 2,
            runtime: fake.runtime()
        )
        await settleMain()
    }

    deinit {
        let manager = manager
        DispatchQueue.main.async { manager.updateDeviceList([]) }
    }

    func select(_ devices: [IQDevice]) async {
        manager.updateDeviceList(devices)
        await settleMain()
    }

    func payload(_ glucose: Int) -> Data {
        try! JSONSerialization.data(withJSONObject: [["glucose": glucose, "trend": "flat"]])
    }

    func submit(_ glucose: Int) async {
        manager.sendWatchStateData(payload(glucose))
        await settleMain()
    }

    /// Submits and lets the 2 s debounce elapse.
    func broadcast(_ glucose: Int) async {
        await submit(glucose)
        await advance(seconds: 2)
    }

    func advance(seconds: TimeInterval) async {
        fake.advance(seconds: seconds)
        await settleMain()
    }

    func ready(_ device: IQDevice) async {
        client.deviceListener(device.uuid)?.deviceCharacteristicsDiscovered?(device)
        await settleMain()
    }

    func status(_ status: IQDeviceStatus, of device: IQDevice) async {
        client.deviceListener(device.uuid)?.deviceStatusChanged?(device, status: status)
        await settleMain()
    }

    func app(_ appUUID: UUID, on device: IQDevice) -> IQApp {
        IQApp(uuid: appUUID, store: UUID(), device: device)
    }

    var stateSends: [SpyConnectIQClient.Sent] {
        client.sent.filter { $0.request == nil }
    }

    func stateSends(_ appUUID: UUID, on device: IQDevice) -> [Int] {
        stateSends.filter { $0.appUUID == appUUID && $0.deviceUUID == device.uuid }.compactMap(\.stateValue)
    }
}

@Suite("Garmin Delivery Recovery Tests", .serialized) @MainActor struct GarminDeliveryRecoveryTests {
    // MARK: Latest-state delivery

    @Test("State goes out without a ready, dedups per target and isolates failing targets") func testPerTargetDelivery(
    ) async throws {
        let f = try await GarminDeliveryFixture()
        await f.select([f.deviceA, f.deviceB])

        await f.broadcast(100)
        #expect(f.stateSends.count == 4, "No ready or status preflight gates the first send")
        await f.broadcast(100)
        #expect(f.stateSends.count == 4, "Identical bytes are not resent to targets that confirmed them")

        f.client.queueResults([4], to: f.datafieldUUID, on: f.deviceB.uuid)
        await f.broadcast(110)
        await f.advance(seconds: 5)
        #expect(f.stateSends(f.datafieldUUID, on: f.deviceB) == [100, 110], "AppNotFound is terminal, no retry")
        #expect(f.stateSends(f.watchfaceUUID, on: f.deviceA) == [100, 110])
        await f.broadcast(110)
        #expect(f.stateSends.count == 8, "Healthy targets keep their confirmed state")

        await f.status(.notConnected, of: f.deviceA)
        await f.broadcast(120)
        #expect(f.stateSends(f.watchfaceUUID, on: f.deviceB) == [100, 110, 120])
        #expect(f.stateSends(f.watchfaceUUID, on: f.deviceA) == [100, 110], "A disconnected device gets nothing")
        #expect(f.stateSends(f.datafieldUUID, on: f.deviceB) == [100, 110], "An absent app gets nothing")

        await f.status(.connected, of: f.deviceA)
        #expect(f.stateSends(f.watchfaceUUID, on: f.deviceA) == [100, 110, 120], "Reconnect flushes only the latest state")
        #expect(f.stateSends(f.datafieldUUID, on: f.deviceA) == [100, 110, 120])

        f.client.deliver(["v": 1, "req": "status"], from: f.app(f.datafieldUUID, on: f.deviceB))
        await settleMain()
        #expect(f.stateSends(f.datafieldUUID, on: f.deviceB) == [100, 110, 120], "Inbound clears the absence of its source")

        let registrations = f.client.calls.count
        await f.ready(f.deviceA)
        await f.ready(f.deviceA)
        await f.select([f.deviceA, f.deviceB])
        await f.broadcast(120)
        #expect(f.client.calls.count == registrations, "Repeated selection registers nothing twice")
        #expect(f.client.calls("registerDevice").count == 2)
        #expect(f.client.calls("registerApp").count == 4)
        #expect(f.stateSends.count == 12, "Duplicate ready and identical state send nothing")
    }

    @Test("Targeted replies leave state dedup alone") func testRepliesDoNotTouchStateDedup() async throws {
        let f = try await GarminDeliveryFixture()
        await f.select([f.deviceA])
        await f.broadcast(100)
        #expect(f.stateSends.count == 2)

        f.client.queueResults([1, 1], to: f.watchfaceUUID, on: f.deviceA.uuid)
        f.client.deliver(["v": 1, "req": "presets"], from: f.app(f.watchfaceUUID, on: f.deviceA))
        #expect(await eventually { f.client.sent.contains { $0.request == "presets" } })
        await f.advance(seconds: 2)
        await f.advance(seconds: 2)
        let replies = f.client.sent.filter { $0.request == "presets" }
        #expect(replies.count == 2, "One original resend after a real failure, never more")
        let results = f.fake.lines("send.result").filter { garminField("kind", in: $0) == "targeted" }
        #expect(results.count == 2)
        #expect(garminField("retry_of", in: results[1]) == garminField("attempt_id", in: results[0]))
        #expect(garminField("payload_id", in: results[1]) == garminField("attempt_id", in: results[0]))

        await f.broadcast(100)
        #expect(f.stateSends.count == 2, "A failed reply neither resets nor resends state")
    }

    // MARK: Retries and staleness

    @Test("A retry never replays an older state while a newer one is debouncing") func testRetryDropsForPendingSubmission(
    ) async throws {
        let f = try await GarminDeliveryFixture(datafields: [])
        await f.select([f.deviceA])
        f.client.queueResults([1], to: f.watchfaceUUID, on: f.deviceA.uuid)
        await f.broadcast(100)

        await f.advance(seconds: 0.5)
        await f.submit(110)
        await f.advance(seconds: 1.5)
        #expect(f.stateSends(f.watchfaceUUID, on: f.deviceA) == [100], "The reserved retry yields to the debouncing state")
        await f.advance(seconds: 0.5)
        #expect(f.stateSends(f.watchfaceUUID, on: f.deviceA) == [100, 110])
        let starts = f.fake.lines("send.start")
        #expect(garminField("attempt", in: starts[1]) == "first")
    }

    @Test("A retry sends the newest debounced state and names the attempt it retries") func testRetryUsesNewestState(
    ) async throws {
        let f = try await GarminDeliveryFixture(datafields: [])
        await f.select([f.deviceA])
        f.client.completionMode = .held
        await f.broadcast(100)
        await f.broadcast(110)
        #expect(f.stateSends(f.watchfaceUUID, on: f.deviceA) == [100], "One state send in flight per target")

        f.client.completionMode = .inline
        f.client.completeHeld(1)
        await settleMain()
        await f.advance(seconds: 2)
        #expect(f.stateSends(f.watchfaceUUID, on: f.deviceA) == [100, 110])
        let starts = f.fake.lines("send.start")
        #expect(garminField("attempt", in: starts[1]) == "retry")
        #expect(garminField("retry_of", in: starts[1]) == garminField("attempt_id", in: starts[0]))
        #expect(garminField("payload_id", in: starts[1]) != garminField("payload_id", in: starts[0]))
    }

    @Test("Bytes already confirmed suppress a reserved retry") func testConfirmedBytesSuppressRetry() async throws {
        let f = try await GarminDeliveryFixture(datafields: [])
        await f.select([f.deviceA])
        await f.broadcast(100)
        f.client.completionMode = .held
        await f.broadcast(110)
        await f.broadcast(100)
        f.client.completionMode = .inline
        f.client.completeHeld(1)
        await settleMain()
        await f.advance(seconds: 2)
        #expect(f.stateSends(f.watchfaceUUID, on: f.deviceA) == [100, 110])
        #expect(f.fake.lines("send.start").count == 2, "The retry found the latest state already confirmed")
    }

    @Test("Duplicate and off-main completions are accepted once") func testDuplicateAndOffMainCompletions() async throws {
        let f = try await GarminDeliveryFixture(datafields: [])
        await f.select([f.deviceA])
        f.client.completionMode = .duplicate
        await f.broadcast(100)
        #expect(f.fake.lines("send.result").count == 1)

        f.client.completionMode = .offMain
        await f.broadcast(110)
        #expect(await eventually {
            await settleMain()
            return f.fake.lines("send.result").count == 2
        })
        await f.broadcast(110)
        #expect(f.stateSends.count == 2, "The off-main success was recorded on main")
    }

    @Test("Stale completions, relays and work cannot touch a re-added device") func testStaleIngressAfterReAdd() async throws {
        let f = try await GarminDeliveryFixture(datafields: [])
        await f.select([f.deviceA])
        let oldDeviceListener = try #require(f.client.deviceListener(f.deviceA.uuid))
        let oldAppListener = try #require(f.client.appListener(f.watchfaceUUID, on: f.deviceA.uuid))
        f.client.completionMode = .held
        await f.broadcast(100)

        await f.select([])
        await f.select([f.deviceA])
        #expect(f.client.calls("unregisterApp").count == 1)
        #expect(f.client.calls("unregisterDevice").count == 1)
        await f.broadcast(110)
        #expect(f.stateSends.count == 2)

        f.client.completeHeld(0)
        await settleMain()
        #expect(f.fake.lines("send.result").map { garminField("accepted", in: $0) } == ["false"])
        await f.broadcast(110)
        #expect(f.stateSends.count == 2, "The new attempt is still in flight")

        oldDeviceListener.deviceStatusChanged?(f.deviceA, status: .notConnected)
        oldAppListener.receivedMessage?(["v": 1, "req": "status"], from: f.app(f.watchfaceUUID, on: f.deviceA))
        await settleMain()
        f.client.completionMode = .inline
        f.client.completeHeld(0)
        await settleMain()
        await f.broadcast(120)
        #expect(f.stateSends(f.watchfaceUUID, on: f.deviceA) == [100, 110, 120], "The old listener could not mark a loss")
    }

    @Test("Cancelled retry work stays inert after a link loss") func testCancelledRetryAfterLoss() async throws {
        let f = try await GarminDeliveryFixture(datafields: [])
        await f.select([f.deviceA])
        f.client.queueResults([1], to: f.watchfaceUUID, on: f.deviceA.uuid)
        await f.broadcast(100)
        await f.status(.notConnected, of: f.deviceA)
        f.fake.forceRunCancelled()
        await settleMain()
        #expect(f.stateSends.count == 1)

        await f.status(.connected, of: f.deviceA)
        #expect(f.stateSends(f.watchfaceUUID, on: f.deviceA) == [100, 100], "Reconnect sends the owed state once")
    }

    @Test("A ready raised inline during registration is accepted") func testInlineReadyDuringRegistration() async throws {
        let f = try await GarminDeliveryFixture(datafields: [])
        f.client.onRegisterDevice = { device, listener in
            listener.deviceCharacteristicsDiscovered?(device)
        }
        await f.select([f.deviceA])
        #expect(f.fake.lines("device.ready").count == 1)
    }

    @Test("A new app waits for state prepared for its configuration") func testNewAppAwaitsNextBroadcast() async throws {
        let f = try await GarminDeliveryFixture(datafields: [])
        await f.select([f.deviceA])
        await f.broadcast(100)
        f.settings.settings.garminSettings.datafields = [.trio]
        await settleMain()
        #expect(f.client.calls("registerApp").count == 2)
        #expect(f.stateSends(f.datafieldUUID, on: f.deviceA).isEmpty, "The cached broadcast was built for another configuration")
        await f.broadcast(100)
        #expect(f.stateSends(f.datafieldUUID, on: f.deviceA) == [100])
        #expect(f.stateSends(f.watchfaceUUID, on: f.deviceA) == [100], "Existing apps keep their confirmed state")
    }
}
