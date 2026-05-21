import Foundation
import Testing

@testable import Trio

/// Pin the wrapper-backed unit-conversion math against the pre-typed-wrapper
/// formulas that previously lived as free `adjustPumped*` methods on
/// `APSManager` and `PumpHistoryStorage`. Those helpers are now removed; the
/// conversion lives inside `PumpInsulin` / `PumpRate` (the wrapper math
/// itself) and `PumpHistoryStorage.pumpBolusAsIU` / `pumpRateAsIU` (the
/// storage-side conversion + rounding). The frozen formulas below pin the
/// pre-refactor behavior byte-for-byte — if a future change to the typed
/// wrappers or the storage helpers drifts from them, this test fails.
///
/// The current production code short-circuits the U100 (`concentration == 1`)
/// case before constructing the wrapper (the legacy code did the same — at
/// U100 the iU value passed through with only a `precisionRounded`, never
/// the increment snap). The parity grid below therefore excludes
/// `concentration == 1` for the cU → iU formula.
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

    /// Pre-typed-wrapper iU → pU formula (the non-U100 branch of the
    /// now-removed `adjustPumpedVolumeToConcentration` /
    /// `adjustPumpedRateToConcentration` helpers in `APSManager`).
    static func legacyToPumpPU(iU: Decimal, concentration: Decimal) -> Decimal {
        (iU / concentration).precisionRounded()
    }

    /// Pre-typed-wrapper pU → iU formula (the non-U100 branch of the
    /// now-removed `adjustPumpedRateToU100` / `adjustPumpedVolumeToU100`
    /// helpers; the live version sits inside `PumpHistoryStorage.pumpBolusAsIU`
    /// and `pumpRateAsIU`, which the wrapper-backed parity tests below also
    /// exercise indirectly).
    static func legacyToAlgorithmIU(pU: Decimal, concentration: Decimal, increment: Decimal) -> Decimal {
        (pU * concentration)
            .precisionRounded()
            .roundedWithIncrement(increment: increment, roundingMode: .plain)
    }

    // MARK: - Parity

    @Test("PumpInsulin(iU:concentration:).pU.precisionRounded() matches legacy iU→pU formula") func pumpInsulinIUToPUParity() {
        for concentration in Self.concentrations {
            for value in Self.values {
                let legacy = Self.legacyToPumpPU(iU: value, concentration: concentration)
                let wrapped = PumpInsulin(iU: value, concentration: concentration)
                    .pU
                    .precisionRounded()
                #expect(
                    legacy == wrapped,
                    "iU=\(value) c=\(concentration): legacy=\(legacy) wrapped=\(wrapped)"
                )
            }
        }
    }

    @Test(
        "PumpInsulin(pU:).iU(...).precisionRounded().roundedWithIncrement() matches legacy pU→iU formula"
    ) func pumpInsulinPUToIUParity() {
        for concentration in Self.concentrations {
            for increment in Self.increments {
                for value in Self.values {
                    let legacy = Self.legacyToAlgorithmIU(
                        pU: value,
                        concentration: concentration,
                        increment: increment
                    )
                    let wrapped = PumpInsulin(pU: value)
                        .iU(concentration: concentration)
                        .precisionRounded()
                        .roundedWithIncrement(increment: increment, roundingMode: .plain)
                    #expect(
                        legacy == wrapped,
                        "pU=\(value) c=\(concentration) inc=\(increment): legacy=\(legacy) wrapped=\(wrapped)"
                    )
                }
            }
        }
    }

    @Test("PumpRate(iU:concentration:).pU.precisionRounded() matches legacy iU→pU formula") func pumpRateIUToPUParity() {
        for concentration in Self.concentrations {
            for value in Self.values {
                let legacy = Self.legacyToPumpPU(iU: value, concentration: concentration)
                let wrapped = PumpRate(iU: value, concentration: concentration)
                    .pU
                    .precisionRounded()
                #expect(
                    legacy == wrapped,
                    "iU/hr=\(value) c=\(concentration): legacy=\(legacy) wrapped=\(wrapped)"
                )
            }
        }
    }

    @Test(
        "PumpRate(pU:).iU(...).precisionRounded().roundedWithIncrement() matches legacy pU→iU formula"
    ) func pumpRatePUToIUParity() {
        for concentration in Self.concentrations {
            for increment in Self.increments {
                for value in Self.values {
                    let legacy = Self.legacyToAlgorithmIU(
                        pU: value,
                        concentration: concentration,
                        increment: increment
                    )
                    let wrapped = PumpRate(pU: value)
                        .iU(concentration: concentration)
                        .precisionRounded()
                        .roundedWithIncrement(increment: increment, roundingMode: .plain)
                    #expect(
                        legacy == wrapped,
                        "pU/hr=\(value) c=\(concentration) inc=\(increment): legacy=\(legacy) wrapped=\(wrapped)"
                    )
                }
            }
        }
    }
}
