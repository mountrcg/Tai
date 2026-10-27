import Foundation
import Testing

@testable import Trio

@Suite("Garmin Message Router Tests") struct GarminMessageRouterTests {
    let requestID = "3f2b8c1e-4a5d-4e6f-9a7b-1c2d3e4f5a6b"
    let appUUID = UUID()
    let milliseconds: UInt64 = 1_800_000_000_123
    let presets = StubWatchPresetsProvider()

    private func router(
        _ processor: WatchCommandProcessor = SpyWatchCommandProcessor(),
        logs: LogCapture? = nil
    ) -> GarminMessageRouter {
        var router = GarminMessageRouter(processor: processor, loadPresets: { [presets] in try await presets.presets() })
        if let logs {
            router.log = logs.logger
        }
        return router
    }

    private func envelope(command: String, payload: [String: Any]) -> [String: Any] {
        [
            "v": 1,
            "req": "command",
            "requestId": requestID,
            "date": NSNumber(value: milliseconds),
            "command": command,
            "payload": payload
        ]
    }

    private func parsedCommand(_ message: Any) -> WatchCommand? {
        guard case let .command(_, _, _, command) = GarminMessageEnvelope.parse(message) else { return nil }
        return command
    }

    // MARK: - Parsing

    @Test("Bare status string is the legacy status request") func testLegacyStatus() {
        #expect(GarminMessageEnvelope.parse("status") == .legacyStatus)
        #expect(GarminMessageEnvelope.parse("bolus") == .invalid(requestID: nil))
    }

    @Test("v1 status and presets requests carry no other fields") func testReadRequests() {
        #expect(GarminMessageEnvelope.parse(["v": 1, "req": "status"]) == .status)
        #expect(GarminMessageEnvelope.parse(["v": 1, "req": "presets"]) == .presets)
        #expect(GarminMessageEnvelope.parse(["v": 1, "req": "presets", "extra": true]) == .invalid(requestID: nil))
        #expect(GarminMessageEnvelope.parse(["v": 2, "req": "status"]) == .invalid(requestID: nil))
        #expect(GarminMessageEnvelope.parse(["v": "1", "req": "status"]) == .invalid(requestID: nil))
        #expect(GarminMessageEnvelope.parse(["v": true, "req": "status"]) == .invalid(requestID: nil))
        #expect(GarminMessageEnvelope.parse(["v": 1, "req": "unknown"]) == .invalid(requestID: nil))
        #expect(GarminMessageEnvelope.parse(42) == .invalid(requestID: nil))
    }

