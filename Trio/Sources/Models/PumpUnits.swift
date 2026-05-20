import Foundation

// MARK: - Pump-domain insulin & rate wrappers

//
// Trio uses `Decimal` in canonical U100 international units ("iU") as the
// default unit for insulin volume and basal rate everywhere — algorithm,
// storage, Nightscout/HealthKit upload, UI. The exception is the pump I/O
// boundary, where the motor pushes a volume in "pumped units" (pU) that
// depends on the user's `insulinConcentration` setting (U10 / U50 / U100 /
// U200 / U500). At U100 the two are numerically identical; at U200 a 1 iU
// dose is 0.5 pU; at U50 it is 2 pU; etc.
//
// `PumpInsulin` and `PumpRate` are typed labels for pU values so the
// compiler makes the pU↔iU conversion explicit at the boundary. iU stays
// as plain `Decimal` everywhere else — the wrappers exist only at the
// pump-driver edge.
//
// Usage:
//   // Going to the pump: wrap the divide-by-concentration in the iU init.
//   let pU = PumpInsulin(iU: amount, concentration: c).pU
//   try await pump.enactBolus(units: pU.doubleValue, ...)
//
//   // Coming back from the pump: wrap the raw pump value, then ask for iU.
//   let storedIU = PumpInsulin(pU: dose.unitsInDeliverableIncrements)
//                      .iU(concentration: c)

/// Insulin amount in pumped units (pU) — what the pump motor actually pushes.
/// Only valid at the pump I/O boundary. Cross to algorithm-canonical iU via
/// `.iU(concentration:)`.
struct PumpInsulin: Hashable, Comparable, Codable {
    let pU: Decimal

    init(pU: Decimal) { self.pU = pU }

    /// Convenience: construct from an algorithm-side iU value via
    /// `pU = iU / concentration`. The wrapper "labels" the result as a
    /// pump-domain value; rounding (precision, increment) is the caller's job.
    init(iU: Decimal, concentration: Decimal) {
        pU = iU / concentration
    }

    /// Bridge to LoopKit pump APIs that take `Double`
    /// (e.g. `PumpManager.enactBolus(units:)`).
    var doubleValue: Double { Double(truncating: pU as NSDecimalNumber) }

    /// Convert back to algorithm-canonical iU.
    /// At U100 (`concentration == 1`) the returned iU equals `pU`.
    func iU(concentration: Decimal) -> Decimal { pU * concentration }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.pU < rhs.pU }
}

/// Basal delivery rate in pumped units per hour (pU/hr).
/// Only valid at the pump I/O boundary. Cross to algorithm-canonical iU/hr
/// via `.iU(concentration:)`.
///
/// Currently no Trio pump driver uses percentage basal rates, so this wrapper
/// assumes absolute pU/hr — symmetric with `PumpInsulin`. A future driver
/// that reports relative basal could add an `isAbsolute: Bool` parameter to
/// `iU(concentration:)` to skip the concentration multiplication.
struct PumpRate: Hashable, Comparable, Codable {
    let pU: Decimal

    init(pU: Decimal) { self.pU = pU }

    init(iU: Decimal, concentration: Decimal) {
        pU = iU / concentration
    }

    var doubleValue: Double { Double(truncating: pU as NSDecimalNumber) }

    func iU(concentration: Decimal) -> Decimal { pU * concentration }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.pU < rhs.pU }
}

// MARK: - Increment helper

/// Increment helper shared between `DeviceDataManager` and tests.
enum PumpUnits {
    /// Compute the iU-equivalent of the pump's smallest deliverable pU increment.
    ///
    /// Mirrors the formula at `DeviceDataManager.pumpManager.didSet`: the algorithm
    /// rounds its proposed doses to this iU value so that after dividing by
    /// concentration at the pump boundary, the result lands exactly on a pump
    /// increment.
    ///
    /// - Parameters:
    ///   - supportedPumpIncrement: The pump's smallest `supportedBolusVolumes` entry, in pU.
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
