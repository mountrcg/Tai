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
}
