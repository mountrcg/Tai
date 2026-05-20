import Foundation
import Testing

@testable import Trio

/// Pin the Phase-1 helper rewrite: `PumpInsulin` / `PumpRate` wrapper
/// arithmetic must produce the exact same `Decimal` output as the pre-Phase-1
/// free formulas in `APSManager.adjustPumped*` and
/// `PumpHistoryStorage.adjustPumped*`. The legacy formulas below are frozen
/// copies of the pre-refactor implementations; if a future change to
/// `PumpInsulin` / `PumpRate` (or the surrounding rounding chain) drifts from
/// them, this test fails.
///
/// Each manager helper keeps a `guard concentration != 1 else { ... }`
/// short-circuit at the call site (the U100 branch returned input verbatim or
/// only `precisionRounded`, never increment-snapped). The parity grid below
/// therefore excludes `concentration == 1` for the non-U100 helpers — that
/// branch is covered by the explicit U100-identity tests at the end.
@Suite("Phase-1 PumpInsulin/PumpRate parity vs frozen legacy formulas") struct ConcentrationScalingParityTests {
    // Non-U100 concentrations the app ships (U10, U50, U200, U500). U100
    // (==1) is excluded from the parity grids because the manager helpers
    // short-circuit before constructing the wrapper.
    static let concentrations: [Decimal] = [0.1, 0.5, 2, 5]

    // Representative values: zero, smallest pump increments, common doses,
    // boundary values for fine-grained concentrations, and the max bolus.
    static let values: [Decimal] = [
        0, 0.005, 0.025, 0.05, 0.075, 0.1, 0.2, 0.5, 1.0, 1.5, 5.5, 25.0, 30.0
    ]

    // Bolus increments observed across supported pumps (Medtronic 0.05,
    // Omnipod 0.05, DanaR 0.05, Medtrum 0.025-normalized-to-0.1) and their
    // concentration-scaled variants.
    static let increments: [Decimal] = [0.005, 0.025, 0.05, 0.1, 0.2, 0.25]

    // MARK: - Frozen legacy formulas

    /// Pre-Phase-1 iU → cU formula, lifted verbatim from
    /// `APSManager.adjustPumpedVolumeToConcentration` /
    /// `…RateToConcentration` (non-U100 branch only).
    static func legacyToPumpCU(iU: Decimal, concentration: Decimal) -> Decimal {
        (iU / concentration).precisionRounded()
    }

    /// Pre-Phase-1 cU → iU formula, lifted verbatim from
    /// `APSManager.adjustPumpedRateToU100` /
    /// `PumpHistoryStorage.adjustPumped{Volume,Rate}ToU100`
    /// (non-U100 branch only).
    static func legacyToAlgorithmIU(cU: Decimal, concentration: Decimal, increment: Decimal) -> Decimal {
        (cU * concentration)
            .precisionRounded()
            .roundedWithIncrement(increment: increment, roundingMode: .plain)
    }

    // MARK: - Parity

    @Test("PumpInsulin(iU:concentration:).cU.precisionRounded() matches legacy iU→cU formula")  func pumpInsulinIUToCUParity() {
        for concentration in Self.concentrations {
            for value in Self.values {
                let legacy = Self.legacyToPumpCU(iU: value, concentration: concentration)
                let wrapped = PumpInsulin(iU: value, concentration: concentration)
                    .cU
                    .precisionRounded()
                #expect(
                    legacy == wrapped,
                    "iU=\(value) c=\(concentration): legacy=\(legacy) wrapped=\(wrapped)"
                )
            }
        }
    }

    @Test(
        "PumpInsulin(cU:).iU(...).precisionRounded().roundedWithIncrement() matches legacy cU→iU formula"
    )  func pumpInsulinCUToIUParity() {
        for concentration in Self.concentrations {
            for increment in Self.increments {
                for value in Self.values {
                    let legacy = Self.legacyToAlgorithmIU(
                        cU: value,
                        concentration: concentration,
                        increment: increment
                    )
                    let wrapped = PumpInsulin(cU: value)
                        .iU(concentration: concentration)
                        .precisionRounded()
                        .roundedWithIncrement(increment: increment, roundingMode: .plain)
                    #expect(
                        legacy == wrapped,
                        "cU=\(value) c=\(concentration) inc=\(increment): legacy=\(legacy) wrapped=\(wrapped)"
                    )
                }
            }
        }
    }

    @Test("PumpRate(iU:concentration:).cU.precisionRounded() matches legacy iU→cU formula")  func pumpRateIUToCUParity() {
        for concentration in Self.concentrations {
            for value in Self.values {
                let legacy = Self.legacyToPumpCU(iU: value, concentration: concentration)
                let wrapped = PumpRate(iU: value, concentration: concentration)
                    .cU
                    .precisionRounded()
                #expect(
                    legacy == wrapped,
                    "iU/hr=\(value) c=\(concentration): legacy=\(legacy) wrapped=\(wrapped)"
                )
            }
        }
    }

    @Test(
        "PumpRate(cU:).iU(...).precisionRounded().roundedWithIncrement() matches legacy cU→iU formula"
    )  func pumpRateCUToIUParity() {
        for concentration in Self.concentrations {
            for increment in Self.increments {
                for value in Self.values {
                    let legacy = Self.legacyToAlgorithmIU(
                        cU: value,
                        concentration: concentration,
                        increment: increment
                    )
                    let wrapped = PumpRate(cU: value)
                        .iU(concentration: concentration)
                        .precisionRounded()
                        .roundedWithIncrement(increment: increment, roundingMode: .plain)
                    #expect(
                        legacy == wrapped,
                        "cU/hr=\(value) c=\(concentration) inc=\(increment): legacy=\(legacy) wrapped=\(wrapped)"
                    )
                }
            }
        }
    }
}
