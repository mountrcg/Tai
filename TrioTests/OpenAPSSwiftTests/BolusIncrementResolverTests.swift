import Foundation
import Testing
@testable import Trio

@Suite("Bolus Increment Resolver Tests") struct BolusIncrementResolverTests {
    /// Leading entries of each kit's `supportedBolusVolumes`; only the first reaches the resolver.
    private enum Pump {
        /// OmnipodKit, DanaKit and MedtrumKit all publish `(1 ... 600).map { $0 / 20 }`
        static let omnipod = [0.05, 0.1, 0.15]
        static let dana = omnipod
        static let medtrum = omnipod
        /// MinimedKit, generation >= 23: scale 40 below 1 U
        static let medtronicX23 = [0.025, 0.05, 0.075]
        /// MinimedKit, older generations: tenths only
        static let medtronicOlder = [0.1, 0.2, 0.3]
    }

    /// Decimal float literals are parsed as Double first, and 0.57 is not exact there.
    private func dec(_ value: String) -> Decimal { Decimal(string: value)! }

    private func resolve(_ volumes: [Double], concentration: Decimal, current: Decimal = 0.05) -> Decimal {
        BolusIncrementResolver.resolve(
            supportedBolusVolumes: volumes,
            currentIncrement: current,
            concentration: concentration
        )
    }

    // MARK: - U100, where the pump decides alone

    @Test("At U100 the pump's smallest volume is taken as-is") func u100TakesPumpIncrement() {
        #expect(resolve([0.05, 0.1], concentration: 1) == 0.05)
        #expect(resolve([0.1, 0.2], concentration: 1) == 0.1)
        #expect(resolve([0.025, 0.05], concentration: 1) == 0.025)
    }

    @Test("A pump reporting no volumes keeps the increment already stored") func noVolumesKeepsCurrent() {
        #expect(resolve([], concentration: 1, current: 0.05) == 0.05)
        #expect(resolve([], concentration: 1, current: 0.025) == 0.025)
    }

    @Test("A pump reporting zero falls back rather than storing zero") func zeroFallsBack() {
        // a zero increment would make roundBasal divide by zero territory
        #expect(resolve([0], concentration: 1) == 0.1)
    }

    // MARK: - Concentration scales the increment

    @Test("U200 doubles the pump increment, U50 halves it") func concentrationScales() {
        #expect(resolve([0.05], concentration: 2) == 0.1)
        #expect(resolve([0.1], concentration: 2) == 0.2)
        #expect(resolve([0.05], concentration: 0.5) == 0.025)
    }

    @Test("A 0.025 pump scales from its own increment") func medtronicScalesFromOwnIncrement() {
        #expect(resolve([0.025], concentration: 2) == 0.05)
        #expect(resolve([0.025], concentration: 0.5) == dec("0.0125"))
    }

    @Test("Without reported volumes concentration scales the fallback") func noVolumesScalesFallback() {
        #expect(resolve([], concentration: 2, current: 0.05) == 0.2)
    }

    // MARK: - The pumps Tai ships with, at every concentration the picker offers

    @Test("Every shipped pump resolves at every offered concentration") func pumpsAcrossConcentrations() {
        // U200, U100, U50, U10 - the four tags in InsulinConcentrationRootView's picker
        #expect(resolve(Pump.omnipod, concentration: 2) == 0.1)
        #expect(resolve(Pump.omnipod, concentration: 1) == 0.05)
        #expect(resolve(Pump.omnipod, concentration: 0.5) == 0.025)
        #expect(resolve(Pump.omnipod, concentration: 0.1) == 0.005)

        // Dana and Medtrum publish the same volumes, so they track Omnipod exactly
        #expect(resolve(Pump.dana, concentration: 0.1) == resolve(Pump.omnipod, concentration: 0.1))
        #expect(resolve(Pump.medtrum, concentration: 0.1) == resolve(Pump.omnipod, concentration: 0.1))

        #expect(resolve(Pump.medtronicOlder, concentration: 2) == 0.2)
        #expect(resolve(Pump.medtronicOlder, concentration: 1) == 0.1)
        #expect(resolve(Pump.medtronicOlder, concentration: 0.5) == 0.05)
        #expect(resolve(Pump.medtronicOlder, concentration: 0.1) == 0.01)
    }

    @Test("A 0.025 Medtronic keeps its own increment at every concentration") func medtronicX23AcrossConcentrations() {
        #expect(resolve(Pump.medtronicX23, concentration: 1) == 0.025)
        #expect(resolve(Pump.medtronicX23, concentration: 2) == 0.05)
        #expect(resolve(Pump.medtronicX23, concentration: 0.5) == dec("0.0125"))
        #expect(resolve(Pump.medtronicX23, concentration: 0.1) == dec("0.0025"))
    }

    // MARK: - No pump attached

    @Test("With no pump the increment is the fallback, scaled by concentration") func withoutPump() {
        #expect(BolusIncrementResolver.resolveWithoutPump(concentration: 1) == 0.1)
        #expect(BolusIncrementResolver.resolveWithoutPump(concentration: 2) == 0.2)
        #expect(BolusIncrementResolver.resolveWithoutPump(concentration: 0.5) == 0.05)
    }

    // MARK: - Every resolved increment has to be renderable

    @Test("Each pump at each concentration resolves to an increment the formatter can show exactly")
    func resolvedIncrementsAreRenderable() {
        for volumes in [Pump.omnipod, Pump.dana, Pump.medtrum, Pump.medtronicX23, Pump.medtronicOlder] {
            for concentration in [Decimal(2), 1, 0.5, 0.1] {
                let increment = resolve(volumes, concentration: concentration)
                let digits = Decimal.maxFractionDigits(for: increment)
                let scaled = increment * pow(10, digits)

                #expect(
                    scaled == scaled.rounded(scale: 0, roundingMode: .down),
                    "\(increment) needs more than \(digits) digits"
                )
            }
        }
    }

    // MARK: - What dosing does with the result

    @Test("The resolved increment is the scale roundBasal rounds a low rate onto") func feedsRoundBasal() {
        var profile = Profile()
        profile.model = "722"

        profile.bolusIncrement = resolve([0.05], concentration: 1)
        #expect(TempBasalFunctions.roundBasal(profile: profile, basalRate: 0.57) == 0.55)

        // the same pump on U200 delivers in 0.1 steps, so the rate lands elsewhere
        profile.bolusIncrement = resolve([0.05], concentration: 2)
        #expect(TempBasalFunctions.roundBasal(profile: profile, basalRate: 0.57) == 0.6)

        // U10 buys 0.005 steps, fine enough that a low rate survives rounding intact
        profile.bolusIncrement = resolve(Pump.omnipod, concentration: 0.1)
        #expect(profile.bolusIncrement == 0.005)
        #expect(TempBasalFunctions.roundBasal(profile: profile, basalRate: dec("0.57")) == dec("0.57"))
    }

    @Test("A Medtronic x54 keeps the granularity dilution earned it") func medtronicDilutionReachesBasal() {
        var profile = Profile()
        profile.model = "554"
        profile.bolusIncrement = resolve(Pump.medtronicX23, concentration: 0.1)

        // 0.0025 U100-units is one 0.025 pump step at U10
        #expect(profile.bolusIncrement == dec("0.0025"))
        #expect(TempBasalFunctions.roundBasal(profile: profile, basalRate: dec("0.57")) == dec("0.57"))
    }
}
