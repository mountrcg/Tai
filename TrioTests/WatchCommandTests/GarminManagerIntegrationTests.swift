import Combine
import ConnectIQ
import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

func makeGarminResolver(stack: CoreDataStack, overrides: [Assembly]) -> Resolver {
    Assembler([
        StorageAssembly(),
        ServiceAssembly(),
        APSAssembly(),
        NetworkAssembly(),
        UIAssembly(),
        SecurityAssembly(),
        TestAssembly(testContext: stack.newTaskContext())
    ] + overrides).resolver
}

/// Stands in for the Connect IQ SDK, records every message with the exact app it targeted and
/// answers with scripted send results. It has no app-status API, like the production seam.
final class SpyConnectIQClient: GarminConnectIQClient, @unchecked Sendable {
    struct Sent {
        let message: Any
        let appUUID: UUID
        let deviceUUID: UUID

        var request: String? { (message as? [String: Any])?[WatchMessageKeys.request] as? String }
        var isState: Bool { message is [Any] }
    }

    private let lock = NSLock()
    private var messages: [Sent] = []
    private var scripted: [String: [IQSendMessageResult]] = [:]
    private var persistent: [String: IQSendMessageResult] = [:]

    var sent: [Sent] { lock.withLock { messages } }

    /// Consumed in order before falling back to the persistent result, then `.success`.
    func script(_ results: [IQSendMessageResult], for appUUID: UUID, on deviceUUID: UUID) {
        lock.withLock { scripted["\(appUUID)-\(deviceUUID)", default: []] += results }
    }

    func setResult(_ result: IQSendMessageResult?, for appUUID: UUID, on deviceUUID: UUID) {
        lock.withLock { persistent["\(appUUID)-\(deviceUUID)"] = result }
    }

    func registerDevice(_: IQDevice, delegate _: IQDeviceEventDelegate) {}

    func registerApp(_: IQApp, delegate _: IQAppMessageDelegate) {}

