import Foundation
@testable import Trio
import XCTest

final class SmbDeliveryRatioSuggestionStateTests: XCTestCase {
    private final class Scope: SettingsScope {
        var writes = 0
        var preferences = Preferences() { didSet { writes += 1 } }
        var isDraft = false
        var basalProfile: [BasalProfileEntry] = []
        var sensitivities = InsulinSensitivities(units: .mgdL, userPreferredUnits: .mgdL, sensitivities: [])
        var carbRatios = CarbRatios(units: .grams, schedule: [])
        var bgTargets = BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
    }

    private func fixture(draft: Bool = false) -> (Scope, SmbDeliveryRatioReview, UserDefaults) {
        let scope = Scope()
        scope.isDraft = draft
        scope.preferences.sub5MinuteLoopInterval = 2
        scope.preferences.smbDeliveryRatio = Decimal(string: "0.7")!
        scope.writes = 0
        let defaults = UserDefaults(suiteName: "SmbDeliveryRatioTests.\(UUID())")!
        return (scope, SmbDeliveryRatioReview(scope: scope, defaults: defaults, context: { "profile-a" }), defaults)
    }

    func testApplyStagesAndCommitsExactlyOnceWithSelectedRatiosOnly() throws {
        let (scope, review, _) = fixture()
        let original = scope.preferences
        review.change(\.enableSub5MinuteGlucose, to: true)
        let pending = try XCTUnwrap(review.pending)
        XCTAssertEqual(scope.preferences, original)
        XCTAssertEqual(scope.writes, 0)
        XCTAssertEqual(pending.fields, [.fixed])
        XCTAssertTrue(review.resolve(pending.id, as: .apply, values: [.fixed: Decimal(string: "0.35")!]))
        var expected = original
        expected.enableSub5MinuteGlucose = true
        expected.smbDeliveryRatio = Decimal(string: "0.35")!
        XCTAssertEqual(scope.preferences, expected)
        XCTAssertEqual(scope.writes, 1)
        XCTAssertFalse(review.needsReview)
        XCTAssertFalse(review.resolve(pending.id, as: .apply, values: [.fixed: Decimal(string: "0.2")!]))
        XCTAssertEqual(scope.writes, 1)
    }

    func testKeepCancelAndDismissDoNotChangeRatios() throws {
        let (scope, review, _) = fixture()
        let original = scope.preferences
        review.change(\.enableSub5MinuteGlucose, to: true)
        XCTAssertTrue(review.resolve(try XCTUnwrap(review.pending).id, as: .cancel))
        XCTAssertEqual(scope.preferences, original)
        XCTAssertEqual(scope.writes, 0)
        review.change(\.enableSub5MinuteGlucose, to: true)
        review.pending = nil
        XCTAssertEqual(scope.preferences, original)
        review.change(\.enableSub5MinuteGlucose, to: true)
        XCTAssertTrue(review.resolve(try XCTUnwrap(review.pending).id, as: .keep))
        XCTAssertTrue(scope.preferences.enableSub5MinuteGlucose)
        XCTAssertEqual(scope.preferences.smbDeliveryRatio, original.smbDeliveryRatio)
        XCTAssertEqual(scope.writes, 1)
    }

    func testNewManualEditDiscardsStaleApplyAndKeep() throws {
        for resolution in [SmbDeliveryRatioReview.Resolution.apply, .keep] {
            let (scope, review, _) = fixture()
            review.change(\.enableSub5MinuteGlucose, to: true)
            let pending = try XCTUnwrap(review.pending)
            scope.preferences.smbDeliveryRatio = Decimal(string: "0.6")!
            let updated = scope.preferences
            XCTAssertFalse(review.resolve(pending.id, as: resolution, values: [.fixed: Decimal(string: "0.3")!]))
            XCTAssertEqual(scope.preferences, updated)
            XCTAssertTrue(review.staleReview)
            XCTAssertNil(review.pending)
        }
    }

    func testProfileSourceOrRevisionChangeDiscardsEvenIdenticalPreferences() throws {
        let (scope, _, defaults) = fixture()
        var context = "profile-a.source-a"
        var revision = "1"
        let review = SmbDeliveryRatioReview(scope: scope, defaults: defaults, revision: { revision }, context: { context })
        review.change(\.enableSub5MinuteGlucose, to: true)
        let first = try XCTUnwrap(review.pending)
        context = "profile-b.source-b"
        XCTAssertFalse(review.resolve(first.id, as: .keep))
        review.change(\.enableSub5MinuteGlucose, to: true)
        let second = try XCTUnwrap(review.pending)
        revision = "2"
        XCTAssertFalse(review.resolve(second.id, as: .keep))
        XCTAssertEqual(scope.writes, 0)
    }

