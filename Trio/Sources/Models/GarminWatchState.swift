import Foundation
import SwiftUI

// MARK: - Unified Garmin Watch State

/// Unified watch state structure for both Trio and SwissAlpine watchfaces.
/// Uses the SwissAlpine xDrip+ compatible data format.
/// Sent as an array where the first entry contains all extended data fields.
struct GarminWatchState: Hashable, Equatable, Sendable, Encodable {
    /// Timestamp of the glucose reading in milliseconds since Unix epoch
    var date: UInt64?
    var sgv: Int16?
    var delta: Int16?
    /// Glucose trend direction (e.g., "Flat", "FortyFiveUp", "SingleUp")
    var direction: String?
    /// Unit hint for the watchface ("mgdl" or "mmol")
    var units_hint: String?
    var iob: Double?
    var tbr: Double?
    var cob: Double?
    var eventualBG: Int16?
    var isf: Int16?
    var sensRatio: Double?

    // MARK: - Display Configuration Fields

    /// Specifies which data field to display as primary (dataType1)
    /// Options: "cob" or "sensRatio"
    var displayDataType1: String?

    /// Specifies which data field to display as secondary (dataType2)
    /// Options: "tbr" or "eventualBG"
    var displayDataType2: String?

    static func == (lhs: GarminWatchState, rhs: GarminWatchState) -> Bool {
        lhs.date == rhs.date &&
            lhs.sgv == rhs.sgv &&
            lhs.delta == rhs.delta &&
            lhs.direction == rhs.direction &&
            lhs.units_hint == rhs.units_hint &&
            lhs.iob == rhs.iob &&
            lhs.tbr == rhs.tbr &&
            lhs.cob == rhs.cob &&
            lhs.eventualBG == rhs.eventualBG &&
            lhs.isf == rhs.isf &&
            lhs.sensRatio == rhs.sensRatio &&
            lhs.displayDataType1 == rhs.displayDataType1 &&
            lhs.displayDataType2 == rhs.displayDataType2
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(date)
        hasher.combine(sgv)
        hasher.combine(delta)
        hasher.combine(direction)
        hasher.combine(units_hint)
        hasher.combine(iob)
        hasher.combine(tbr)
        hasher.combine(cob)
        hasher.combine(eventualBG)
        hasher.combine(isf)
        hasher.combine(sensRatio)
        hasher.combine(displayDataType1)
        hasher.combine(displayDataType2)
    }

    enum CodingKeys: String, CodingKey {
        case date
        case sgv
        case delta
        case direction
        case units_hint
        case iob
        case tbr
        case cob
        case eventualBG
        case isf
        case sensRatio
        case displayDataType1
        case displayDataType2
    }

    /// Custom encoding that excludes nil values from the JSON output
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(date, forKey: .date)
        try container.encodeIfPresent(sgv, forKey: .sgv)
        try container.encodeIfPresent(delta, forKey: .delta)
        try container.encodeIfPresent(direction, forKey: .direction)
        try container.encodeIfPresent(units_hint, forKey: .units_hint)
        try container.encodeIfPresent(iob, forKey: .iob)
        try container.encodeIfPresent(tbr, forKey: .tbr)
        try container.encodeIfPresent(cob, forKey: .cob)
        try container.encodeIfPresent(eventualBG, forKey: .eventualBG)
        try container.encodeIfPresent(isf, forKey: .isf)
        try container.encodeIfPresent(sensRatio, forKey: .sensRatio)
        try container.encodeIfPresent(displayDataType1, forKey: .displayDataType1)
        try container.encodeIfPresent(displayDataType2, forKey: .displayDataType2)
    }
}
