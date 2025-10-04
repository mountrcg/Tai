import Foundation
import SwiftUI

struct GarminWatchState: Hashable, Equatable, Sendable, Encodable {
    var glucose: String?
    var trendRaw: String?
    var delta: String?
    var iob: String?
    var cob: String?
    var lastLoopDateInterval: UInt64?
    var eventualBGRaw: String?
    var isf: String?
    var sensRatio: String?

    static func == (lhs: GarminWatchState, rhs: GarminWatchState) -> Bool {
        lhs.glucose == rhs.glucose &&
            lhs.trendRaw == rhs.trendRaw &&
            lhs.delta == rhs.delta &&
            lhs.iob == rhs.iob &&
            lhs.cob == rhs.cob &&
            lhs.lastLoopDateInterval == rhs.lastLoopDateInterval &&
            lhs.eventualBGRaw == rhs.eventualBGRaw &&
            lhs.isf == rhs.isf &&
            lhs.sensRatio == rhs.sensRatio
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(glucose)
        hasher.combine(trendRaw)
        hasher.combine(delta)
        hasher.combine(iob)
        hasher.combine(cob)
        hasher.combine(lastLoopDateInterval)
        hasher.combine(eventualBGRaw)
        hasher.combine(isf)
        hasher.combine(sensRatio)
    }

    // Custom encoding to exclude nil values
    enum CodingKeys: String, CodingKey {
        case glucose
        case trendRaw
        case delta
        case iob
        case cob
        case lastLoopDateInterval
        case eventualBGRaw
        case isf
        case sensRatio
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(glucose, forKey: .glucose)
        try container.encodeIfPresent(trendRaw, forKey: .trendRaw)
        try container.encodeIfPresent(delta, forKey: .delta)
        try container.encodeIfPresent(iob, forKey: .iob)
        try container.encodeIfPresent(cob, forKey: .cob)
        try container.encodeIfPresent(lastLoopDateInterval, forKey: .lastLoopDateInterval)
        try container.encodeIfPresent(eventualBGRaw, forKey: .eventualBGRaw)
        try container.encodeIfPresent(isf, forKey: .isf)
        // sensRatio will only be encoded if it's not nil
        try container.encodeIfPresent(sensRatio, forKey: .sensRatio)
    }
}