    func testAcknowledgementSurvivesReopeningAndLaterTransitionUsesCurrentRatios() throws {
        let (scope, review, defaults) = fixture()
        review.change(\.enableSub5MinuteGlucose, to: true)
        review.resolve(try XCTUnwrap(review.pending).id, as: .keep)
        let reopened = SmbDeliveryRatioReview(scope: scope, defaults: defaults, context: { "profile-a" })
        reopened.refresh()
        XCTAssertNil(reopened.pending)
        XCTAssertFalse(reopened.needsReview)
        XCTAssertEqual(scope.writes, 1)
        reopened.change(\.enableSub5MinuteGlucose, to: false)
        scope.preferences.smbDeliveryRatio = Decimal(string: "0.6")!
        reopened.change(\.enableSub5MinuteGlucose, to: true)
        XCTAssertEqual(try XCTUnwrap(reopened.pending).current(.fixed), Decimal(string: "0.6")!)
    }

    func testProgrammaticActivationOnlyShowsPassiveReviewAndDraftAcknowledgementIsIsolated() throws {
        let (live, liveReview, defaults) = fixture()
        live.preferences.enableSub5MinuteGlucose = true
        liveReview.refresh()
        XCTAssertNil(liveReview.pending)
        XCTAssertTrue(liveReview.needsReview)
        let draft = Scope()
        draft.isDraft = true
        draft.preferences = live.preferences
        let review = SmbDeliveryRatioReview(scope: draft, defaults: defaults, context: { "profile-a" })
        review.reviewCurrent()
        review.resolve(try XCTUnwrap(review.pending).id, as: .keep)
        XCTAssertFalse(review.needsReview)
        XCTAssertTrue(liveReview.needsReview)
        XCTAssertEqual(live.preferences.smbDeliveryRatio, Decimal(string: "0.7")!)
        let reopened = SmbDeliveryRatioReview(scope: draft, defaults: defaults, context: { "profile-a" })
        XCTAssertFalse(reopened.needsReview)
    }

    func testRampSelectionCannotInvertEndpointsOrIncreaseImportedValues() throws {
        let (scope, review, _) = fixture()
        scope.preferences.autoisf = true
        scope.preferences.smbDeliveryRatioBGrange = 100
        scope.preferences.smbDeliveryRatioMin = Decimal(string: "0.65")!
        scope.preferences.smbDeliveryRatioMax = Decimal(string: "0.8")!
        review.change(\.enableSub5MinuteGlucose, to: true)
        let pending = try XCTUnwrap(review.pending)
        XCTAssertEqual(pending.fields.count, 3)
        XCTAssertFalse(review.canApply(pending, values: [.maximum: Decimal(string: "0.4")!]))
        XCTAssertFalse(review.canApply(pending, values: [.fixed: Decimal(string: "0.75")!]))
        XCTAssertFalse(review.canApply(pending, values: [.fixed: Decimal(string: "0.333")!]))
        XCTAssertTrue(review.canApply(pending, values: [.minimum: Decimal(string: "0.3")!, .maximum: Decimal(string: "0.45")!]))
        XCTAssertTrue(review.resolve(pending.id, as: .apply, values: [.fixed: Decimal(string: "0.35")!]))
        XCTAssertEqual(scope.preferences.smbDeliveryRatioMin, pending.starting.smbDeliveryRatioMin)
        XCTAssertEqual(scope.preferences.smbDeliveryRatioMax, pending.starting.smbDeliveryRatioMax)
    }

    func testOnlyExplicitEnableOrShorterReferencePrompts() throws {
        let (scope, review, _) = fixture()
        review.change(\.sub5MinuteLoopInterval, to: 1)
        XCTAssertNil(review.pending)
        review.change(\.enableSub5MinuteGlucose, to: true)
        review.resolve(try XCTUnwrap(review.pending).id, as: .keep)
        review.change(\.sub5MinuteLoopInterval, to: 4)
        XCTAssertNil(review.pending)
        review.change(\.sub5MinuteLoopInterval, to: 2)
        XCTAssertNotNil(review.pending)
        XCTAssertEqual(scope.preferences.sub5MinuteLoopInterval, 4)
    }

    func testPickerRegistrationAndAutomaticNilRoundTrip() throws {
        let loop = try XCTUnwrap(PickerSettingsProvider.shared.pickerSetting(for: "sub5MinuteLoopInterval"))
        XCTAssertEqual(
            PickerSettingsProvider.shared.generatePickerValues(from: loop, units: .mgdL),
            (1 ... 10).map { Decimal($0) }
        )
        let parabola = try XCTUnwrap(PickerSettingsProvider.shared.pickerSetting(for: "autoISFParabolaMinMinutes"))
        XCTAssertEqual(
            PickerSettingsProvider.shared.generatePickerValues(from: parabola, units: .mgdL),
            (5 ... 20).map { Decimal($0) }
        )
        let (scope, review, _) = fixture()
        review.change(\.autoISFParabolaMinMinutes, to: 10)
        review.change(\.autoISFParabolaMinMinutes, to: nil)
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(scope.preferences))
        XCTAssertNil(decoded.autoISFParabolaMinMinutes)
    }
}
