import Foundation
import Testing
@testable import Trio

/// `TempBasalFunctions.roundBasal` must reproduce the paired driver's own rate table.
/// Tables are built arithmetically here so this suite runs in the algorithm-only SPM target;
/// `BasalRoundingDriverParityTests` checks them against the real kits.
@Suite("Round Basal Tests") struct RoundBasalTests {
    /// Dana: 0.01 U/hr flat, up to 3 U/hr.
    static let danaRates: [Decimal] = (0 ... 300).map { Decimal($0) / 100 }

    /// Omnipod Eros: 0.05 U/hr flat to 30, and no zero rate.
    static let erosRates: [Decimal] = (1 ... 600).map { Decimal($0) / 20 }

    /// Omnipod non-Eros and Medtrum: 0.05 U/hr flat, zero allowed.
    static let flatRates: [Decimal] = (0 ... 600).map { Decimal($0) / 20 }

    /// Minimed pre-x23: 0.05 U/hr flat to 35.
    static let minimedPre23Rates: [Decimal] = (0 ... 700).map { Decimal($0) / 20 }

    /// Minimed gen >= 23: 0.025 below 1 U/hr, 0.05 to 9.95, 0.1 above.
    static let minimedGen23Rates: [Decimal] = (0 ... 39).map { Decimal($0) / 40 }
        + (20 ... 199).map { Decimal($0) / 20 }
        + (100 ... 350).map { Decimal($0) / 10 }

    private func profile(_ rates: [Decimal]) -> Profile {
        var profile = Profile()
        profile.supportedBasalRates = rates
        return profile
    }

    private func round(_ rate: Decimal, _ rates: [Decimal]) -> Decimal {
        TempBasalFunctions.roundBasal(profile: profile(rates), basalRate: rate)
    }

    @Test("Dana keeps the 0.01 resolution the pump delivers") func danaResolution() {
        // the regression from issue #1424: the old bands turned this into 1.25
        #expect(round(1.23, Self.danaRates) == 1.23)
        #expect(round(0.01, Self.danaRates) == 0.01)
        // built as Decimal(57) / 100: the literal 0.57 is parsed via Double and is not exact
        #expect(round(0.567, Self.danaRates) == Decimal(57) / 100)
    }

    @Test("Dana clamps to the top of its table") func danaCeiling() {
        #expect(round(4, Self.danaRates) == 3)
    }

    @Test("flat 0.05 pumps keep rates above 10 U/hr") func flatAboveTen() {
        // the old bands switched to 0.1 above 10 and pushed this to 10.1
        #expect(round(10.05, Self.flatRates) == 10.05)
        #expect(round(10.05, Self.minimedPre23Rates) == 10.05)
    }

    @Test("Omnipod Eros rounds onto its own minimum or to zero") func erosBelowMinimum() {
        // the pod's table has no zero, so zero has to come from the seed
        #expect(round(0.01, Self.erosRates) == 0)
        #expect(round(0.03, Self.erosRates) == 0.05)
        #expect(round(0.07, Self.erosRates) == 0.05)
    }

    @Test("Minimed gen >= 23 keeps its 0.025 resolution") func minimedFineResolution() {
        // dead in production before this change: model.json was always "722"
        #expect(round(0.025, Self.minimedGen23Rates) == 0.025)
        #expect(round(0.03, Self.minimedGen23Rates) == 0.025)
        #expect(round(1.03, Self.minimedGen23Rates) == 1.05)
        #expect(round(10.06, Self.minimedGen23Rates) == 10.1)
    }

    @Test("no pump paired leaves the rate alone but keeps it readable") func noPump() {
        #expect(round(1.23, []) == 1.23)
        #expect(round(12.345678, []) == 12.345)
    }

    @Test("an unsorted or duplicated table gives the sorted answer") func unorderedTable() {
        let shuffled: [Decimal] = [1.0, 0.05, 0.5, 0.05, 0.1]
        #expect(round(0.6, shuffled) == 0.5)
        #expect(round(0.04, shuffled) == 0.05)
    }

