import Foundation

enum GarminWatchSetting: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }
    case cob
    case sensRatio

    var displayName: String {
        switch self {
        case .cob:
            return String(localized: "COB", comment: "")
        case .sensRatio:
            return String(localized: "Sensitivity Rate", comment: "")
        }
    }
}
