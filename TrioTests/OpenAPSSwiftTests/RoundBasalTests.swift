import Foundation
import Testing
@testable import Trio

/// `TempBasalFunctions.roundBasal` must reproduce the paired driver's own rate table.
/// Tables come from `PumpRateTables` so this suite runs in the algorithm-only SPM target;
/// `BasalRoundingDriverParityTests` checks them against the real kits.
@Suite("Round Basal Tests") struct RoundBasalTests {
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
        #expect(round(1.23, PumpRateTables.dana) == 1.23)
        #expect(round(0.01, PumpRateTables.dana) == 0.01)
        // built as Decimal(57) / 100: the literal 0.57 is parsed via Double and is not exact
        #expect(round(0.567, PumpRateTables.dana) == Decimal(57) / 100)
    }

    @Test("Dana clamps to the top of its table") func danaCeiling() {
        #expect(round(4, PumpRateTables.dana) == 3)
    }

    @Test("flat 0.05 pumps keep rates above 10 U/hr") func flatAboveTen() {
        // the old bands switched to 0.1 above 10 and pushed this to 10.1
        #expect(round(10.05, PumpRateTables.flat) == 10.05)
        #expect(round(10.05, PumpRateTables.minimedPre23) == 10.05)
    }

    @Test("Omnipod Eros rounds onto its own minimum or to zero") func erosBelowMinimum() {
        // the pod's table has no zero, so zero has to come from the seed
        #expect(round(0.01, PumpRateTables.omnipodEros) == 0)
        #expect(round(0.03, PumpRateTables.omnipodEros) == 0.05)
        #expect(round(0.07, PumpRateTables.omnipodEros) == 0.05)
    }

    @Test("Minimed gen >= 23 keeps its 0.025 resolution") func minimedFineResolution() {
        // dead in production before this change: model.json was always "722"
        #expect(round(0.025, PumpRateTables.minimedGen23) == 0.025)
        #expect(round(0.03, PumpRateTables.minimedGen23) == 0.025)
        #expect(round(1.03, PumpRateTables.minimedGen23) == 1.05)
        #expect(round(10.06, PumpRateTables.minimedGen23) == 10.1)
    }

    @Test("no pump paired leaves the rate alone but keeps it readable") func noPump() {
        #expect(round(1.23, []) == 1.23)
        #expect(round(12.345678, []) == 12.34567)
    }

    @Test("an unsorted or duplicated table gives the sorted answer") func unorderedTable() {
        let shuffled: [Decimal] = [1.0, 0.05, 0.5, 0.05, 0.1]
        #expect(round(0.6, shuffled) == 0.5)
        #expect(round(0.04, shuffled) == 0.05)
    }

    @Test("every result is a rate the pump can hold, within half a step", arguments: [
        Decimal(0), 0.011, 0.03, 0.4, 0.999, 1.0, 1.234, 5.375, 9.99, 10.06, 29.999
    ]) func landsOnTheTable(rate: Decimal) {
        for rates in [PumpRateTables.dana, PumpRateTables.omnipodEros, PumpRateTables.flat, PumpRateTables.minimedGen23] {
            let rounded = round(rate, rates)
            #expect(rounded == 0 || rates.contains(rounded))
            #expect(abs(rounded - rate) <= 0.05 || rate > rates[rates.count - 1])
        }
    }

    @Test("setTempBasal delivers a Dana rate at full resolution") func setTempBasalKeepsResolution() throws {
        var profile = profile(PumpRateTables.dana)
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

    @Test("setTempBasal never rounds above the max safe basal rate") func neverExceedsMaxSafeBasal() throws {
        var profile = profile(PumpRateTables.flat)
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

        // round-half-up could land a 2.97 cap on 3.0; flooring cannot
        #expect(requestedTemp.rate ?? 0 <= maxSafeBasal)
        #expect(requestedTemp.rate == 2.95)
    }

    @Test("computeAdjustedBasal keeps Dana resolution through the sensitivity ratio") func computeAdjustedBasalResolution() {
        let adjusted = DeterminationGenerator.computeAdjustedBasal(
            profile: profile(PumpRateTables.dana),
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
            deliverAt: nil,
            carbsReq: nil,
            temp: nil,
            bg: nil,
            reservoir: nil,
            isf: nil,
            timestamp: nil,
            tdd: nil,
            current_target: nil,
            minDelta: nil,
            expectedDelta: nil,
            minGuardBG: nil,
            minPredBG: nil,
            threshold: nil,
            carbRatio: nil,
            received: false,
            tick: nil
        )
    }
}