    @Test("Every command parses with its exact payload") func testCommands() {
        #expect(parsedCommand(envelope(command: "bolus", payload: ["bolus": 1.5])) == .bolus(1.5))
        #expect(parsedCommand(envelope(command: "bolus", payload: ["bolus": 2])) == .bolus(2))
        #expect(parsedCommand(envelope(command: "carbs", payload: ["carbs": 45])) == .carbs(45))
        #expect(
            parsedCommand(envelope(command: "mealBolus", payload: ["carbs": 45, "bolus": 3.25]))
                == .mealBolus(carbs: 45, bolus: 3.25)
        )
        #expect(
            parsedCommand(envelope(command: "activateOverride", payload: ["name": "Sport"])) ==
                .activateOverride(name: "Sport")
        )
        #expect(parsedCommand(envelope(command: "cancelOverride", payload: [:])) == .cancelOverride)
        #expect(
            parsedCommand(envelope(command: "activateTempTarget", payload: ["name": "Walk"])) == .activateTempTarget(name: "Walk")
        )
        #expect(parsedCommand(envelope(command: "cancelTempTarget", payload: [:])) == .cancelTempTarget)
    }

    @Test("The command date is read as Unix milliseconds") func testDate() {
        guard case let .command(echoedID, uuid, date, _) = GarminMessageEnvelope.parse(
            envelope(command: "carbs", payload: ["carbs": 10])
        ) else {
            Issue.record("Expected a command")
            return
        }
        #expect(echoedID == requestID)
        #expect(uuid == UUID(uuidString: requestID))
        #expect(abs(date.timeIntervalSince1970 - 1_800_000_000.123) < 0.000_1)
    }

    @Test("A Monkey C Float bolus is rounded to 0.001 U") func testFloatRounding() {
        let payload: [String: Any] = ["bolus": NSNumber(value: Float(0.1))]
        #expect(parsedCommand(envelope(command: "bolus", payload: payload)) == .bolus(Decimal(string: "0.1")!))
    }

    @Test("Malformed commands are rejected but keep their request ID for the ack") func testMalformedPayloads() {
        let cases: [(command: String, payload: [String: Any])] = [
            ("bolus", ["bolus": true]),
            ("bolus", ["bolus": "1"]),
            ("bolus", ["bolus": 1, "note": "x"]),
            ("bolus", [:]),
            ("carbs", ["carbs": 12.5]),
            ("carbs", ["carbs": "12"]),
            ("mealBolus", ["carbs": 20]),
            ("activateOverride", ["name": 3]),
            ("activateOverride", [:]),
            ("cancelOverride", ["name": "Sport"]),
            ("requestBolusRecommendation", [:]),
            ("unknown", [:])
        ]
        for (command, payload) in cases {
            #expect(
                GarminMessageEnvelope.parse(envelope(command: command, payload: payload)) == .invalid(requestID: requestID),
                "\(command) with \(payload.keys.sorted())"
            )
        }
    }

    @Test("Malformed envelopes are rejected") func testMalformedEnvelopes() {
        var extraField = envelope(command: "carbs", payload: ["carbs": 10])
        extraField["auth"] = ["scheme": "hmac-sha256"]
        #expect(GarminMessageEnvelope.parse(extraField) == .invalid(requestID: requestID))

        var missingDate = envelope(command: "carbs", payload: ["carbs": 10])
        missingDate["date"] = nil
        #expect(GarminMessageEnvelope.parse(missingDate) == .invalid(requestID: requestID))

        var negativeDate = envelope(command: "carbs", payload: ["carbs": 10])
        negativeDate["date"] = -1
        #expect(GarminMessageEnvelope.parse(negativeDate) == .invalid(requestID: requestID))

        var badPayload = envelope(command: "carbs", payload: ["carbs": 10])
        badPayload["payload"] = "none"
        #expect(GarminMessageEnvelope.parse(badPayload) == .invalid(requestID: requestID))

        var wrongVersion = envelope(command: "carbs", payload: ["carbs": 10])
        wrongVersion["v"] = 2
        #expect(GarminMessageEnvelope.parse(wrongVersion) == .invalid(requestID: requestID))
    }

    @Test("Request IDs must be RFC 4122 UUIDs") func testRequestIDFormat() {
        #expect(GarminMessageEnvelope.rfc4122UUID(requestID) != nil)
        #expect(GarminMessageEnvelope.rfc4122UUID(requestID.uppercased()) != nil)
        // variant nibble 'c' is the Microsoft layout, not RFC 4122
        #expect(GarminMessageEnvelope.rfc4122UUID("3f2b8c1e-4a5d-4e6f-ca7b-1c2d3e4f5a6b") == nil)
        #expect(GarminMessageEnvelope.rfc4122UUID("3f2b8c1e4a5d4e6f9a7b1c2d3e4f5a6b") == nil)
        #expect(GarminMessageEnvelope.rfc4122UUID("not-a-uuid") == nil)
    }

    // MARK: - Routing

    @Test("Status requests refresh the broadcast state and send no reply") func testStatusRouting() async {
        let messages: [Any] = ["status", ["v": 1, "req": "status"] as [String: Any]]
        for message in messages {
            let outcome = await router().route(message, from: appUUID, isRegistered: true, appName: "test")
            #expect(outcome.reply == nil)
            #expect(outcome.refreshTrigger == "WatchRequest")
        }
    }

    @Test("Unregistered apps are ignored without executing") func testUnregisteredApp() async {
        let processor = SpyWatchCommandProcessor()
        let outcome = await router(processor).route(
            envelope(command: "carbs", payload: ["carbs": 10]),
            from: appUUID,
            isRegistered: false,
            appName: "test"
        )

        #expect(outcome.reply == nil)
        #expect(outcome.refreshTrigger == nil)
        #expect(processor.processed.isEmpty)
    }

    @Test("Invalid messages get neither a reply nor a refresh") func testInvalidIgnored() async {
        let outcome = await router().route(["v": 1, "req": "bogus"], from: appUUID, isRegistered: true, appName: "test")

        #expect(outcome.reply == nil)
        #expect(outcome.refreshTrigger == nil)
    }

    @Test("A preset reply carries the switches and limits the watch reads") func testPresetsReplySwitches() async throws {
        let processor = SpyWatchCommandProcessor()
        processor.capabilitiesResult = WatchCommandCapabilities(
            isCommandControlEnabled: true,
            isBolusCommandEnabled: false,
            maxBolus: 5,
            maxCarbs: 120,
            bolusIncrement: 0.05
        )

        let outcome = await router(processor)
            .route(["v": 1, "req": "presets"], from: appUUID, isRegistered: true, appName: "test")

        let reply = try #require(outcome.reply)
        #expect(Set(reply.keys) == [
            "v", "req", "overridePresets", "tempTargetPresets",
            "isCommandControlEnabled", "isBolusCommandEnabled", "maxBolus", "maxCarbs", "bolusIncrement"
        ])
        #expect(reply["req"] as? String == "presets")
        #expect((reply["overridePresets"] as? [[String: Any]])?.isEmpty == true)
        #expect((reply["tempTargetPresets"] as? [[String: Any]])?.isEmpty == true)
        #expect(reply["isCommandControlEnabled"] as? Bool == true)
        #expect(reply["maxCarbs"] as? Double == 120)
        // a Decimal float literal is not exact, so compare with a tolerance
        #expect(abs((reply["bolusIncrement"] as? Double ?? 0) - 0.05) < 1E-9)
        #expect(outcome.refreshTrigger == nil)
    }

    @Test("A preset request gets a targeted presets reply and no broadcast refresh") func testPresetsReply() async throws {
        presets.overrides = [WatchPresetEntry(name: "Sport", isActive: true, ref: .presetID("sport"))]
        presets.tempTargets = [WatchPresetEntry(name: "Walk", isActive: false, ref: .presetID("walk"))]

        let outcome = await router().route(["v": 1, "req": "presets"], from: appUUID, isRegistered: true, appName: "test")

        let reply = try #require(outcome.reply)
        #expect(Set(reply.keys) == [
            "v", "req", "overridePresets", "tempTargetPresets",
            "isCommandControlEnabled", "isBolusCommandEnabled", "maxBolus", "maxCarbs", "bolusIncrement"
        ])
        #expect(reply["req"] as? String == "presets")
        let overrides = try #require(reply["overridePresets"] as? [[String: Any]])
        #expect(overrides.first?["name"] as? String == "Sport")
        #expect(overrides.first?["isEnabled"] as? Bool == true)
        let tempTargets = try #require(reply["tempTargetPresets"] as? [[String: Any]])
        #expect(tempTargets.first?["name"] as? String == "Walk")
        #expect(outcome.refreshTrigger == nil)
    }

    @Test("A preset load failure is logged by category only") func testPresetErrorSanitized() async {
        presets.error = SensitiveTestError()
        let logs = LogCapture()

        let outcome = await router(logs: logs)
            .route(["v": 1, "req": "presets"], from: appUUID, isRegistered: true, appName: "test")

        #expect(outcome.reply == nil)
        #expect(logs.entries.contains { $0.level == .warning && $0.line.contains("(unexpected)") })
        #expect(logs.lines.allSatisfy { !$0.contains(SensitiveTestError.marker) })
    }

    @Test("A command gets exactly the v1 ack and triggers a refresh on success") func testCommandAck() async throws {
        let processor = SpyWatchCommandProcessor()
        let sut = router(processor)

        let outcome = await sut.route(
            envelope(command: "carbs", payload: ["carbs": 10]),
            from: appUUID,
            isRegistered: true,
            appName: "test"
        )

        let reply = try #require(outcome.reply)
        #expect(Set(reply.keys) == ["v", "req", "requestId", "acknowledged", "ackCode", "message"])
        #expect(reply["v"] as? Int == 1)
        #expect(reply["req"] as? String == "ack")
        #expect(reply["requestId"] as? String == requestID)
        #expect(reply["acknowledged"] as? Bool == true)
        #expect(reply["ackCode"] as? String == "carbs_logged")
        #expect(outcome.refreshTrigger == "WatchCommand")

        #expect(processor.processed.count == 1)
        #expect(processor.processed.first?.appUUID == appUUID)
        #expect(processor.processed.first?.command == .carbs(10))
    }

    @Test("Failures do not refresh; partial failures do") func testRefreshRules() async {
        let processor = SpyWatchCommandProcessor()
        let sut = router(processor)
        let message = envelope(command: "mealBolus", payload: ["carbs": 10, "bolus": 1])

        processor.result = .failure("Watch commands are disabled.")
        let failed = await sut.route(message, from: appUUID, isRegistered: true, appName: "test")
        #expect(failed.refreshTrigger == nil)
        #expect(failed.reply?["ackCode"] as? String == "failure")

        processor.result = WatchCommandResult(acknowledged: false, ackCode: .partialFailure, message: "Carbs logged.")
        let partial = await sut.route(message, from: appUUID, isRegistered: true, appName: "test")
        #expect(partial.refreshTrigger == "WatchCommand")
        #expect(partial.reply?["ackCode"] as? String == "partial_failure")
    }

    @Test("Only successful preset commands push the preset list") func testPresetPushRules() async {
        let processor = SpyWatchCommandProcessor()
        let sut = router(processor)

        processor.result = .success(.overrideStarted, "Override started.")
        let started = await sut.route(
            envelope(command: "activateOverride", payload: ["name": "Sport"]),
            from: appUUID,
            isRegistered: true,
            appName: "test"
        )
        #expect(started.pushesPresets)

        processor.result = .success(.tempTargetStopped, "Temp target stopped.")
        let stopped = await sut.route(
            envelope(command: "cancelTempTarget", payload: [:]),
            from: appUUID,
            isRegistered: true,
            appName: "test"
        )
        #expect(stopped.pushesPresets)

        processor.result = .failure("Override preset not found.")
        let failed = await sut.route(
            envelope(command: "activateOverride", payload: ["name": "Sport"]),
            from: appUUID,
            isRegistered: true,
            appName: "test"
        )
        #expect(failed.pushesPresets == false)

        processor.result = .success(.carbsLogged, "Carbs logged.")
        let carbs = await sut.route(
            envelope(command: "carbs", payload: ["carbs": 10]),
            from: appUUID,
            isRegistered: true,
            appName: "test"
        )
        #expect(carbs.pushesPresets == false)
    }

    @Test("Invalid commands are answered only when they name a request ID") func testInvalidReplies() async {
        let processor = SpyWatchCommandProcessor()
        let sut = router(processor)

        let named = await sut.route(
            envelope(command: "carbs", payload: ["carbs": "ten"]),
            from: appUUID,
            isRegistered: true,
            appName: "test"
        )
        #expect(named.reply?["requestId"] as? String == requestID)
        #expect(named.reply?["acknowledged"] as? Bool == false)
        #expect(named.refreshTrigger == nil)

        let anonymous = await sut.route(["v": 1, "req": "command"], from: appUUID, isRegistered: true, appName: "test")
        #expect(anonymous.reply == nil)
        #expect(processor.processed.isEmpty)
    }

    // MARK: - Presets

    @Test("Presets are sorted by name and keep their state") func testPresetsSorted() async throws {
        presets.overrides = [
            WatchPresetEntry(name: "b", isActive: false, ref: .presetID("b")),
            WatchPresetEntry(name: "A", isActive: true, ref: .presetID("A")),
            WatchPresetEntry(name: "c", isActive: false, ref: .presetID("c"))
        ]
        presets.tempTargets = [
            WatchPresetEntry(name: "Walk 10", isActive: false, ref: .presetID("10")),
            WatchPresetEntry(name: "Walk 9", isActive: false, ref: .presetID("9"))
        ]

        let sorted = try await presets.presets()

        #expect(sorted.overridePresets == [
            OverridePresetWatch(name: "A", isEnabled: true),
            OverridePresetWatch(name: "b", isEnabled: false),
            OverridePresetWatch(name: "c", isEnabled: false)
        ])
        #expect(sorted.tempTargetPresets.map(\.name) == ["Walk 9", "Walk 10"])
    }
}

