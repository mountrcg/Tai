import Foundation
import Testing
@testable import Trio

@Suite("determineBasal SMB microbolus behavior") struct DetermineBasalSmbMicroBolusTests {
    private func buildInputs(lastBolusOffsetMinutes: Decimal) -> (
        profile: Profile,
        preferences: Preferences,
        currentTemp: TempBasal,
        iobData: [IobResult],
        mealData: ComputedCarbs,
        autosensData: Autosens,
        glucoseStatus: GlucoseStatus,
        trioCustomOrefVariables: TrioCustomOrefVariables,
        microBolusAllowed: Bool,
        currentTime: Date
    ) {
        let now = Date()

        var profile = Profile()
        profile.currentBasal = 1.0
        profile.maxDailyBasal = 1.5
        profile.maxBasal = 3.0
        profile.minBg = 90
        profile.maxBg = 160
        profile.targetBg = 100
        profile.sens = 40
        profile.carbRatio = 10
        profile.thresholdSetting = 70
        profile.maxIob = 6
        profile.enableSMBAlways = true
        profile.bolusIncrement = 0.1
        profile.enableSMBHighBg = true
        profile.enableSMBHighBgTarget = 140

        var preferences = Preferences()
        preferences.curve = .rapidActing
        preferences.useCustomPeakTime = false

        let currentTemp = TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: now)

        let lastBolusTime = UInt64(
            now
                .addingTimeInterval(TimeInterval(-60 * NSDecimalNumber(decimal: lastBolusOffsetMinutes).doubleValue))
                .timeIntervalSince1970 * 1000
        )
        let iobData = [IobResult(
            iob: 0.2,
            activity: 0,
            basaliob: 0.2,
            bolusiob: 0,
            netbasalinsulin: 0,
            bolusinsulin: 0,
            time: now,
            iobWithZeroTemp: IobResult.IobWithZeroTemp(
                iob: 0.2,
                activity: 0,
                basaliob: 0.2,
                bolusiob: 0,
                netbasalinsulin: 0,
                bolusinsulin: 0,
                time: now
            ),
            lastBolusTime: lastBolusTime,
            lastTemp: IobResult.LastTemp(
                rate: 0,
                timestamp: now,
                started_at: now,
                date: UInt64(now.timeIntervalSince1970 * 1000),
                duration: 30
            )
        )]

        let mealData = ComputedCarbs(
            carbs: 0,
            mealCOB: 0,
            currentDeviation: 0,
            maxDeviation: 0,
            minDeviation: 0,
            slopeFromMaxDeviation: 0,
            slopeFromMinDeviation: 0,
            allDeviations: [0, 0, 0, 0, 0],
            lastCarbTime: 0
        )

        let autosensData = Autosens(ratio: 1.0, newisf: nil)

        let glucoseStatus = GlucoseStatus(
            delta: 5,
            glucose: 190,
            noise: 1,
            shortAvgDelta: 5,
            longAvgDelta: 5,
            date: now,
            lastCalIndex: nil,
            device: "test"
        )

        let trioCustomOrefVariables = TrioCustomOrefVariables(
            average_total_data: 0,
            weightedAverage: 0,
            currentTDD: 0,
            past2hoursAverage: 0,
            date: now,
            overridePercentage: 100,
            useOverride: false,
            duration: 0,
            unlimited: false,
            overrideTarget: 0,
            smbIsOff: false,
            advancedSettings: false,
            isfAndCr: false,
            isf: false,
            cr: false,
            smbIsScheduledOff: false,
            start: 0,
            end: 0,
            smbMinutes: 30,
            uamMinutes: 30
        )

