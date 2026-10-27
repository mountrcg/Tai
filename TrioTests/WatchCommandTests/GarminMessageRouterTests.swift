import Foundation
import Testing

@testable import Trio

@Suite("Garmin Message Router Tests") struct GarminMessageRouterTests {
    let appUUID = UUID()

    private func router(logs: LogCapture? = nil) -> GarminMessageRouter {
        var router = GarminMessageRouter()
        if let logs {
            router.log = logs.logger
        }
        return router
    }

    // MARK: - Parsing

    @Test("Bare status string is the legacy status request") func testLegacyStatus() {
        #expect(GarminMessageEnvelope.parse("status") == .legacyStatus)
        #expect(GarminMessageEnvelope.parse("bolus") == .invalid)
    }

    @Test("v1 status requests carry no other fields") func testReadRequests() {
        #expect(GarminMessageEnvelope.parse(["v": 1, "req": "status"]) == .status)
        #expect(GarminMessageEnvelope.parse(["v": 1, "req": "status", "extra": true]) == .invalid)
        #expect(GarminMessageEnvelope.parse(["v": 2, "req": "status"]) == .invalid)
        #expect(GarminMessageEnvelope.parse(["v": "1", "req": "status"]) == .invalid)
        #expect(GarminMessageEnvelope.parse(["v": true, "req": "status"]) == .invalid)
        #expect(GarminMessageEnvelope.parse(["v": 1, "req": "unknown"]) == .invalid)
        #expect(GarminMessageEnvelope.parse(42) == .invalid)
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

    @Test("Unregistered apps are ignored") func testUnregisteredApp() async {
        let outcome = await router().route("status", from: appUUID, isRegistered: false, appName: "test")

        #expect(outcome.reply == nil)
        #expect(outcome.refreshTrigger == nil)
    }

    @Test("Invalid messages get neither a reply nor a refresh") func testInvalidIgnored() async {
        let outcome = await router().route(["v": 1, "req": "bogus"], from: appUUID, isRegistered: true, appName: "test")

        #expect(outcome.reply == nil)
        #expect(outcome.refreshTrigger == nil)
    }
}
