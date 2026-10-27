import Foundation

// MARK: - Garmin Data Type Settings

/// Primary attribute selection for Garmin watchface and datafield.
/// Determines whether to display COB, ISF, or Sensitivity Ratio alongside glucose data.
/// Used by both Trio and SwissAlpine watchfaces.
enum GarminPrimaryAttributeChoice: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }

    case cob
    case isf
    case sensRatio

    var displayName: String {
        switch self {
        case .cob:
            return String(localized: "COB", comment: "")
        case .isf:
            return String(localized: "ISF", comment: "")
        case .sensRatio:
            return String(localized: "Sens Ratio", comment: "")
        }
    }
}

/// Secondary attribute selection for both Trio and SwissAlpine watchfaces.
/// Determines whether to display Temp Basal Rate or Eventual BG.
enum GarminSecondaryAttributeChoice: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }

    case tbr
    case eventualBG

    var displayName: String {
        switch self {
        case .tbr:
            return String(localized: "TBR", comment: "")
        case .eventualBG:
            return String(localized: "evBG", comment: "")
        }
    }
}

// MARK: - Garmin Watchface Setting

/// Defines the available Garmin watchfaces with their associated UUIDs.
enum GarminWatchface: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }

    case trio
    case swissalpine
    /// Not a watchface but a Connect IQ watch app that republishes the payload as
    /// complications, so any watchface with complication slots can show Trio data.
    /// It takes the watchface slot because someone on complications is by definition
    /// not running one of the Trio watchfaces, which leaves that slot free.
    case complication

    var displayName: String {
        switch self {
        case .trio:
            return String(localized: "Trio", comment: "")
        case .swissalpine:
            return String(localized: "Swissalpine", comment: "")
        case .complication:
            return String(localized: "Complication", comment: "")
        }
    }

    /// The UUID for the watchface applications in Garmin Connect IQ
    var watchfaceUUID: UUID? {
        switch self {
        case .trio:
            // return UUID(uuidString: "EC3420F6-027D-49B3-B45F-D81D6D3ED90A")  // local build
            // return UUID(uuidString: "81204522-B1BE-4E19-8E6E-C4032AAF8C6D") // ConnectIQ test build
            return UUID(uuidString: "7a121867-140e-41ba-9982-2e82e2aa6579") // ConnectIQ live build
        case .swissalpine:
            // return UUID(uuidString: "5A643C13-D5A7-40D4-B809-84789FDF4A1F") // ConnectIQ test build
            return UUID(uuidString: "4cea4efd-4aaf-4db4-8891-ef36dde14303") // ConnectIQ live build
        case .complication:
            return UUID(uuidString: "0986fd19-604b-4bcb-a931-6f8621738682") // ConnectIQ live build
            // return UUID(uuidString: "a897ce34-1135-4632-b855-1c75f1ec27bf") // ConnectIQ beta build
        }
    }
}

// MARK: - Garmin Command App

/// Connect IQ watch app that sends commands next to a Trio or Swissalpine watchface.
enum GarminWatchControls {
    static let displayName = "Trio-WatchControls"
    static let appUUID = UUID(uuidString: "d504737e-8315-48d4-b07e-4c421ffb6f54")
}

/// The one watch app allowed to send commands; with both command apps installed, both would otherwise prompt.
/// Raw values are the `owner` the watch reads from the command app notice.
enum GarminCommandApp: String {
    case complication
    case watchControls
    case none

    /// The watchface selection decides, since Complication then runs in the watchface slot.
    init(_ settings: GarminWatchSettings) {
        if settings.watchface == .complication {
            self = .complication
        } else {
            self = settings.isCommandControlEnabled ? .watchControls : .none
        }
    }

    var appUUID: UUID? {
        switch self {
        case .complication: return GarminWatchface.complication.watchfaceUUID
        case .watchControls: return GarminWatchControls.appUUID
        case .none: return nil
        }
    }

    static let appUUIDs = Set([GarminWatchface.complication.watchfaceUUID, GarminWatchControls.appUUID].compactMap { $0 })
}

// MARK: - Garmin Datafield Setting