@Suite("Garmin Command Settings Migration Tests") struct GarminCommandSettingsMigrationTests {
    @Test("Settings written before commands existed decode with both switches off") func testMissingKeysDefaultOff() throws {
        let settings = try JSONDecoder().decode(TrioSettings.self, from: Data(#"{"isWatchfaceDataEnabled": true}"#.utf8))

        #expect(settings.isWatchfaceDataEnabled == true)
        #expect(settings.garminSettings.isCommandControlEnabled == false)
        #expect(settings.garminSettings.isBolusCommandEnabled == false)
    }

    @Test("Command switches survive an encode/decode round trip") func testRoundTrip() throws {
        var settings = TrioSettings()
        settings.garminSettings.isCommandControlEnabled = true
        settings.garminSettings.isBolusCommandEnabled = true

        let decoded = try JSONDecoder().decode(TrioSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded.isGarminCommandControlEnabled == true)
        #expect(decoded.isGarminBolusCommandEnabled == true)
        #expect(decoded.garminSettings == settings.garminSettings)
    }

    @Test("GarminWatchSettings without command keys keeps its other values") func testGroupedSettingsMigration() throws {
        let json =
            #"{"watchface": "swissalpine", "datafield": "swissalpine", "primaryAttributeChoice": "isf", "secondaryAttributeChoice": "eventualBG", "isWatchfaceDataEnabled": true}"#
        let settings = try JSONDecoder().decode(GarminWatchSettings.self, from: Data(json.utf8))

        #expect(settings.watchface == .swissalpine)
        #expect(settings.datafield == .swissalpine)
        #expect(settings.primaryAttributeChoice == .isf)
        #expect(settings.isWatchfaceDataEnabled == true)
        #expect(settings.isCommandControlEnabled == false)
        #expect(settings.isBolusCommandEnabled == false)
    }
}
