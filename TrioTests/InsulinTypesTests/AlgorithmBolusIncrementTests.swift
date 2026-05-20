import Foundation
import Testing

@testable import Trio

/// Pin the iU-equivalent bolus-increment computation
/// (`PumpUnits.algorithmBolusIncrement`). The helper is the single source of
/// truth for the formula that lives at `DeviceDataManager.pumpManager.didSet`,
/// where the algorithm increment is recomputed on every pump attach. The
/// typed `PumpInsulin` argument enforces the pU domain at the call site;
/// these tests pin the math.
@Suite("PumpUnits.algorithmBolusIncrement") struct AlgorithmBolusIncrementTests {
    // MARK: - U100 (concentration == 1) — identity, no scaling

    @Test("U100: pump increment passes through unchanged") func u100PassesThrough() {
        #expect(PumpUnits.algorithmBolusIncrement(supportedPumpIncrement: PumpInsulin(pU: 0.05), concentration: 1) == 0.05)
        #expect(PumpUnits.algorithmBolusIncrement(supportedPumpIncrement: PumpInsulin(pU: 0.1), concentration: 1) == 0.1)
        #expect(PumpUnits.algorithmBolusIncrement(supportedPumpIncrement: PumpInsulin(pU: 0.5), concentration: 1) == 0.5)
    }

    // MARK: - U200 (concentration == 2) — doubles iU per pU step

    @Test("U200: Medtronic 0.05 pU increment becomes 0.1 iU") func u200MedtronicIncrement() {
        #expect(PumpUnits.algorithmBolusIncrement(supportedPumpIncrement: PumpInsulin(pU: 0.05), concentration: 2) == 0.1)
    }

    @Test("U200: Omnipod 0.05 pU increment becomes 0.1 iU") func u200OmnipodIncrement() {
        #expect(PumpUnits.algorithmBolusIncrement(supportedPumpIncrement: PumpInsulin(pU: 0.05), concentration: 2) == 0.1)
    }

    // MARK: - U500 / U50 / U10

    @Test("U500: 0.05 pU increment becomes 0.25 iU") func u500Increment() {
        #expect(PumpUnits.algorithmBolusIncrement(supportedPumpIncrement: PumpInsulin(pU: 0.05), concentration: 5) == 0.25)
    }

    @Test("U50: 0.05 pU increment becomes 0.025 iU") func u50Increment() {
        #expect(PumpUnits.algorithmBolusIncrement(supportedPumpIncrement: PumpInsulin(pU: 0.05), concentration: 0.5) == 0.025)
    }

    @Test("U10: 0.05 pU increment becomes 0.005 iU") func u10Increment() {
        #expect(PumpUnits.algorithmBolusIncrement(supportedPumpIncrement: PumpInsulin(pU: 0.05), concentration: 0.1) == 0.005)
    }

    // MARK: - 0.025 pU pumps are no longer specially filtered

    //
    // The pre-Phase-1 Tai code had `filteredSupportedIncrement = supportedPumpIncrement
    // != 0.025 ? supportedPumpIncrement : 0.1` and applied it only when scaling, so
    // a 0.025-pU pump at non-U100 ended up with an iU increment of 0.1 × concentration.
    // The `0.025` magic number actually came from `oref0/lib/round-basal.js`, where it
    // describes Medtronic x23/x54 *basal*-rate granularity at low rates — not a bolus
    // concept. Mis-applied to `supportedBolusVolumes.first` it had no defensible
    // meaning, so the filter was dropped. A 0.025-pU pump now scales linearly like
    // any other pump.

    @Test("0.025 pU pump scales linearly at U100") func pump025AtU100() {
        #expect(PumpUnits.algorithmBolusIncrement(supportedPumpIncrement: PumpInsulin(pU: 0.025), concentration: 1) == 0.025)
    }

    @Test("0.025 pU pump scales linearly at U200") func pump025AtU200() {
        #expect(PumpUnits.algorithmBolusIncrement(supportedPumpIncrement: PumpInsulin(pU: 0.025), concentration: 2) == 0.05)
    }

    // MARK: - Zero / negative defense

    @Test("Zero pump increment falls back to 0.1 iU") func zeroPumpIncrementFallback() {
        #expect(PumpUnits.algorithmBolusIncrement(supportedPumpIncrement: PumpInsulin(pU: 0), concentration: 1) == 0.1)
        #expect(PumpUnits.algorithmBolusIncrement(supportedPumpIncrement: PumpInsulin(pU: 0), concentration: 2) == 0.1)
    }
}
