import Foundation

// MARK: - Pump-domain insulin & rate wrappers (asymmetric AAPS-style)

//
// Trio treats `Decimal` (canonical U100 international units, "iU") as the
// default unit for insulin volume and basal rate everywhere — algorithm,
// storage, Nightscout/HealthKit upload, UI. The exception is the pump I/O
// boundary, where the motor pushes cartridge volume ("cU") that depends on
// the user's insulin concentration setting (U10 / U50 / U100 / U200 / U500).
//
// `PumpInsulin` and `PumpRate` are typed labels for cU values so the compiler
// makes the cU↔iU conversion explicit at the boundary. There is no matching
// `AlgorithmInsulin` — iU stays as plain `Decimal`. This mirrors AAPS's
// `core.interfaces.pump.PumpInsulin` / `PumpRate` (see PR
// https://github.com/nightscout/AndroidAPS/pull/4441).
//
// Usage:
//   // Going to the pump: wrap the divide-by-concentration in the iU init.
//   let cU = PumpInsulin(iU: amount, concentration: c).cU
//   try await pump.enactBolus(units: cU.doubleValue, ...)
//
//   // Coming back from the pump: wrap the raw pump value, then ask for iU.
//   let storedIU = PumpInsulin(cU: dose.unitsInDeliverableIncrements)
//                      .iU(concentration: c)

/// Insulin amount in pump-cartridge volume (cU) — the liquid the motor pushes.
/// Only valid at the pump I/O boundary. Cross to algorithm-canonical iU via
/// `.iU(concentration:)`.
struct PumpInsulin: Hashable, Comparable, Codable {
    let cU: Decimal

    init(cU: Decimal) { self.cU = cU }

    /// Convenience: construct from an algorithm-side iU value via
    /// `cU = iU / concentration`. The wrapper "labels" the result as a
    /// pump-domain value; rounding (precision, increment) is the caller's job.
    init(iU: Decimal, concentration: Decimal) {
        cU = iU / concentration
    }

    /// Bridge to LoopKit pump APIs that take `Double`
    /// (e.g. `PumpManager.enactBolus(units:)`).
    var doubleValue: Double { Double(truncating: cU as NSDecimalNumber) }

    /// Convert back to algorithm-canonical iU.
    /// At U100 (`concentration == 1`) the returned iU equals `cU`.
    func iU(concentration: Decimal) -> Decimal { cU * concentration }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.cU < rhs.cU }
}

/// Basal delivery rate in pump-cartridge volume per hour (cU/hr).
/// Only valid at the pump I/O boundary. Cross to algorithm-canonical iU/hr
/// via `.iU(concentration:)`.
///
/// Currently no Trio pump driver uses percentage basal rates, so this wrapper
/// assumes absolute cU/hr — symmetric with `PumpInsulin`. AAPS adds an
/// `isAbsolute: Boolean` param for pumps that report relative basal; we can
/// add that here if a future driver needs it.
struct PumpRate: Hashable, Comparable, Codable {
    let cU: Decimal

    init(cU: Decimal) { self.cU = cU }

    init(iU: Decimal, concentration: Decimal) {
        cU = iU / concentration
    }

    var doubleValue: Double { Double(truncating: cU as NSDecimalNumber) }

    func iU(concentration: Decimal) -> Decimal { cU * concentration }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.cU < rhs.cU }
}

// MARK: - Increment helper

/// Increment helper shared between `DeviceDataManager` and tests.
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