    func send(_ message: Any, to app: IQApp, completion: @escaping (IQSendMessageResult) -> Void) {
        let target = "\(app.uuid!)-\(app.device.uuid!)"
        let result: IQSendMessageResult = lock.withLock {
            messages.append(Sent(message: message, appUUID: app.uuid, deviceUUID: app.device.uuid))
            if var queue = scripted[target], !queue.isEmpty {
                let next = queue.removeFirst()
                scripted[target] = queue
                return next
            }
            return persistent[target] ?? .success
        }
        completion(result)
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

@Suite("Garmin Manager Delivery Tests", .serialized) final class GarminManagerDeliveryTests {
    let complicationUUID = GarminWatchface.complication.watchfaceUUID!
    let datafieldUUID = GarminDatafield.swissalpine.datafieldUUID!
    let deviceA = IQDevice(id: UUID(), modelName: "fenix 8", friendlyName: "A")!
    let deviceB = IQDevice(id: UUID(), modelName: "Enduro 3", friendlyName: "B")!

    let client = SpyConnectIQClient()
    let manager: BaseGarminManager

    init() async throws {
        let stack = try await CoreDataStack.createForTests()
        let resolver = makeGarminResolver(stack: stack, overrides: [])

        let settings = try #require(resolver.resolve(SettingsManager.self))
        settings.settings.garminSettings.watchface = .complication
        settings.settings.garminSettings.isWatchfaceDataEnabled = true
        settings.settings.garminSettings.datafield = .swissalpine

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

    private func broadcast(_ sgv: Int) {
        manager.sendWatchStateData(try! JSONSerialization.data(withJSONObject: [["sgv": sgv]]))
    }

    private func states(to appUUID: UUID? = nil, on device: IQDevice? = nil) -> [SpyConnectIQClient.Sent] {
        client.sent.filter {
            $0.isState && (appUUID == nil || $0.appUUID == appUUID) && (device == nil || $0.deviceUUID == device?.uuid)
        }
    }

    private func sent(_ request: String) -> [SpyConnectIQClient.Sent] {
        client.sent.filter { $0.request == request }
    }

    /// Lets queued main-queue work and debounces run before asserting that nothing more was sent.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    // MARK: - Broadcast

    @Test("Each app gets exactly one send per broadcast and an unchanged state is not resent") func testOneSendPerApp() async {
        broadcast(120)
        #expect(await eventually { self.states().count == 4 })

        broadcast(120)
        await settle()
        #expect(states().count == 4)

        broadcast(121)
        #expect(await eventually { self.states().count == 8 })
    }

    @Test("A state that failed for good stays owed and goes out with the next broadcast") func testFailedStateIsOwed() async {
        client.script([.failure_Timeout, .failure_Timeout], for: complicationUUID, on: deviceA.uuid)
        broadcast(120)
        #expect(await eventually { self.states(to: self.complicationUUID, on: self.deviceA).count == 2 })

        broadcast(120)
        #expect(await eventually { self.states(to: self.complicationUUID, on: self.deviceA).count == 3 })
        await settle()
        #expect(states().count == 6, "Only the owed app is resent an unchanged state")
    }

    @Test("AppNotFound is not resent and the app is skipped until it is heard from") func testAppNotFound() async {
        client.setResult(.failure_AppNotFound, for: datafieldUUID, on: deviceA.uuid)
        broadcast(120)
        #expect(await eventually { self.states().count == 4 })
        await settle()
        #expect(states(to: datafieldUUID, on: deviceA).count == 1, "No resend for an app that is not installed")

        broadcast(121)
        #expect(await eventually { self.states().count == 7 })
        await settle()
        #expect(states(to: datafieldUUID, on: deviceA).count == 1)

        client.setResult(nil, for: datafieldUUID, on: deviceA.uuid)
        // any message proves the channel; a status request would also start a refresh and blur the count
        manager.receivedMessage(["v": 1, "req": "presets"], from: app(datafieldUUID, on: deviceA))
        #expect(await eventually { self.states(to: self.datafieldUUID, on: self.deviceA).count == 2 })
    }

    @Test("A disconnected device gets nothing until it reconnects, then its owed state") func testDisconnectedGate() async {
        manager.deviceStatusChanged(deviceA, status: .notConnected)
        broadcast(120)
        #expect(await eventually { self.states(on: self.deviceB).count == 2 })
        await settle()
        #expect(states(on: deviceA).isEmpty, "No SDK traffic toward a disconnected watch")

        manager.deviceCharacteristicsDiscovered(deviceA)
        // the reconnect also starts a regular refresh, which may add more sends
        #expect(await eventually { self.states(on: self.deviceA).count >= 2 })
    }

    @Test("A message from an owed app delivers its state right away") func testInboundFlushesOwed() async {
        client.script([.failure_DeviceIsBusy, .failure_DeviceIsBusy], for: complicationUUID, on: deviceB.uuid)
        broadcast(120)
        #expect(await eventually { self.states(to: self.complicationUUID, on: self.deviceB).count == 2 })

        manager.receivedMessage(["v": 1, "req": "presets"], from: app(complicationUUID, on: deviceB))
        #expect(await eventually { self.states(to: self.complicationUUID, on: self.deviceB).count == 3 })
    }

    // MARK: - Inbound

    @Test("Status requests from registered apps refresh the state") func testStatusRefreshes() async {
        let triggers = RefreshTriggerRecorder(manager)
        manager.receivedMessage("status", from: app(complicationUUID, on: deviceA))

        #expect(await eventually { triggers.count("WatchRequest") == 1 })
    }

    @Test("A message from an unregistered device is ignored") func testUnregisteredDevice() async throws {
        let triggers = RefreshTriggerRecorder(manager)
        let stranger = try #require(IQDevice(id: UUID(), modelName: "fenix 8", friendlyName: "C"))
        manager.receivedMessage(["v": 1, "req": "status"], from: app(complicationUUID, on: stranger))

        await settle()
        #expect(client.sent.isEmpty)
        #expect(triggers.count("WatchRequest") == 0)
    }
}