        return (
            profile: profile,
            preferences: preferences,
            currentTemp: currentTemp,
            iobData: iobData,
            mealData: mealData,
            autosensData: autosensData,
            glucoseStatus: glucoseStatus,
            trioCustomOrefVariables: trioCustomOrefVariables,
            microBolusAllowed: true,
            currentTime: now
        )
    }

    @Test("Applies SMB microbolus when interval has elapsed") func testMicrobolusWhenIntervalElapsed() throws {
        let inputs = buildInputs(lastBolusOffsetMinutes: 10)

        let determination = try DeterminationGenerator.determineBasal(
            profile: inputs.profile,
            preferences: inputs.preferences,
            units: .mgdL,
            currentTemp: inputs.currentTemp,
            iobData: inputs.iobData,
            mealData: inputs.mealData,
            autosensData: inputs.autosensData,
            glucoseStatus: inputs.glucoseStatus,
            microBolusAllowed: inputs.microBolusAllowed,
            autoISFStatus: nil,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables,
            currentTime: inputs.currentTime
        )

        #expect(determination?.units ?? 0 > 0)
        #expect(determination?.reason.contains("Microbolusing") ?? false)
    }

    @Test("Waits for SMB interval before another microbolus") func testWaitsForInterval() throws {
        let inputs = buildInputs(lastBolusOffsetMinutes: 1)

        let determination = try DeterminationGenerator.determineBasal(
            profile: inputs.profile,
            preferences: inputs.preferences,
            units: .mgdL,
            currentTemp: inputs.currentTemp,
            iobData: inputs.iobData,
            mealData: inputs.mealData,
            autosensData: inputs.autosensData,
            glucoseStatus: inputs.glucoseStatus,
            microBolusAllowed: inputs.microBolusAllowed,
            autoISFStatus: nil,
            trioCustomOrefVariables: inputs.trioCustomOrefVariables,
            currentTime: inputs.currentTime
        )

        #expect(determination?.units == nil || determination?.units == 0)
        #expect(determination?.reason.contains("Waiting") ?? false)
    }

    /// Regression test: `units:` threaded into `determineBasal` must reach the autoISF
    /// even/odd parity check. Same profile + same `targetBG` (92 mg/dL = 5.1 mmol/L)
    /// flips the SMB verdict purely on the units argument:
    ///   - .mgdL: 92 is even → SMB enforced, reason has no "odd Target"
    ///   - .mmolL: 5.1 has odd tenths digit → SMB blocked, reason contains "odd Target"
    /// If `units` is ever re-sourced from the profile (or anything not the parameter),
    /// both calls produce the same verdict and this test fails.
    @Test("autoISF even/odd parity follows the passed units, not the profile") func testParityFollowsUnitsParameter() throws {
        var inputs = buildInputs(lastBolusOffsetMinutes: 10)
        inputs.profile.autoisf = true
        inputs.profile.enableSMBEvenOnOddOffAlways = true
        inputs.profile.minBg = 92
        inputs.profile.targetBg = 92

        // autoISFStatus must be non-nil so AutoISF.run takes the full path that
        // bakes the SMB reason fragment into isfReason → determination.reason.
        let autoISFStatus = AutoISFGlucoseStatus(
            glucoseStatus: inputs.glucoseStatus,
            cgmFlatMinutes: 0,
            dura_ISF_minutes: 0,
            dura_ISF_average: 0,
            dura_p: 0,
            delta_pl: 0,
            delta_pn: 0,
            bg_acceleration: 0,
            r_squ: 0,
            a_0: 0,
            a_1: 0,
            a_2: 0,
            debugInfo: ""
        )

        func run(units: GlucoseUnits) throws -> Determination? {
            try DeterminationGenerator.determineBasal(
                profile: inputs.profile,
                preferences: inputs.preferences,
                units: units,
                currentTemp: inputs.currentTemp,
                iobData: inputs.iobData,
                mealData: inputs.mealData,
                autosensData: inputs.autosensData,
                glucoseStatus: inputs.glucoseStatus,
                microBolusAllowed: inputs.microBolusAllowed,
                autoISFStatus: autoISFStatus,
                trioCustomOrefVariables: inputs.trioCustomOrefVariables,
                currentTime: inputs.currentTime
            )
        }

        let mgdl = try run(units: .mgdL)
        let mmol = try run(units: .mmolL)

        #expect(!(mgdl?.reason.contains("odd Target") ?? true))
        #expect(mmol?.reason.contains("odd Target") ?? false)
    }
}
