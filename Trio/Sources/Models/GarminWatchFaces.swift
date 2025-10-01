import Foundation

enum GarminWatchFaces: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case original
    case swissalpine

    var displayName: String {
        switch self {
        case .original:
            return String(localized: "Original Trio", comment: "")
        case .swissalpine:
            return String(localized: "Swissalpine xDrip+", comment: "")
        }
    }
}
