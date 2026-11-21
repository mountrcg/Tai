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
    func testAmendedSuggestionUsesSMBIntervalAndGraphDomain() {
        XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: 0.7, field: .fixed, smbInterval: 1),
                       .suggestion(value: 0.2, lowerBoundLimited: false))
        XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: 0.7, field: .fixed, smbInterval: 3),
                       .suggestion(value: 0.5, lowerBoundLimited: false))
        for interval in 5 ... 10 {
            XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: 0.7, field: .fixed, smbInterval: Decimal(interval)),
                           .keepCurrent)
        }
        for ratio: Decimal in [1, 1.2, 1.5] {
            XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: ratio, field: .fixed, smbInterval: 1), .keepCurrent)
        }
    }

    func testSuggestionBoundsAndInvalidImports() {
        for field in SmbDeliveryRatioSuggestion.Field.allCases {
            XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: 0.1, field: field, smbInterval: 1),
                           .suggestion(value: 0.1, lowerBoundLimited: true))
            for ratio: Decimal in [.nan, 0, 0.05, field.bounds.upperBound + 0.05] {
                XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: ratio, field: field, smbInterval: 1), .invalid)
            }
            for interval: Decimal in [.nan, 0, 1.5, 11] {
                XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: 0.5, field: field, smbInterval: interval), .invalid)
            }
        }
        XCTAssertFalse(SmbDeliveryRatioSuggestion.validEndpoints(minimum: 0.8, maximum: 0.7))
        XCTAssertFalse(SmbDeliveryRatioSuggestion.validEndpoints(minimum: .nan, maximum: 0.7))
        XCTAssertTrue(SmbDeliveryRatioSuggestion.validEndpoints(minimum: 0.7, maximum: 1.2))
    }

    func testSuggestionNeverIncreasesAndPreservesEndpointOrder() {
        for interval in 1 ... 4 {
            var previous: Decimal = 0
            for hundredths in stride(from: 10, through: 95, by: 5) {
                let current = Decimal(hundredths) / 100
                guard case let .suggestion(value, _) = SmbDeliveryRatioSuggestion.suggestion(
                    current: current, field: .minimum, smbInterval: Decimal(interval)
                ) else { return XCTFail("Expected a suggestion") }
                XCTAssertLessThanOrEqual(value, current)
                XCTAssertGreaterThanOrEqual(value, previous)
                var steps = value / Decimal(string: "0.05")!
                var integer = Decimal()
                NSDecimalRound(&integer, &steps, 0, .down)
                XCTAssertEqual(steps, integer)
                previous = value
            }
        }
        // 1 - (1 - 0.2)^5 is an exact picker boundary in the inverse graph.
        XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: 0.67232, field: .fixed, smbInterval: 1),
                       .suggestion(value: 0.2, lowerBoundLimited: false))
    }

}