/// Defines the available Garmin datafields with their associated UUIDs.
enum GarminDatafield: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    var id: String { rawValue }

    case trio
    case swissalpine
    case loopgraph
    case none

    var displayName: String {
        switch self {
        case .trio:
            return String(localized: "Trio", comment: "")
        case .swissalpine:
            return String(localized: "Swissalpine", comment: "")
        case .loopgraph:
            return String(localized: "LoopGraph", comment: "")
        case .none:
            return String(localized: "None", comment: "")
        }
    }

    /// The UUID for the datafield application in Garmin Connect IQ
    var datafieldUUID: UUID? {
        switch self {
        case .trio:
            // return UUID(uuidString: "71cf0982-ca41-42a5-8441-ea81d36056c3")  // local build
            // return UUID(uuidString: "f07f4ef9-108b-4397-95c9-217b5173412e")  // ConnectIQ test build
            return UUID(uuidString: "3d9b6528-8c84-459a-bbab-989b5f001ebd") // ConnectIQ live build
        case .swissalpine:
            // return UUID(uuidString: "7A2268F6-3381-4474-81BD-0A3E7F458CB7") // ConnectIQ test build
            return UUID(uuidString: "dec5292a-74b0-41bc-8e45-cd93f1d5e137") // ConnectIQ live build
        case .loopgraph:
            return UUID(uuidString: "986105b6-5d20-4895-a5c1-b98248ddde4c") // beta build Robert
        // return UUID(uuidString: "2e18aaa2-2b57-47d3-8ace-f9cd27c0d765") // original build (local)
        case .none:
            return nil
        }
    }

    /// The datafields the user can pick from. `.none` is not offered as a choice any more:
    /// "no datafield" is expressed by an empty selection.
    static var selectableCases: [GarminDatafield] {
        allCases.filter { $0 != .none }
    }

    /// Maximum number of datafields that can receive data at the same time.
    /// Every selected datafield is registered as its own Connect IQ app and gets the
    /// same broadcast payload, so this caps how many apps a single update fans out to.
    static let maxSelectionCount = 4

    /// Normalizes a selection read from settings: drops `.none`, removes duplicates
    /// and enforces `maxSelectionCount`, preserving the original order.
    static func sanitizedSelection(_ datafields: [GarminDatafield]) -> [GarminDatafield] {
        var selection = [GarminDatafield]()
        for datafield in datafields where datafield != .none && !selection.contains(datafield) {
            selection.append(datafield)
            if selection.count == maxSelectionCount { break }
        }
        return selection
    }
}

// MARK: - Garmin Watch Settings Group

/// Groups related Garmin watch settings together for easier management.
/// Both watchfaces use the same settings: primaryAttributeChoice and secondaryAttributeChoice.
struct GarminWatchSettings: Codable, Hashable {
    var watchface: GarminWatchface = .trio
    /// Datafields that receive data, in selection order. Empty means no datafield is used.
    /// Never holds more than `GarminDatafield.maxSelectionCount` entries.
    var datafields: [GarminDatafield] = [.trio]
    var primaryAttributeChoice: GarminPrimaryAttributeChoice = .cob
    var secondaryAttributeChoice: GarminSecondaryAttributeChoice = .tbr
    var isWatchfaceDataEnabled: Bool = false
    /// Master switch for state-changing watch commands; status and preset reads ignore it.
    var isCommandControlEnabled: Bool = false
    /// Allows bolus and meal+bolus commands; only effective while `isCommandControlEnabled` is on.
    var isBolusCommandEnabled: Bool = false

    /// Adds or removes a datafield from the selection, ignoring additions beyond the maximum.
    mutating func toggleDatafield(_ datafield: GarminDatafield) {
        if let index = datafields.firstIndex(of: datafield) {
            datafields.remove(at: index)
        } else if datafields.count < GarminDatafield.maxSelectionCount {
            datafields.append(datafield)
        }
    }

    /// Whether the given datafield can still be added to the selection.
    func canSelectDatafield(_ datafield: GarminDatafield) -> Bool {
        datafields.contains(datafield) || datafields.count < GarminDatafield.maxSelectionCount
    }
}

extension GarminWatchSettings {
    /// Pre-multi-datafield releases wrote a singular `datafield` key; it has no backing property,
    /// so it decodes through its own container rather than widening the Codable `CodingKeys`.
    private enum LegacyCodingKeys: String, CodingKey {
        case datafield
    }

    /// Keys missing from settings written by older versions keep their defaults, so commands stay off.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        self.init()
        if let watchface = try? container.decode(GarminWatchface.self, forKey: .watchface) {
            self.watchface = watchface
        }
        if let datafields = try? container.decode([GarminDatafield].self, forKey: .datafields) {
            self.datafields = GarminDatafield.sanitizedSelection(datafields)
        } else if let legacyDatafield = try? legacyContainer.decode(GarminDatafield.self, forKey: .datafield) {
            datafields = GarminDatafield.sanitizedSelection([legacyDatafield])
        }
        if let primaryAttributeChoice = try? container
            .decode(GarminPrimaryAttributeChoice.self, forKey: .primaryAttributeChoice)
        {
            self.primaryAttributeChoice = primaryAttributeChoice
        }
        if let secondaryAttributeChoice = try? container.decode(
            GarminSecondaryAttributeChoice.self,
            forKey: .secondaryAttributeChoice
        ) {
            self.secondaryAttributeChoice = secondaryAttributeChoice
        }
        if let isWatchfaceDataEnabled = try? container.decode(Bool.self, forKey: .isWatchfaceDataEnabled) {
            self.isWatchfaceDataEnabled = isWatchfaceDataEnabled
        }
        if let isCommandControlEnabled = try? container.decode(Bool.self, forKey: .isCommandControlEnabled) {
            self.isCommandControlEnabled = isCommandControlEnabled
        }
        if let isBolusCommandEnabled = try? container.decode(Bool.self, forKey: .isBolusCommandEnabled) {
            self.isBolusCommandEnabled = isBolusCommandEnabled
        }
    }
}
