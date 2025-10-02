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
    var aiSR: String?

    static func == (lhs: GarminWatchState, rhs: GarminWatchState) -> Bool {
        lhs.glucose == rhs.glucose &&
            lhs.trendRaw == rhs.trendRaw &&
            lhs.delta == rhs.delta &&
            lhs.iob == rhs.iob &&
            lhs.cob == rhs.cob &&
            lhs.lastLoopDateInterval == rhs.lastLoopDateInterval &&
            lhs.eventualBGRaw == rhs.eventualBGRaw &&
            lhs.isf == rhs.isf &&
            lhs.aiSR == rhs.aiSR
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
        hasher.combine(aiSR)
    }
}

// MARK: - Swiss Alpine Watchface Data Structure

struct SwissAlpineGlucoseEntry: Encodable {
    let date: UInt64
    let sgv: Int
    let delta: Double
    let direction: String
    let noise: Double
    let units_hint: String?
    let iob: Double?
    let tbr: Int?
    let cob: Double?

    init(
        date: UInt64,
        sgv: Int,
        delta: Double,
        direction: String,
        noise: Double = 0.0,
        units_hint: String? = nil,
        iob: Double? = nil,
        tbr: Int? = nil,
        cob: Double? = nil
    ) {
        self.date = date
        self.sgv = sgv
        self.delta = delta
        self.direction = direction
        self.noise = noise
        self.units_hint = units_hint
        self.iob = iob
        self.tbr = tbr
        self.cob = cob
    }
}