    @Test("every result is a rate the pump can hold, within half a step", arguments: [
        Decimal(0), 0.011, 0.03, 0.4, 0.999, 1.0, 1.234, 5.375, 9.99, 10.06, 29.999
    ]) func landsOnTheTable(rate: Decimal) {
        for rates in [Self.danaRates, Self.erosRates, Self.flatRates, Self.minimedGen23Rates] {
            let rounded = round(rate, rates)
            #expect(rounded == 0 || rates.contains(rounded))
            // half a step, unless the rate is off the top of the table and clamps to it
            #expect(abs(rounded - rate) <= 0.05 || rate > rates[rates.count - 1])
        }
    }

    @Test("setTempBasal delivers a Dana rate at full resolution") func setTempBasalKeepsResolution() throws {
        var profile = profile(Self.danaRates)
        profile.currentBasal = 0.8
        profile.maxDailyBasal = 1.3
        profile.maxBasal = 3.0

        let requestedTemp = try TempBasalFunctions.setTempBasal(
            rate: 1.23,
            duration: 30,
            profile: profile,
            determination: Determination.roundBasalTestStub,
            currentTemp: TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date())
        )

        #expect(requestedTemp.rate == 1.23)
    }

    @Test("setTempBasal rounds a capped rate onto the nearest deliverable one") func cappedRateRounds() throws {
        var profile = profile(Self.flatRates)
        profile.currentBasal = 0.8
        profile.maxDailyBasal = 0.99
        profile.maxBasal = 2.97
        profile.maxDailySafetyMultiplier = 3
        profile.currentBasalSafetyMultiplier = 4

        let maxSafeBasal = try TempBasalFunctions.getMaxSafeBasalRate(profile: profile)
        let requestedTemp = try TempBasalFunctions.setTempBasal(
            rate: 5,
            duration: 30,
            profile: profile,
            determination: Determination.roundBasalTestStub,
            currentTemp: TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date())
        )

        // rounding to nearest can carry a cap up half a step; 2.97 is nearer 2.95
        #expect(requestedTemp.rate ?? 0 <= maxSafeBasal)
        #expect(requestedTemp.rate == 2.95)
    }

    @Test("computeAdjustedBasal keeps Dana resolution through the sensitivity ratio") func computeAdjustedBasalResolution() {
        let adjusted = DeterminationGenerator.computeAdjustedBasal(
            profile: profile(Self.danaRates),
            currentBasalRate: 1.23,
            sensitivityRatio: 1,
            overrideFactor: 1
        )

        #expect(adjusted == 1.23)
    }
}

private extension Determination {
    /// Minimal determination for exercising `setTempBasal`.
    static var roundBasalTestStub: Determination {
        Determination(
            id: UUID(),
            reason: "",
            units: nil,
            insulinReq: nil,
            eventualBG: nil,
            sensitivityRatio: nil,
            rate: nil,
            duration: nil,
            iob: nil,
            cob: nil,
            predictions: nil,
            deliverAt: Date(),
            carbsReq: nil,
            temp: .absolute,
            bg: nil,
            reservoir: nil,
            isf: nil,
            timestamp: Date(),
            tdd: nil,
            current_target: nil,
            minDelta: nil,
            expectedDelta: nil,
            minGuardBG: nil,
            minPredBG: nil,
            threshold: nil,
            carbRatio: nil,
            received: false,
            smbRatio: nil,
            duraISFratio: nil,
            bgISFratio: nil,
            ppISFratio: nil,
            acceISFratio: nil,
            autoISFratio: nil,
            iobTH: nil,
            tick: nil,
            parabolaFitMinutes: nil,
            parabolaFitLastDelta: nil,
            parabolaFitNextDelta: nil,
            parabolaFitCorrelation: nil,
            parabolaFitA0: nil,
            parabolaFitA1: nil,
            parabolaFitA2: nil,
            duraMin: nil,
            duraAvg: nil,
            bgAcce: nil,
            bgi: nil,
            deviation: nil,
            iobActivity: nil
        )
    }
}
