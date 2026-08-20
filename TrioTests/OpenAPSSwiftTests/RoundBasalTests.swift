import Foundation
import Testing
@testable import Trio

@Suite("Round Basal Tests") struct RoundBasalTests {
    private func profile(increment: Decimal, model: String? = "722") -> Profile {
        var profile = Profile()
        profile.bolusIncrement = increment
        profile.model = model
        return profile
    }

    // MARK: - Rates below 1 U/h follow the pump increment

    @Test("A rate below 1 rounds onto the pump's own increment") func lowRateFollowsIncrement() {
        #expect(TempBasalFunctions.roundBasal(profile: profile(increment: 0.1), basalRate: 0.57) == 0.6)
        #expect(TempBasalFunctions.roundBasal(profile: profile(increment: 0.05), basalRate: 0.57) == 0.55)
        #expect(TempBasalFunctions.roundBasal(profile: profile(increment: 0.025), basalRate: 0.57) == 0.575)
    }

    @Test("Halves round up, as Math.round does") func halvesRoundUp() {
        #expect(TempBasalFunctions.roundBasal(profile: profile(increment: 0.1), basalRate: 0.55) == 0.6)
        #expect(TempBasalFunctions.roundBasal(profile: profile(increment: 0.05), basalRate: 0.575) == 0.6)
    }

    @Test("A non-positive increment falls back to 0.05 steps") func nonPositiveIncrementFallsBack() {
        #expect(TempBasalFunctions.roundBasal(profile: profile(increment: 0), basalRate: 0.57) == 0.55)
    }

    // MARK: - The model no longer overrides the increment

    @Test("Medtronic x23 and x54 follow the increment like any other pump") func medtronicFollowsIncrement() {
        for model in ["554", "523", "722554", "515523", "722", nil] {
            #expect(TempBasalFunctions.roundBasal(profile: profile(increment: 0.1, model: model), basalRate: 0.57) == 0.6)
            #expect(TempBasalFunctions.roundBasal(profile: profile(increment: 0.025, model: model), basalRate: 0.57) == 0.575)
        }
    }

    @Test("An x23 at U100 rounds exactly as the removed override did") func medtronicAtU100Unchanged() {
        // its resolved increment is 0.025, so 1/increment is the 40 the override forced
        let x23 = profile(increment: 0.025, model: "554")
        #expect(TempBasalFunctions.roundBasal(profile: x23, basalRate: 0.57) == 0.575)
        #expect(TempBasalFunctions.roundBasal(profile: x23, basalRate: 0.38) == 0.375)
    }

    // MARK: - Above 1 U/h the increment stops mattering

    @Test("Rates from 1 to 10 round to 0.05 regardless of increment") func midBandIgnoresIncrement() {
        for increment in [Decimal(0.1), 0.05, 0.025] {
            #expect(TempBasalFunctions.roundBasal(profile: profile(increment: increment), basalRate: 2.83) == 2.85)
        }
        #expect(TempBasalFunctions.roundBasal(profile: profile(increment: 0.1, model: "554"), basalRate: 2.83) == 2.85)
    }

    @Test("Rates of 10 and above round to 0.1 regardless of increment") func highBandIgnoresIncrement() {
        for increment in [Decimal(0.1), 0.05, 0.025] {
            #expect(TempBasalFunctions.roundBasal(profile: profile(increment: increment), basalRate: 12.34) == 12.3)
        }
    }

    @Test("Band edges take the band they belong to") func bandEdges() {
        // 0.99 is still the increment band, 1 is not
        #expect(TempBasalFunctions.roundBasal(profile: profile(increment: 0.025), basalRate: 0.99) == 1)
        #expect(TempBasalFunctions.roundBasal(profile: profile(increment: 0.025), basalRate: 1.01) == 1)
        #expect(TempBasalFunctions.roundBasal(profile: profile(increment: 0.025), basalRate: 9.99) == 10)
        #expect(TempBasalFunctions.roundBasal(profile: profile(increment: 0.025), basalRate: 10.04) == 10)
    }

    @Test("Zero stays zero") func zeroStaysZero() {
        #expect(TempBasalFunctions.roundBasal(profile: profile(increment: 0.05), basalRate: 0) == 0)
    }
}
