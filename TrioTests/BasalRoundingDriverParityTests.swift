import DanaKit
import Foundation
import MedtrumKit
import MinimedKit
import Testing

@testable import Trio

/// Pins `TempBasalFunctions.roundBasal` against the real pump kits' own rate tables. The
/// algorithm rounds to nearest and the driver floors, so the guarantee is not that they agree
/// on an arbitrary rate, but that whatever the algorithm commits to survives the driver
/// untouched - including the trip through insulin concentration. `RoundBasalTests` covers the
/// same shapes arithmetically for the algorithm-only SPM target, which cannot import the kits.
@Suite("Basal Rounding Driver Parity") struct BasalRoundingDriverParityTests {
    /// Mirrors `APSManager.supportedBasalRates`: the 3 dp normalisation is what keeps a
    /// `Double(n) / 20` table entry from landing just above the clean rate it represents.
    private func normalised(_ rates: [Double]) -> [Decimal] {
        rates.map { Decimal($0).rounded(scale: 3) }
    }

    /// the shape every kit implements, and LoopKit's default
    private func driver(_ table: [Double], _ unitsPerHour: Decimal) -> Decimal {
        let rate = table.last(where: { $0 <= Double(truncating: unitsPerHour as NSNumber) }) ?? 0
        return Decimal(rate).rounded(scale: 3)
    }

    private func algorithm(_ table: [Decimal], _ rate: Decimal) -> Decimal {
        var profile = Profile()
        profile.supportedBasalRates = table
        return TempBasalFunctions.roundBasal(profile: profile, basalRate: rate)
    }

    /// Values chosen to land on, just below, and just above real table steps.
    private static let probes: [Decimal] = [
        0, 0.01, 0.024, 0.025, 0.03, 0.049, 0.05, 0.07, 0.5, 0.975, 0.99,
        1, 1.03, 1.23, 2.5, 3, 3.01, 5.375, 9.95, 10, 10.05, 10.06, 24.9, 30, 35, 40
    ]

    private static let tables: [(String, [Double])] = [
        ("Minimed 723 (gen >= 23)", PumpModel.model723.supportedBasalRates),
        ("Minimed 522 (pre-x23)", PumpModel.model522.supportedBasalRates),
        ("Dana", DanaKitPumpManager.onboardingSupportedBasalRates),
        ("Medtrum", MedtrumPumpManager.onboardingSupportedBasalRates),
        // Pod's table is a local inside OmnipodKit's BasalDeliveryTable, so replicate Eros here
        ("Omnipod Eros", (1 ... 600).map { Double($0) / 20 })
    ]

    @Test("the algorithm's rate survives the driver", arguments: tables) func survivesDriver(pump: String, table: [Double]) {
        for probe in Self.probes {
            let mine = algorithm(normalised(table), probe)
            #expect(driver(table, mine) == mine, "\(pump) floors \(mine) away at probe \(probe)")
        }
    }

    /// The algorithm works in U100 units and `adjustPumpedRateToConcentration` divides back out
    /// before delivery, so the scaled table has to divide back onto a rate the pump holds.
    @Test("a scaled rate divides back onto the table", arguments: tables) func survivesDilution(pump: String, table: [Double]) {
        for concentration in [Decimal(2), 5, 0.5, 0.1] {
            let scaled = normalised(table).map { $0 * concentration }

            for probe in Self.probes {
                let mine = algorithm(scaled, probe)
                let pumpVolume = mine / concentration
                #expect(
                    driver(table, pumpVolume) == pumpVolume,
                    "\(pump) at U\(concentration * 100) floors \(pumpVolume) away at probe \(probe)"
                )
            }
        }
    }

    @Test("every kit table is non-empty and normalises without collisions") func tablesNormaliseCleanly() {
        for (_, table) in Self.tables {
            let rates = normalised(table)
            #expect(!rates.isEmpty)
            // 3 dp must not merge two distinct rates into one
            #expect(Set(rates).count == Set(table).count)
        }
    }
}
