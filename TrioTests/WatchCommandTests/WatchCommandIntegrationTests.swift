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

    init(
        carbsContext: @escaping () -> NSManagedObjectContext,
        validator: BolusSafetyValidator,
        processor: WatchCommandProcessor?,
        apsManager: APSManager?
    ) {
        self.carbsContext = carbsContext
        self.validator = validator
        self.processor = processor
        self.apsManager = apsManager
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
    }
}

private func makeResolver(
    stack: CoreDataStack,
    carbsContext: @escaping () -> NSManagedObjectContext,
    validator: BolusSafetyValidator = StubBolusSafetyValidator(),
    processor: WatchCommandProcessor? = nil,
    apsManager: APSManager? = nil
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
            apsManager: apsManager
        )
        // same scope as the app, so the test and the managers share one settings manager
    ], parent: nil, defaultObjectScope: .container).resolver
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
            log: logs.logger
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

@Suite("Garmin Manager Command Integration Tests", .serialized) final class GarminManagerCommandIntegrationTests {
    let complicationUUID = GarminWatchface.complication.watchfaceUUID!
    let datafieldUUID = GarminDatafield.swissalpine.datafieldUUID!
    let deviceA = IQDevice(id: UUID(), modelName: "fenix 8", friendlyName: "A")!
    let deviceB = IQDevice(id: UUID(), modelName: "Enduro 3", friendlyName: "B")!

    let processor: SpyWatchCommandProcessor
    let client: SpyConnectIQClient
    let settings: SettingsManager
    let authorization: WatchCommandAuthorization
    let manager: BaseGarminManager

    init() async throws {
        let stack = try await CoreDataStack.createForTests()
        let processor = SpyWatchCommandProcessor()
        let client = SpyConnectIQClient()
        let resolver = makeResolver(stack: stack, carbsContext: { stack.newTaskContext() }, processor: processor)

        let settings = try #require(resolver.resolve(SettingsManager.self))
        settings.settings.garminSettings.watchface = .complication
        settings.settings.garminSettings.isWatchfaceDataEnabled = true
        settings.settings.garminSettings.datafield = .swissalpine
        settings.settings.garminSettings.isCommandControlEnabled = true
        // settings persist on the simulator between runs, so start from a known state
        settings.settings.garminSettings.isBolusCommandEnabled = false
        settings.settings.maxCarbs = 100

        self.processor = processor
        self.client = client
        self.settings = settings
        authorization = try #require(resolver.resolve(WatchCommandAuthorization.self))
        manager = BaseGarminManager(
            resolver: resolver,
            connectIQClient: client,
            sendRetryDelay: 0.01,
            broadcastDebounce: .milliseconds(10)
        )
        manager.updateDeviceList([deviceA, deviceB])
    }

    deinit {
        // the device list is persisted in user defaults
        manager.updateDeviceList([])
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
        manager.receivedMessage(
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
            client.sent.filter { !$0.isState }.allSatisfy { $0.appUUID != datafieldUUID },
            "Nothing command-related is fanned out"
        )
    }

    @Test("A failed ack is resent once to the same app and never owed") func testAckRetryTarget() async {
        client.script([.failure_Timeout, .failure_Timeout], for: complicationUUID, on: deviceA.uuid)
        let requestID = UUID().uuidString
        manager.receivedMessage(
            command("carbs", payload: ["carbs": 20], requestID: requestID),
            from: app(complicationUUID, on: deviceA)
        )

        #expect(await eventually { self.sent("ack").count == 2 })
        let acks = sent("ack")
        #expect(acks.allSatisfy { $0.appUUID == complicationUUID && $0.deviceUUID == deviceA.uuid })
        #expect(acks.allSatisfy { ($0.message as? [String: Any])?["requestId"] as? String == requestID })

        // the watch expires an unanswered command itself, so later deliveries carry no stale ack
        manager.sendWatchStateData(try! JSONSerialization.data(withJSONObject: [["sgv": 120]]))
        #expect(await eventually { self.client.sent.contains { $0.isState } })
        try? await Task.sleep(nanoseconds: 150_000_000)
        #expect(sent("ack").count == 2)
    }

    @Test(
        "Command switch and max carbs changes push the preset reply to Complication apps only"
    ) func testSettingsPushPresets() async {
        settings.settings.garminSettings.isBolusCommandEnabled = true

        #expect(await eventually { self.sent("presets").count == 2 })
        #expect(sent("presets").allSatisfy { $0.appUUID == complicationUUID })

        settings.settings.maxCarbs = 99
        #expect(await eventually { self.sent("presets").count == 4 })

        settings.settings.garminSettings.primaryAttributeChoice = .isf
        try? await Task.sleep(nanoseconds: 200_000_000)
        #expect(sent("presets").count == 4, "Display settings do not push the preset reply")
    }

    @Test("A command from an unregistered device is ignored") func testUnregisteredDevice() async throws {
        let stranger = try #require(IQDevice(id: UUID(), modelName: "fenix 8", friendlyName: "C"))
        manager.receivedMessage(
            command("carbs", payload: ["carbs": 20], requestID: UUID().uuidString),
            from: app(complicationUUID, on: stranger)
        )

        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(client.sent.isEmpty)
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

// MARK: - Revocation And Final Boundaries

/// Runs revocation through the production settings manager, Garmin manager, processor and storage;
/// only the pump, the safety validator and the Connect IQ SDK are stand-ins.
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
            sendRetryDelay: 0.01,
            broadcastDebounce: .milliseconds(10)
        )
        manager.updateDeviceList([device])
        defer { manager.updateDeviceList([]) }
        let triggers = RefreshTriggerRecorder(manager)

        let complicationUUID = try #require(GarminWatchface.complication.watchfaceUUID)
        manager.receivedMessage(
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
            checks.record(pump.bolusRequests.isEmpty ? "before" : "after")
        }
        #expect(delivered)
        #expect(checks.lines == ["before"])
        #expect(pump.bolusRequests == [2])

        pump.bolusSucceeds = false
        let refused = try await actions.enactBolus(1) {}
        #expect(refused == false)
    }
}
