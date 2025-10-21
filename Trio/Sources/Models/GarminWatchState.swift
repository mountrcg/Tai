//
//  GarminWatchState.swift
//  Trio
//
//  Created by Cengiz Deniz on 25.01.25.
//
import Foundation
import SwiftUI

struct GarminWatchState: Hashable, Equatable, Sendable, Encodable {
    var glucose: String?
    var trendRaw: String?
    var delta: String?
    var iob: String?
    var cob: String?
    var lastLoopDateInterval: UInt64?
    var eventualBG: String?
    var isf: String?

    static func == (lhs: GarminWatchState, rhs: GarminWatchState) -> Bool {
        lhs.glucose == rhs.glucose &&
            lhs.trendRaw == rhs.trendRaw &&
            lhs.delta == rhs.delta &&
            lhs.iob == rhs.iob &&
            lhs.cob == rhs.cob &&
            lhs.lastLoopDateInterval == rhs.lastLoopDateInterval &&
            lhs.eventualBG == rhs.eventualBG &&
            lhs.isf == rhs.isf
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(glucose)
        hasher.combine(trendRaw)
        hasher.combine(delta)
        hasher.combine(iob)
        hasher.combine(cob)
        hasher.combine(lastLoopDateInterval)
        hasher.combine(eventualBG)
        hasher.combine(isf)
    }
}
