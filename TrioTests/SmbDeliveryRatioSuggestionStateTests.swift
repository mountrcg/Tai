import Foundation
import LoopKit
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

    private final class Settings: SettingsManager {
        var settings = TrioSettings()
        var preferences = Preferences()
        var pumpSettings = PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2)
        func updateInsulinCurve(_: InsulinType?) {}
    }

    private func fixture() -> (CGMSettings.StateModel, Scope, Settings) {
        let scope = Scope()
        let settings = Settings()
        let state = CGMSettings.StateModel()
        state.scope = scope
        state.settingsManager = settings
        return (state, scope, settings)
    }

    func testSuitabilityRequiresPluginAndAllowlistedIdentifier() {
        let (state, _, settings) = fixture()
        let autoISF = AutoISFSettings.StateModel()
        autoISF.settingsManager = settings
        for identifier in ["LibreTransmitterManagerV3", "LibreLoopCGMManager", "SyaiCGMManager", "unknown", ""] {
            settings.settings.cgmPluginIdentifier = identifier
            settings.settings.cgm = .plugin
            XCTAssertEqual(state.isSuitableSource, !["unknown", ""].contains(identifier))
            XCTAssertEqual(autoISF.isSuitableSource, state.isSuitableSource)
            settings.settings.cgm = .none
            XCTAssertFalse(state.isSuitableSource)
            XCTAssertFalse(autoISF.isSuitableSource)
        }
    }

    func testLaunchDoesNotNormalizeAndSourceTransitionNormalizesOnlyOnce() {
        let (state, scope, settings) = fixture()
        scope.preferences.enableSub5MinuteGlucose = true
        scope.preferences.sub5MinuteLoopInterval = 1
        scope.preferences.smbInterval = 2
        scope.preferences.smbDeliveryRatio = 0.7
        let original = scope.preferences
        scope.writes = 0
        state.normalizeSub5MinuteSettingsOnSourceChange()
        XCTAssertEqual(scope.preferences, original)
        XCTAssertEqual(scope.writes, 0)
        settings.settings.cgm = .plugin
        settings.settings.cgmPluginIdentifier = "SyaiCGMManager"
        state.normalizeSub5MinuteSettingsOnSourceChange()
        XCTAssertEqual(scope.preferences, original)
        settings.settings.cgm = .none
        state.normalizeSub5MinuteSettingsOnSourceChange()
        var expected = original
        expected.normalizeSub5MinuteSettings()
        XCTAssertEqual(scope.preferences, expected)
        XCTAssertEqual(scope.writes, 1)
        scope.preferences.smbDeliveryRatio = 0.8
        state.normalizeSub5MinuteSettingsOnSourceChange()
        XCTAssertEqual(scope.preferences.smbDeliveryRatio, 0.8)
    }

    func testSectionAppearanceUsesCurrentPreferences() {
        let (state, scope, _) = fixture()
        scope.preferences.enableSub5MinuteGlucose = true
        scope.preferences.sub5MinuteLoopInterval = 2
        scope.preferences.smbInterval = 3
        scope.preferences.smbDeliveryRatio = 0.6
        state.sub5MinuteSectionAppeared()
        XCTAssertEqual(state.suggestionBaseline, .init(loopInterval: 2, smbInterval: 3, ratio: 0.6))
        scope.preferences.smbDeliveryRatio = 0.8
        state.sub5MinuteSectionAppeared()
        XCTAssertEqual(state.smbDeliveryRatio, 0.8)
        XCTAssertEqual(state.suggestionBaseline?.ratio, 0.8)
    }

    func testBaselineLifecycleAndApply() {
        let (state, _, settings) = fixture()
        settings.settings.cgm = .plugin
        settings.settings.cgmPluginIdentifier = "SyaiCGMManager"
        state.smbDeliveryRatio = 0.5
        state.enableSub5MinuteGlucose = true
        state.seedSuggestionBaseline()
        state.sub5MinuteLoopInterval = 1
        XCTAssertEqual(state.suggestedRatio, 0.3)
        state.applySuggestedRatio()
        XCTAssertEqual(state.smbDeliveryRatio, 0.3)
        XCTAssertNil(state.suggestedRatio)
        state.smbInterval = 1
        XCTAssertNotNil(state.suggestedRatio)
        state.smbDeliveryRatio = 0.6
        XCTAssertNil(state.suggestedRatio)
        XCTAssertEqual(state.suggestionBaseline?.ratio, 0.6)
        state.enableSub5MinuteGlucose = false
        XCTAssertNil(state.suggestionBaseline)
        state.sub5MinuteLoopInterval = 5
        state.enableSub5MinuteGlucose = true
        XCTAssertEqual(state.suggestionBaseline?.loopInterval, 5)
    }
}
