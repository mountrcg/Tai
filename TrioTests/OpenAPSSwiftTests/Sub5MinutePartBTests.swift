import Foundation
@testable import Trio
import XCTest

final class Sub5MinutePartBTests: XCTestCase {
    private let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    func testIntervalSanitizerAcceptsOnlyWholeMinutesInRange() {
        for value in 1 ... 10 {
            XCTAssertEqual(SmbIntervalGate.sanitizedInterval(Decimal(value)), Decimal(value))
        }
        for value in [Decimal.nan, -1, 0, 11, Decimal(string: "1.5")!] {
            XCTAssertEqual(SmbIntervalGate.sanitizedInterval(value), 3)
        }
    }

    func testSixSecondToleranceUsesTimestampPrecision() {
        for interval in 1 ... 10 {
            let due = anchor.addingTimeInterval(Double(interval * 60 - 6))
            XCTAssertTrue(SmbIntervalGate.tooSoon(
                lastBolusTime: anchor, intervalMinutes: Decimal(interval), now: due.addingTimeInterval(-0.001)
            ))
            XCTAssertFalse(SmbIntervalGate.tooSoon(lastBolusTime: anchor, intervalMinutes: Decimal(interval), now: due))
            XCTAssertFalse(SmbIntervalGate.tooSoon(
                lastBolusTime: anchor, intervalMinutes: Decimal(interval), now: due.addingTimeInterval(0.001)
            ))
        }
    }

    func testUnknownOrInvalidHistoryNeverAuthorizesBolus() {
        for lastBolus in [nil, anchor.addingTimeInterval(1), Date(timeIntervalSince1970: .nan)] {
            XCTAssertTrue(SmbIntervalGate.tooSoon(lastBolusTime: lastBolus, intervalMinutes: 1, now: anchor))
        }
        XCTAssertTrue(SmbIntervalGate.tooSoon(
            lastBolusTime: anchor, intervalMinutes: 1, now: Date(timeIntervalSince1970: .infinity)
        ))
    }

    func testIntermediateSkipTruthTableAndEqualityBoundaries() {
        // SMB due is 174 seconds; regular run is due at 300 seconds.
        for (elapsed, skip) in [(0, true), (173.999, true), (174, false), (299, false),
                                (300, false), (301, false)]
        {
            XCTAssertEqual(Sub5MinuteLoopPolicy.shouldSkipIntermediateRun(
                now: anchor.addingTimeInterval(elapsed), lastRegularRun: anchor,
                loopInterval: 5, lastBolus: anchor, SMBInterval: 3
            ), skip)
        }
        for offset in [6.0, 7.0] {
            XCTAssertFalse(Sub5MinuteLoopPolicy.shouldSkipIntermediateRun(
                now: anchor.addingTimeInterval(60), lastRegularRun: anchor,
                loopInterval: 5, lastBolus: anchor.addingTimeInterval(offset), SMBInterval: 5
            ))
        }
    }

    func testUnknownProvenanceAndInvalidClockDoNotSuppressEvaluation() {
        for lastRegular in [nil, anchor.addingTimeInterval(1), Date(timeIntervalSince1970: .nan)] {
            XCTAssertFalse(Sub5MinuteLoopPolicy.shouldSkipIntermediateRun(
                now: anchor, lastRegularRun: lastRegular, loopInterval: 5, lastBolus: anchor, SMBInterval: 1
            ))
        }
        for lastBolus in [nil, anchor.addingTimeInterval(1), Date(timeIntervalSince1970: .infinity)] {
            XCTAssertFalse(Sub5MinuteLoopPolicy.shouldSkipIntermediateRun(
                now: anchor, lastRegularRun: anchor, loopInterval: 5, lastBolus: lastBolus, SMBInterval: 1
            ))
        }
        for interval in [Decimal.nan, 0, 11, Decimal(string: "1.5")!] {
            XCTAssertFalse(Sub5MinuteLoopPolicy.shouldSkipIntermediateRun(
                now: anchor, lastRegularRun: anchor, loopInterval: interval, lastBolus: anchor, SMBInterval: 1
            ))
        }
        XCTAssertFalse(Sub5MinuteLoopPolicy.shouldSkipIntermediateRun(
            now: Date(timeIntervalSince1970: .nan), lastRegularRun: anchor,
            loopInterval: 5, lastBolus: anchor, SMBInterval: 1
        ))
    }
}
