import Foundation

extension CGMCatalogEntry {
    var supportsRawGlucoseObservations: Bool {
        switch source {
        case let .managed(_, id): return Self.supportsRawGlucoseObservations(identifier: id)
        case .native: return false
        }
    }

    static func supportsRawGlucoseObservations(identifier: String) -> Bool {
        ["LibreTransmitterManagerV3", "LibreLoopCGMManager", "SyaiCGMManager"].contains(identifier)
    }

    /// Identity of a source that can deliver sub-5-minute readings, nil otherwise. The glucose
    /// simulator qualifies too: its interval can be set down to 1 minute.
    static func denseObservationSourceID(cgm: CGMType, pluginIdentifier: String) -> String? {
        switch cgm {
        case .plugin: return supportsRawGlucoseObservations(identifier: pluginIdentifier) ? pluginIdentifier : nil
        case .simulator: return CGMType.simulator.id
        default: return nil
        }
    }
}
