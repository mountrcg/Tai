import Foundation
@testable import Trio
import XCTest

final class Sub5MinutePartBTests: XCTestCase {
    func testSuggestionUsesLoopIntervalAndGraphDomain() {
        XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: 0.7, field: .fixed, loopInterval: 1),
                       .suggestion(value: 0.2, lowerBoundLimited: false))
        XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: 0.7, field: .fixed, loopInterval: 3),
                       .suggestion(value: 0.5, lowerBoundLimited: false))
        XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: 0.7, field: .fixed, loopInterval: 2),
                       .suggestion(value: 0.35, lowerBoundLimited: false))
        for interval in 5 ... 10 {
            XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: 0.7, field: .fixed, loopInterval: Decimal(interval)),
                           .keepCurrent)
        }
        for ratio: Decimal in [1, 1.2, 1.5] {
            XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: ratio, field: .fixed, loopInterval: 1), .keepCurrent)
        }
    }

    func testSuggestionBoundsAndInvalidImports() {
        for field in SmbDeliveryRatioSuggestion.Field.allCases {
            XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: 0.1, field: field, loopInterval: 1),
                           .suggestion(value: 0.1, lowerBoundLimited: true))
            for ratio: Decimal in [.nan, 0, 0.05, field.bounds.upperBound + 0.05] {
                XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: ratio, field: field, loopInterval: 1), .invalid)
            }
            for interval: Decimal in [.nan, 0, 1.5, 11] {
                XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: 0.5, field: field, loopInterval: interval), .invalid)
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
                    current: current, field: .minimum, loopInterval: Decimal(interval)
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
        XCTAssertEqual(SmbDeliveryRatioSuggestion.suggestion(current: Decimal(string: "0.67232")!, field: .fixed, loopInterval: 1),
                       .suggestion(value: 0.2, lowerBoundLimited: false))
    }

}