/// The basal editor's picker round-trips its value through `Double`, then resolves it against the
/// concentration-adjusted rate grid with `nearestSupportedBasalRate`, the rule `roundBasal` uses.
@Suite("Basal editor picker rate selection") struct BasalEditorPickerRateTests {
    private static let decimilliTable: [Decimal] = (0 ... 350).map { Decimal($0) / 10 }
    private static let tables: [[Decimal]] = [PumpRateTables.dana, PumpRateTables.minimedGen23, PumpRateTables.flat, decimilliTable]
    private static let concentrations: [Decimal] = [Decimal(1) / 10, Decimal(1) / 2, 1, 2]

    /// What the picker's `tag(Double(value))` / `Decimal($0)` round-trip hands back.
    private func pickerRoundTrip(_ value: Decimal) -> Decimal {
        Decimal(Double(truncating: value as NSNumber))
    }

    @Test("U10 on a 0.025 pump keeps 0.0425 instead of flattening it to 0.04") func u10Regression() throws {
        let grid = PumpRateTables.minimedGen23.map { $0 / 10 }
        let target = Decimal(425) / 10000
        let targetIndex = try #require(grid.firstIndex(of: target))
        let picked = pickerRoundTrip(grid[targetIndex])

        // the old fixed-scale floor truncated the round-tripped value below the rate it represents
        #expect(picked.rounded(scale: 3) < target)

        let nearest = picked.nearestSupportedBasalRate(in: grid)
        #expect(nearest == target)
        #expect(grid.firstIndex(of: nearest) == targetIndex)
        #expect(nearest != Decimal(4) / 100)
    }

    @Test("U10 on a 0.025 pump resolves neighbouring four-decimal rates to themselves", arguments: [
        Decimal(25) / 1000, Decimal(175) / 1000, Decimal(575) / 1000, Decimal(825) / 1000
    ]) func u10Neighbours(pumpRate: Decimal) {
        let grid = PumpRateTables.minimedGen23.map { $0 / 10 }
        let rate = pumpRate / 10
        #expect(grid.contains(rate))
        #expect(pickerRoundTrip(rate).nearestSupportedBasalRate(in: grid) == rate)
    }

    @Test("U50 on a 0.025 pump resolves four-decimal rates to themselves", arguments: [
        Decimal(125) / 10000, Decimal(375) / 10000, Decimal(625) / 10000
    ]) func u50FourDecimals(rate: Decimal) {
        let grid = PumpRateTables.minimedGen23.map { $0 / 2 }
        #expect(grid.contains(rate))
        #expect(pickerRoundTrip(rate).nearestSupportedBasalRate(in: grid) == rate)
    }

    @Test("every grid entry survives the picker round-trip for each step and concentration") func everyGridEntry() {
        var mismatches: [String] = []
        for table in Self.tables {
            for concentration in Self.concentrations {
                let grid = table.map { $0 * concentration }
                for rate in grid where pickerRoundTrip(rate).nearestSupportedBasalRate(in: grid) != rate {
                    mismatches.append("\(rate) at concentration \(concentration)")
                }
            }
        }
        #expect(mismatches.isEmpty, "\(mismatches.prefix(10))")
    }

    @Test("matches roundBasal on the same tables") func parityWithRoundBasal() {
        let probes: [Decimal] = [0, 0.001, 0.0124, 0.0125, 0.03, 0.0425, 0.4, 0.999, 1.0, 1.234, 5.375, 9.99, 10.06, 29.999, 40]
        for table in Self.tables {
            var profile = Profile()
            profile.supportedBasalRates = table
            for probe in probes {
                #expect(probe.nearestSupportedBasalRate(in: table) == TempBasalFunctions.roundBasal(profile: profile, basalRate: probe))
            }
        }
    }
}
