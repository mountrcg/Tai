import Foundation
import LoopKit
@testable import Trio
import XCTest

final class CGMSettingsSub5MinuteStateTests: XCTestCase {
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
        // the glucose simulator can run at 1-minute intervals, whatever plugin was last configured
        settings.settings.cgm = .simulator
        settings.settings.cgmPluginIdentifier = "unknown"
        XCTAssertTrue(state.isSuitableSource)
        XCTAssertTrue(autoISF.isSuitableSource)
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

    func testSmoothingLockFollowsSub5AndMirrorsEnforcedSettings() {
        let (state, _, settings) = fixture()
        XCTAssertFalse(state.isSmoothingLocked)
        // stands in for the settings manager's policy, which the stub does not run
        settings.settings.smoothGlucose = true
        settings.settings.smoothingAlgorithm = .adaptiveUkf
        state.setSub5MinuteGlucose(true)
        XCTAssertTrue(state.isSmoothingLocked)
        XCTAssertTrue(state.smoothGlucose)
        XCTAssertEqual(state.smoothingAlgorithm, .adaptiveUkf)
        state.setSub5MinuteGlucose(false)
        XCTAssertFalse(state.isSmoothingLocked)
        XCTAssertTrue(state.smoothGlucose)
    }

    func testSectionAppearanceUsesCurrentPreferences() {
        let (state, scope, _) = fixture()
        scope.preferences.enableSub5MinuteGlucose = true
        scope.preferences.sub5MinuteLoopInterval = 2
        scope.preferences.smbInterval = 3
        scope.preferences.smbDeliveryRatio = 0.6
        state.sub5MinuteSectionAppeared()
        XCTAssertTrue(state.enableSub5MinuteGlucose)
        XCTAssertEqual(state.smbInterval, 3)
        XCTAssertEqual(state.smbDeliveryRatio, 0.6)
        scope.preferences.smbDeliveryRatio = 0.8
        state.sub5MinuteSectionAppeared()
        XCTAssertEqual(state.smbDeliveryRatio, 0.8)
    }
}
