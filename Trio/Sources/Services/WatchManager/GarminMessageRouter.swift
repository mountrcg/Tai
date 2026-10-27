import Foundation

/// A message received from a Connect IQ app, after envelope validation.
enum GarminInboundMessage: Equatable {
    /// Bare `"status"` string sent by watch apps that predate the v1 envelope.
    case legacyStatus
    case status
    case invalid
}

/// Garmin v1 wire contract: parsing inbound envelopes and building the targeted replies.
enum GarminMessageEnvelope {
    static let protocolVersion = 1

    enum Request: String {
        case status
    }

    private static let readEnvelopeKeys: Set<String> = [WatchMessageKeys.protocolVersion, WatchMessageKeys.request]

    static func parse(_ message: Any) -> GarminInboundMessage {
        if let string = message as? String {
            return string == Request.status.rawValue ? .legacyStatus : .invalid
        }
        guard let envelope = message as? [String: Any],
              integer(envelope[WatchMessageKeys.protocolVersion]) == Int64(protocolVersion),
              let request = (envelope[WatchMessageKeys.request] as? String).flatMap(Request.init(rawValue:)),
              Set(envelope.keys) == readEnvelopeKeys
        else {
            return .invalid
        }

        switch request {
        case .status: return .status
        }
    }

    // MARK: - Value Types

    /// Connect IQ delivers every number, and booleans too, as `NSNumber`; booleans are not numbers here.
    static func number(_ value: Any?) -> NSNumber? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue.isFinite ? number : nil
    }

    static func integer(_ value: Any?) -> Int64? {
        guard let number = number(value) else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double, abs(double) < 9.0E15 else { return nil }
        return number.int64Value
    }
}

/// Connect IQ side of watch messages: one inbound message becomes at most one reply for the
/// requesting app plus an optional state refresh. It has no broadcast path by design.
struct GarminMessageRouter {
    struct Outcome {
        /// Sent to the requesting `IQApp` only.
        var reply: [String: Any]?
        /// Trigger name for a regular watch-state update, if one is due.
        var refreshTrigger: String?

        static let none = Outcome(reply: nil, refreshTrigger: nil)
    }

    var log: WatchCommandLogger = .app

    func route(_ message: Any, from appUUID: UUID, isRegistered: Bool, appName: String) async -> Outcome {
        let inbound = GarminMessageEnvelope.parse(message)
        log.debug("Garmin \(appName) sent a \(inbound.logName)")

        guard isRegistered else {
            log.info("Ignored a \(inbound.logName) from unregistered Garmin app \(appUUID.uuidString)")
            return .none
        }

        switch inbound {
        case .legacyStatus,
             .status:
            return Outcome(reply: nil, refreshTrigger: "WatchRequest")

        case .invalid:
            return .none
        }
    }
}

private extension GarminInboundMessage {
    var logName: String {
        switch self {
        case .legacyStatus: return "legacy status request"
        case .status: return "status request"
        case .invalid: return "invalid message"
        }
    }
}
