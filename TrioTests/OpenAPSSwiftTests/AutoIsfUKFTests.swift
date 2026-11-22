import Foundation
@testable import Trio
import XCTest

final class AutoIsfUKFTests: XCTestCase {
    private func series(_ values: [Double], minutes: Int64 = 5) -> [AutoIsfUKFGlucoseValue] {
        values.enumerated().map {
            AutoIsfUKFGlucoseValue(timestamp: 1_700_000_000_000 - Int64($0.offset) * minutes * 60000, value: $0.element)
        }
    }

    func testEmptySingleAndErrorFallbacks() {
        XCTAssertTrue(AutoIsfUKFSmoother().smooth([]).isEmpty)
        for (raw, expected) in [(100.0, 100.0), (20, 39)] {
            XCTAssertEqual(AutoIsfUKFSmoother().smooth(series([raw]))[0].smoothed, expected)
        }
        XCTAssertEqual(AutoIsfUKFSmoother().smooth(series([38, 38, 38])).map(\.smoothed), [39, 39, 39])
    }

    func testCleanRisingSpikeAndMajorGap() throws {
        let clean = AutoIsfUKFSmoother().smooth(series([101, 99, 100, 102, 98, 100, 101, 99, 100, 100]))
        for reading in clean { XCTAssertEqual(try XCTUnwrap(reading.smoothed), 100, accuracy: 30) }
        let rising = AutoIsfUKFSmoother().smooth(series([150, 140, 130, 120, 110, 100, 90, 80]))
        XCTAssertGreaterThan(try XCTUnwrap(rising.first?.smoothed), try XCTUnwrap(rising.last?.smoothed))
        let spike = AutoIsfUKFSmoother().smooth(series([100, 100, 100, 300, 100, 100, 100, 100]))
        XCTAssertEqual(spike[3].value, 300)
        XCTAssertLessThan(try XCTUnwrap(spike[3].smoothed), 200)
        let old = series([120, 119, 121]).map {
            AutoIsfUKFGlucoseValue(timestamp: $0.timestamp - 135 * 60000, value: $0.value)
        }
        XCTAssertGreaterThanOrEqual(AutoIsfUKFSmoother().smooth(series([100, 101, 99]) + old).compactMap(\.smoothed).count, 4)
    }

    func testDeterminismAndDenseFiltering() throws {
        let input = series([120, 118, 122, 119, 121, 120, 118])
        let a = AutoIsfUKFSmoother().smooth(input)
        let b = AutoIsfUKFSmoother().smooth(input)
        for (first, second) in zip(a, b) {
            XCTAssertEqual(try XCTUnwrap(first.smoothed), try XCTUnwrap(second.smoothed), accuracy: 1E-9)
        }
        let dense = series((0 ..< 60).map { $0.isMultiple(of: 2) ? 123 : 117 }, minutes: 1)
        XCTAssertTrue(AutoIsfUKFSmoother().smooth(dense).contains { abs(($0.smoothed ?? $0.value) - $0.value) > 1E-6 })
    }

    func testMedianNewestWindowDuplicatesGapsAndInsufficientHistory() {
        XCTAssertEqual(AutoIsfUKFSmoother.medianSpacingMinutes(series(Array(repeating: 100, count: 10), minutes: 1)), 1)
        XCTAssertEqual(AutoIsfUKFSmoother.medianSpacingMinutes(series(Array(repeating: 100, count: 10))), 5)
        let dense = series(Array(repeating: 100, count: 10), minutes: 1)
        let gap = dense.enumerated().map { index, reading in
            AutoIsfUKFGlucoseValue(timestamp: reading.timestamp - (index >= 6 ? 40 * 60000 : 0), value: 100)
        }
        XCTAssertEqual(AutoIsfUKFSmoother.medianSpacingMinutes(gap), 1)
        XCTAssertNil(AutoIsfUKFSmoother.medianSpacingMinutes(Array(dense.prefix(4))))
        XCTAssertEqual(AutoIsfUKFSmoother.medianSpacingMinutes([dense[0]] + dense), 1)
        XCTAssertEqual(AutoIsfUKFSmoother.medianSpacingMinutes(dense + series(Array(repeating: 100, count: 31))), 5)
    }

    func testDenseRateSeeding() throws {
        let input = series((0 ..< 20).map { 160 - Double($0) }, minutes: 1)
        XCTAssertEqual(try XCTUnwrap(AutoIsfUKFSmoother().smooth(input)[18].smoothed), input[18].value, accuracy: 1)
    }

    // captured from AAPS-autoISF 592410f984a824bc1e9e1d4113b74b7abaec93f3 via scripts/capture-autoisf-ukf-reference.py
    func testKotlinGoldenVector() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("json/autoisf-ukf-dense-reference.json")
        let expected = try JSONDecoder().decode([Double].self, from: Data(contentsOf: path))
        let input = series((0 ..< 60).map { 120 + ($0.isMultiple(of: 2) ? 3 : -3) + Double($0) * 0.2 }, minutes: 1)
        let output = AutoIsfUKFSmoother().smooth(input)
        XCTAssertEqual(output.count, expected.count)
        for (point, golden) in zip(output, expected) {
            XCTAssertEqual(try XCTUnwrap(point.smoothed), golden, accuracy: abs(golden) * 1E-6)
        }
    }

    func testPersistedBoundsSensorResetAndSuppressedLearning() throws {
        let input = series((0 ..< 60).map { $0.isMultiple(of: 2) ? 123 : 117 }, minutes: 1)
        let engine = AutoIsfUKFSmoother()
        _ = engine.smooth(input)
        let state = engine.persistedState
        _ = engine.smooth(input, learn: false)
        XCTAssertEqual(engine.persistedState, state)
        let resumed = AutoIsfUKFSmoother(state: state)
        XCTAssertEqual(resumed.persistedState, state)
        engine.sensorChanged(at: input[0].timestamp)
        _ = engine.smooth(input)
        XCTAssertEqual(engine.persistedState.sessionID, state.sessionID + 1)
        var invalid = state
        invalid.learnedR = 999
        let restored = AutoIsfUKFSmoother(state: invalid)
        let valid = AutoIsfUKFSmoother(state: .init(
            learnedR: 25,
            lastSavedTimestamp: state.lastSavedTimestamp,
            lastProcessedTimestamp: state.lastProcessedTimestamp
        ))
        XCTAssertEqual(restored.smooth(input).map(\.smoothed), valid.smooth(input).map(\.smoothed))
    }

    func testCalibrationDoesNotHideRawSentinel() {
        let input = [AutoIsfUKFGlucoseValue(timestamp: 1_700_000_000_000, value: 38, calibrated: 100)]
        XCTAssertEqual(AutoIsfUKFSmoother().smooth(input)[0].value, 38)
        XCTAssertEqual(AutoIsfUKFSmoother().smooth(input)[0].smoothed, 100)
    }
}
