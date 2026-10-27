import Foundation

/// A state-changing command sent from a watch, already parsed and type-checked by its transport.
enum WatchCommand: Hashable {
    case bolus(Decimal)
    case carbs(Int)
    /// Carbs are stored before the bolus runs, so a rejected bolus still leaves the meal logged.
    case mealBolus(carbs: Int, bolus: Decimal)
    case activateOverride(name: String)
    case cancelOverride
    case activateTempTarget(name: String)
    case cancelTempTarget

    /// Wire name of the command; also the only command detail that is safe to log.
    var name: String {
        switch self {
        case .bolus: return "bolus"
        case .carbs: return "carbs"
        case .mealBolus: return "mealBolus"
        case .activateOverride: return "activateOverride"
        case .cancelOverride: return "cancelOverride"
        case .activateTempTarget: return "activateTempTarget"
        case .cancelTempTarget: return "cancelTempTarget"
        }
    }

    var bolusAmount: Decimal? {
        switch self {
        case let .bolus(units),
             let .mealBolus(_, units):
            return units
        default:
            return nil
        }
    }

    var carbsAmount: Int? {
        switch self {
        case let .carbs(grams),
             let .mealBolus(grams, _):
            return grams
        default:
            return nil
        }
    }

    var isInsulin: Bool { bolusAmount != nil }

    /// Commands whose success changes which preset is active on the watch's preset list.
    var changesPresetState: Bool {
        switch self {
        case .activateOverride,
             .activateTempTarget,
             .cancelOverride,
             .cancelTempTarget:
            return true
        default:
            return false
        }
    }
}

struct WatchCommandRequest: Equatable {
    let requestID: UUID
    /// Request IDs are only unique per watch app.
    let appUUID: UUID
    /// When the watch issued the command.
    let date: Date
    let command: WatchCommand
}

/// Switches and limits the watch uses to offer only what the phone accepts; the phone still enforces
/// each of them. The defaults describe a phone that accepts nothing.
struct WatchCommandCapabilities: Equatable {
    var isCommandControlEnabled = false
    var isBolusCommandEnabled = false
    var maxBolus: Decimal = 0
    var maxCarbs: Decimal = 0
    var bolusIncrement: Decimal = 0
}
