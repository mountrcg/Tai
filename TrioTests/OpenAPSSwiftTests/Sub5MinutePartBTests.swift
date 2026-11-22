import Foundation
@testable import Trio
import XCTest

final class SmbDeliveryRatioSuggestionTests: XCTestCase {
    private func suggestion(
        _ ratio: Decimal = 0.5,
        oldLoop: Decimal = 5,
        oldSMB: Decimal = 3,
        loop: Decimal = 1,
        smb: Decimal = 3
    ) -> SmbDeliveryRatioSuggestion.Result {
        SmbDeliveryRatioSuggestion.suggestion(
            baseline: .init(loopInterval: oldLoop, smbInterval: oldSMB, ratio: ratio),
            loopInterval: loop, smbInterval: smb
        )
    }

    func testEffectiveCadenceIncludesSMBThrottle() {
        XCTAssertEqual(suggestion(), .suggestion(value: 0.3, lowerBoundLimited: false))
        // 1 - 0.5^(1/5) is 0.12945, which floors to 0.10, not 0.15.
        XCTAssertEqual(suggestion(oldSMB: 1, smb: 1), .suggestion(value: 0.1, lowerBoundLimited: false))
        XCTAssertEqual(suggestion(0.7, oldLoop: 3, oldSMB: 5), .suggestion(value: 0.5, lowerBoundLimited: false))
    }

    func testSlowerOrUnchangedCadenceKeepsCurrent() {
        XCTAssertEqual(suggestion(loop: 5), .keepCurrent)
        XCTAssertEqual(suggestion(smb: 6), .keepCurrent)
        for ratio: Decimal in [1, 1.2, 1.5] {
            XCTAssertEqual(suggestion(ratio), .keepCurrent)
        }
    }

    func testInvalidValues() {
        for ratio: Decimal in [.nan, 0, 0.05, 1.55] {
            XCTAssertEqual(suggestion(ratio), .invalid)
        }
        for interval: Decimal in [.nan, 0, 1.5, 11] {
            XCTAssertEqual(suggestion(loop: interval), .invalid)
            XCTAssertEqual(suggestion(oldLoop: interval), .invalid)
        }
        XCTAssertEqual(suggestion(smb: .nan), .invalid)
        XCTAssertEqual(suggestion(oldSMB: 0), .invalid)
    }

    func testReduceOnlyGridAndBounds() {
        for interval in 1 ... 4 {
            for hundredths in stride(from: 10, through: 95, by: 5) {
                let current = Decimal(hundredths) / 100
                guard case let .suggestion(value, _) = suggestion(current, oldSMB: 1, loop: Decimal(interval), smb: 1)
                else { return XCTFail("Expected suggestion") }
                XCTAssertLessThanOrEqual(value, current)
                XCTAssertGreaterThanOrEqual(value, 0.1)
                var steps = value / Decimal(string: "0.05")!
                var integer = Decimal()
                NSDecimalRound(&integer, &steps, 0, .down)
                XCTAssertEqual(steps, integer)
            }
        }
        XCTAssertEqual(suggestion(0.1), .suggestion(value: 0.1, lowerBoundLimited: true))
        XCTAssertEqual(
            suggestion(Decimal(string: "0.67232")!, oldSMB: 1, smb: 1),
            .suggestion(value: 0.2, lowerBoundLimited: false)
        )
    }

    func testFallbackUsesNamedDefaultsAndPreservesOtherPreferences() {
        var preferences = Preferences()
        preferences.enableSub5MinuteGlucose = true
        preferences.sub5MinuteLoopInterval = 1
        preferences.smbInterval = 1
        preferences.smbDeliveryRatio = 0.7
        let original = preferences
        preferences.normalizeSub5MinuteSettings()
        let fallback = Preferences.sub5Fallback
        XCTAssertEqual(preferences.enableSub5MinuteGlucose, fallback.enable)
        XCTAssertEqual(preferences.sub5MinuteLoopInterval, fallback.loopInterval)
        XCTAssertEqual(preferences.smbInterval, fallback.smbInterval)
        XCTAssertEqual(preferences.smbDeliveryRatio, fallback.smbDeliveryRatio)
        XCTAssertEqual(preferences.smbDeliveryRatioMin, original.smbDeliveryRatioMin)
        XCTAssertEqual(preferences.autoISFParabolaMinMinutes, original.autoISFParabolaMinMinutes)
        XCTAssertEqual(Preferences().smbInterval, 3)
        XCTAssertEqual(Preferences().smbDeliveryRatio, 0.85)
    }
}
