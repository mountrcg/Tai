import Foundation
import Testing
@testable import Trio

@Suite("Round Basal Tests") struct RoundBasalTests {
    private func profile(increment: Decimal) -> Profile {
        var profile = Profile()
        profile.bolusIncrement = increment
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

    // MARK: - Above 1 U/h the increment stops mattering

    @Test("Rates from 1 to 10 round to 0.05 regardless of increment") func midBandIgnoresIncrement() {
        for increment in [Decimal(0.1), 0.05, 0.025] {
            #expect(TempBasalFunctions.roundBasal(profile: profile(increment: increment), basalRate: 2.83) == 2.85)
        }
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
