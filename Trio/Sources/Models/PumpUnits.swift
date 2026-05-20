import Foundation

// MARK: - Insulin volume

/// Insulin amount in the algorithm's canonical U100 international units (iU).
///
/// All IOB, COB, dosing computation, history storage, Nightscout/HealthKit upload,
/// and UI display happen in this space. Never pass to a `LoopKit.PumpManager` API —
/// convert via `.cU(concentration:)` first so the compiler enforces the conversion.
struct AlgorithmInsulin: Hashable, Comparable, Codable {
    let iU: Decimal

    init(iU: Decimal) { self.iU = iU }

    /// Convert to pump-cartridge volume (cU) given the active insulin concentration.
    /// At U100 (`concentration == 1`) the cU value equals the iU value.
    func cU(concentration: Decimal) -> PumpInsulin {
        PumpInsulin(cU: iU / concentration)
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.iU < rhs.iU }
    static func + (lhs: Self, rhs: Self) -> Self { .init(iU: lhs.iU + rhs.iU) }
    static func - (lhs: Self, rhs: Self) -> Self { .init(iU: lhs.iU - rhs.iU) }
}

/// Insulin amount in pump-cartridge volume (cU) — the actual liquid the motor pushes.
///
/// Only valid at the pump I/O boundary. Never store, display, or compute IOB
/// in this space; convert back to `AlgorithmInsulin` via `.iU(concentration:)` first.
struct PumpInsulin: Hashable, Comparable, Codable {
    let cU: Decimal

    init(cU: Decimal) { self.cU = cU }

    /// Bridge for LoopKit pump APIs that accept `Double` (e.g. `PumpManager.enactBolus(units:)`).
    /// LoopKit `DoseEntry` exposes `Double` values; convert at the call site via
    /// `PumpInsulin(cU: Decimal(dose.unitsInDeliverableIncrements))` to keep the
    /// Double↔Decimal boundary explicit.
    var doubleValue: Double { Double(truncating: cU as NSDecimalNumber) }

    /// Convert back to algorithm canonical units (iU) given the active insulin concentration.
    /// At U100 (`concentration == 1`) the iU value equals the cU value.
    func iU(concentration: Decimal) -> AlgorithmInsulin {
        AlgorithmInsulin(iU: cU * concentration)
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.cU < rhs.cU }
}

// MARK: - Basal rate

/// Basal delivery rate in algorithm canonical U/hr (U100 iU per hour).
struct AlgorithmBasalRate: Hashable, Comparable, Codable {
    let iU: Decimal

    init(iU: Decimal) { self.iU = iU }

    func cU(concentration: Decimal) -> PumpBasalRate {
        PumpBasalRate(cU: iU / concentration)
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.iU < rhs.iU }
    static func + (lhs: Self, rhs: Self) -> Self { .init(iU: lhs.iU + rhs.iU) }
    static func - (lhs: Self, rhs: Self) -> Self { .init(iU: lhs.iU - rhs.iU) }
}

/// Basal delivery rate in pump-cartridge volume per hour (cU/hr).
struct PumpBasalRate: Hashable, Comparable, Codable {
    let cU: Decimal

    init(cU: Decimal) { self.cU = cU }

    var doubleValue: Double { Double(truncating: cU as NSDecimalNumber) }

    func iU(concentration: Decimal) -> AlgorithmBasalRate {
        AlgorithmBasalRate(iU: cU * concentration)
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.cU < rhs.cU }
}

// MARK: - Increment helper

/// Increment helpers shared between `DeviceDataManager` and tests.
enum PumpUnits {
    /// Compute the iU-equivalent of the pump's smallest deliverable cU increment.
    ///
    /// Mirrors the formula at `DeviceDataManager.pumpManager.didSet`: the algorithm
    /// rounds its proposed doses to this iU value so that after dividing by
    /// concentration at the pump boundary, the result lands exactly on a pump
    /// increment.
    ///
    /// - Parameters:
    ///   - supportedPumpIncrement: The pump's smallest `supportedBolusVolumes` entry, in cU.
    ///     Pumps reporting `0.025` are normalized to `0.1` for safety.
    ///   - concentration: The user's `insulinConcentration` setting (U100 = 1, U200 = 2, …).
    /// - Returns: The iU increment the algorithm should round to. Never zero.
    static func algorithmBolusIncrement(
        supportedPumpIncrement: Decimal,
        concentration: Decimal
    ) -> Decimal {
        let filtered: Decimal = supportedPumpIncrement != 0.025 ? supportedPumpIncrement : 0.1
        let scaled = concentration != 1 ? filtered * concentration : filtered
        return scaled > 0 ? scaled : 0.1
    }
}
