import Foundation

/// Resolves the bolus increment stored in preferences from what the pump can deliver and the
/// insulin concentration in use.
///
/// The increment is not a user setting: `BaseDeviceDataManager` overwrites it whenever a pump
/// manager is attached or cleared. It reaches dosing through `Profile.bolusIncrement`, which
/// `TempBasalFunctions.roundBasal` turns into the low-rate rounding scale.
enum BolusIncrementResolver {
    static let fallback: Decimal = 0.1

    /// - Parameters:
    ///   - supportedBolusVolumes: `PumpManager.supportedBolusVolumes`, smallest first.
    ///   - currentIncrement: kept when the pump reports no volumes and concentration is U100.
    static func resolve(
        supportedBolusVolumes: [Double],
        currentIncrement: Decimal,
        concentration: Decimal
    ) -> Decimal {
        let supportedPumpIncrement = Decimal(supportedBolusVolumes.first ?? 0.1)
        var bolusIncrement = Decimal(supportedBolusVolumes.first ?? Double(currentIncrement))

        if concentration != 1 {
            bolusIncrement = supportedPumpIncrement * concentration
        }

        return bolusIncrement > 0 ? bolusIncrement : fallback
    }

    /// No pump attached, so there is no reported increment to scale.
    static func resolveWithoutPump(concentration: Decimal) -> Decimal {
        concentration != 1 ? fallback * concentration : fallback
    }
}
