import Foundation
@testable import Trio
import XCTest

final class Sub5MinutePartATests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func readings(count: Int, spacing: TimeInterval = 60) -> [BloodGlucose] {
        (0 ..< count).map { index in
            let date = now.addingTimeInterval(-Double(index) * spacing)
            return BloodGlucose(sgv: 180 - index, date: Decimal(date.timeIntervalSince1970 * 1000), dateString: date)
        }
    }

    func testCadenceRequiresConsentTrustAndFiveIntervals() {
        let dense = readings(count: 6)
        XCTAssertEqual(GlucoseCadence.detect(dense, trusted: true, enabled: true, now: now), .dense(medianSpacing: 60))
        XCTAssertEqual(GlucoseCadence.detect(dense, trusted: false, enabled: true, now: now), .legacy)
        XCTAssertEqual(GlucoseCadence.detect(dense, trusted: true, enabled: false, now: now), .legacy)
        XCTAssertEqual(GlucoseCadence.detect(Array(dense.prefix(5)), trusted: true, enabled: true, now: now), .legacy)
        XCTAssertEqual(GlucoseCadence.detect(readings(count: 10, spacing: 300), trusted: true, enabled: true, now: now), .legacy)
        XCTAssertTrue(GlucoseCadence.detect(readings(count: 6, spacing: 210), trusted: true, enabled: true, now: now).isDense)
        XCTAssertFalse(GlucoseCadence.detect(readings(count: 6, spacing: 211), trusted: true, enabled: true, now: now).isDense)
    }

    func testGapDuplicatesManualAndFutureCannotQualify() {
        let samples = readings(count: 8)
        XCTAssertEqual(
            GlucoseCadence.detect(Array(repeating: samples[0], count: 8), trusted: true, enabled: true, now: now),
            .legacy
        )
        var manual = samples
        for index in manual.indices { manual[index].mbg = 120 }
        XCTAssertEqual(GlucoseCadence.detect(manual, trusted: true, enabled: true, now: now), .legacy)
        XCTAssertEqual(GlucoseCadence.detect(samples, trusted: true, enabled: true, now: now.addingTimeInterval(-600)), .legacy)
        XCTAssertEqual(
            GlucoseCadence.detect([samples[0]] + readings(count: 10).dropFirst(8), trusted: true, enabled: true, now: now),
            .legacy
        )
        XCTAssertEqual(GlucoseCadence.detect(samples, trusted: true, enabled: true, now: now.addingTimeInterval(421)), .legacy)
    }

    func testSingletonCandidatesRetainStartupAndResetEpoch() {
        var candidates = GlucoseCadenceCandidates()
        let epoch = UUID()
        for reading in readings(count: 6).reversed() {
            candidates.append([reading], epochID: epoch, now: reading.dateString)
        }
        XCTAssertEqual(candidates.readings.count, 6)
        XCTAssertTrue(GlucoseCadence.detect(candidates.readings, trusted: true, enabled: true, now: now).isDense)
        candidates.append([readings(count: 1)[0]], epochID: UUID(), now: now)
        XCTAssertEqual(candidates.readings.count, 1)
        candidates.append(readings(count: 200), epochID: epoch, now: now)
        XCTAssertLessThanOrEqual(candidates.readings.count, 64)
    }

    func testAutomaticMinimumAndValidatedOverrides() {
        XCTAssertEqual(GlucoseCadence.dense(medianSpacing: 89).parabolaMinimum(override: nil), 10)
        XCTAssertEqual(GlucoseCadence.dense(medianSpacing: 90).parabolaMinimum(override: nil), 15)
        for value: Decimal in [5, 20] {
            XCTAssertEqual(GlucoseCadence.dense(medianSpacing: 60).parabolaMinimum(override: value), value)
        }
        for value: Decimal in [0, 21, 5.5, .nan] {
            XCTAssertEqual(GlucoseCadence.dense(medianSpacing: 60).parabolaMinimum(override: value), 10)
        }
    }

    func testOldPreferencesAndJSONKeys() throws {
        let decoder = JSONDecoder()
        let old = try decoder.decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertFalse(old.enableSub5MinuteGlucose)
        XCTAssertFalse(old.autoISFParabolaSmoothed)
        XCTAssertNil(old.autoISFParabolaMinMinutes)
        XCTAssertEqual(old.sub5MinuteLoopInterval, 5)
        let imported = try decoder.decode(Preferences.self, from: Data(
            #"{"enable_sub5_minute_glucose":true,"autoisf_parabola_smoothed":true,"autoisf_parabola_min_minutes":5.5,"loop_interval":0}"#
                .utf8
        ))
        XCTAssertTrue(imported.enableSub5MinuteGlucose)
        XCTAssertNil(imported.autoISFParabolaMinMinutes)
        XCTAssertEqual(imported.sub5MinuteLoopInterval, 5)
        var preferences = imported
        preferences.autoISFParabolaMinMinutes = 20
        preferences.sub5MinuteLoopInterval = 1
        let data = try JSONEncoder().encode(preferences)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["autoisf_parabola_min_minutes"] as? Int, 20)
        XCTAssertEqual(object["loop_interval"] as? Int, 1)
        var profile = Profile()
        profile.update(from: preferences)
        XCTAssertTrue(profile.enableSub5MinuteGlucose)
        XCTAssertEqual(profile.autoISFParabolaMinMinutes, 20)
        var oldProfile = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Profile())) as? [String: Any])
        for key in ["enable_sub5_minute_glucose", "autoisf_parabola_smoothed", "autoisf_parabola_min_minutes", "loop_interval"] {
            oldProfile.removeValue(forKey: key)
        }
        let decoded = try decoder.decode(Profile.self, from: JSONSerialization.data(withJSONObject: oldProfile))
        XCTAssertFalse(decoded.enableSub5MinuteGlucose)
        XCTAssertEqual(decoded.sub5MinuteLoopInterval, 5)
    }

    func testGridDeltaUsesFiveMinuteUnitsAndLegacyIsExact() throws {
        let grid = readings(count: 10, spacing: 300)
        let legacy = try XCTUnwrap(DeterminationGenerator.getGlucoseStatus(glucoseReadings: grid))
        let typed = try XCTUnwrap(DeterminationGenerator.getGlucoseStatus(input: GlucoseAlgorithmInput(dosingReadings: grid)))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        XCTAssertEqual(try encoder.encode(legacy), try encoder.encode(typed))
        let dense = readings(count: 46)
        let sampled = stride(from: 0, to: dense.count, by: 5).map { dense[$0] }
        let status = try XCTUnwrap(DeterminationGenerator.getGlucoseStatus(input: GlucoseAlgorithmInput(
            dosingReadings: sampled, denseRawReadings: dense, cadence: .dense(medianSpacing: 60)
        )))
        XCTAssertEqual(status.delta, 5)
        XCTAssertEqual(status.shortAvgDelta, 5)
        XCTAssertEqual(status.longAvgDelta, 5)
    }

    func testDenseMinimumIsInclusiveAndFlatCheckStaysRaw() throws {
        let raw = readings(count: 11)
        let grid = [raw[0], raw[5], raw[10]]
        let base = try XCTUnwrap(DeterminationGenerator.getGlucoseStatus(glucoseReadings: grid))
        var profile = Profile()
        profile.autoisf = true
        profile.enableSub5MinuteGlucose = true
        let input = GlucoseAlgorithmInput(dosingReadings: grid, denseRawReadings: raw, cadence: .dense(medianSpacing: 60))
        let dense = try XCTUnwrap(AutoISFGlucose.getAutoISFGlucoseStatus(
            glucoseStatus: base, glucoseReadings: grid, profile: profile, input: input
        ))
        XCTAssertEqual(dense.dura_p, 10)
        XCTAssertEqual(dense.delta_pn, 5)
        var flat = raw
        for index in flat.indices { flat[index].sgv = 100 }
        var smoothedInput = input
        smoothedInput.denseSmoothedReadings = flat
        profile.autoISFParabolaSmoothed = true
        let smoothed = try XCTUnwrap(AutoISFGlucose.getAutoISFGlucoseStatus(
            glucoseStatus: base, glucoseReadings: grid, profile: profile, input: smoothedInput
        ))
        XCTAssertEqual(smoothed.cgmFlatMinutes, dense.cgmFlatMinutes)
        XCTAssertEqual(smoothed.delta_pn, 0)
        profile.enableSub5MinuteGlucose = false
        let legacy = AutoISFGlucose.getAutoISFGlucoseStatus(glucoseStatus: base, glucoseReadings: grid, profile: profile)
        let off = AutoISFGlucose.getAutoISFGlucoseStatus(
            glucoseStatus: base,
            glucoseReadings: grid,
            profile: profile,
            input: input
        )
        XCTAssertEqual(off?.dura_p, legacy?.dura_p)
    }

    func testCoverageCountsSupportedSlotsRatherThanDenseRows() {
        let dense = readings(count: 72)
        XCTAssertFalse(GlucoseAlgorithmInput(dosingReadings: dense, cadence: .dense(medianSpacing: 60)).hasAutosensCoverage)
        let grid = readings(count: 72, spacing: 300)
        XCTAssertTrue(GlucoseAlgorithmInput(dosingReadings: grid).hasAutosensCoverage)
        XCTAssertTrue(GlucoseAlgorithmInput(
            dosingReadings: grid, cadence: .dense(medianSpacing: 60), supportedGridDates: grid.map(\.dateString)
        ).hasAutosensCoverage)
        XCTAssertFalse(GlucoseAlgorithmInput(
            dosingReadings: dense, cadence: .dense(medianSpacing: 60), supportedGridDates: dense.map(\.dateString)
        ).hasAutosensCoverage)
    }

    func testDenseErrorBreakCannotReuseEarlierFit() throws {
        var raw = readings(count: 30)
        raw[5].sgv = 38
        let grid = stride(from: 0, to: raw.count, by: 5).map { raw[$0] }
        let status = try XCTUnwrap(DeterminationGenerator.getGlucoseStatus(glucoseReadings: grid))
        var profile = Profile()
        profile.autoisf = true
        profile.enableSub5MinuteGlucose = true
        let input = GlucoseAlgorithmInput(dosingReadings: grid, denseRawReadings: raw, cadence: .dense(medianSpacing: 60))
        let result = try XCTUnwrap(AutoISFGlucose.getAutoISFGlucoseStatus(
            glucoseStatus: status, glucoseReadings: grid, profile: profile, input: input
        ))
        XCTAssertEqual(result.dura_p, 0)
        XCTAssertEqual(result.delta_pn, 0)
    }

    func testSettingsFingerprintIsStableAcrossEncoders() {
        let preferences = Preferences()
        XCTAssertFalse(preferences.glucoseObservationFingerprint.isEmpty)
        for _ in 0 ..< 10 {
            XCTAssertEqual(preferences.glucoseObservationFingerprint, preferences.glucoseObservationFingerprint)
        }
    }
}
