import Foundation
import MedtrumKit
import Testing

@testable import Trio

/// Pins `TempBasalFunctions.roundBasal` against the real pump kits' own rate tables. The
/// algorithm rounds to nearest while drivers floor, so the guarantee is that every rate the
/// algorithm commits to survives the driver unchanged. `RoundBasalTests` covers the same table
/// shapes arithmetically for the algorithm-only SPM target, which cannot import the kits.
@Suite("Basal Rounding Driver Parity") struct BasalRoundingDriverParityTests {
    /// Mirrors `APSManager.supportedBasalRates`: the 3 dp normalisation is what keeps a
    /// `Double(n) / 20` table entry from landing just above the clean rate it represents.
    private func normalised(_ rates: [Double]) -> [Decimal] {
        rates.map { Decimal($0).rounded(scale: 3) }
    }

    private func driver(_ table: [Double], _ unitsPerHour: Decimal) -> Decimal {
        let requested = Double(truncating: unitsPerHour as NSNumber).deliverable
        return Decimal(table.last(where: { $0 <= requested }) ?? 0).rounded(scale: 3)
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
        ("Medtrum", MedtrumPumpManager.onboardingSupportedBasalRates),
        // Pod's table is a local inside OmnipodKit's BasalDeliveryTable, so replicate Eros here
        ("Omnipod Eros", (1 ... 600).map { Double($0) / 20 })
    ]

    @Test("the algorithm's rate survives the driver", arguments: tables) func survivesDriver(pump: String, table: [Double]) {
        for probe in Self.probes {
            let mine = algorithm(normalised(table), probe)
            #expect(driver(table, mine) == mine, "\(pump) floors \(mine) away at probe \(probe)")
        }

        for rate in normalised(table) {
            #expect(driver(table, rate) == rate, "\(pump) floors \(rate) away")
        }
    }

    @Test("a scaled rate divides back onto the table", arguments: tables) func survivesDilution(pump: String, table: [Double]) {
        for concentration in [Decimal(2), 5, 0.5, 0.1] {
            let scaled = normalised(table).map { $0 * concentration }
            for probe in Self.probes {
                let pumpVolume = algorithm(scaled, probe) / concentration
                #expect(driver(table, pumpVolume) == pumpVolume, "\(pump) at U\(concentration * 100) loses \(pumpVolume)")
            }
        }
    }

    /// The rate `APSManager.performBasal` hands over must be the *same* `Double` the driver's own
    /// table holds. `Double(truncating:)` lands below on 41 of Dana's 301 rates (0.07 becomes
    /// 0.06999999999999999), and since every table floors, that silently costs a full increment.
    @Test(
        "the rate handed to the driver survives the Decimal to Double hop",
        arguments: tables
    ) func handedOverRateSurvivesConversion(pump: String, table: [Double]) {
        for entry in table {
            // what roundBasal returns: the injected table entry, an exact 3 dp Decimal
            let algorithmRate = Decimal(entry).rounded(scale: 3)
            // what performBasal sends
            let handedOver = algorithmRate.nearestDouble

            #expect(handedOver == entry, "\(pump): \(algorithmRate) converted to \(handedOver), table holds \(entry)")
            #expect(
                (table.last { $0 <= handedOver } ?? 0) == entry,
                "\(pump): the driver would floor \(handedOver) below \(entry)"
            )
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
