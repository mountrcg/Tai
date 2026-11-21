import Foundation
import LoopKit
import Swinject

protocol SettingsManager: AnyObject {
    var settings: TrioSettings { get set }
    var preferences: Preferences { get set }
    var glucoseInputRevision: UUID? { get }
    func withGlucoseInputRevision(_ revision: UUID?, perform operation: () throws -> Void) rethrows -> Bool
    var pumpSettings: PumpSettings { get }
    func updateInsulinCurve(_ insulinType: InsulinType?)
}

extension SettingsManager {
    var glucoseInputRevision: UUID? { nil }
    func withGlucoseInputRevision(_ revision: UUID?, perform operation: () throws -> Void) rethrows -> Bool {
        guard revision == glucoseInputRevision else { return false }
        try operation()
        return true
    }
}

protocol SettingsObserver {
    func settingsDidChange(_: TrioSettings)
}

protocol PreferencesObserver {
    func preferencesDidChange(_: Preferences)
}

final class BaseSettingsManager: SettingsManager, Injectable {
    @Injected() var broadcaster: Broadcaster!
    @Injected() var storage: FileStorage!
    @Injected() private var watchCommandAuthorization: WatchCommandAuthorization!

    private let glucoseRevisionLock = NSRecursiveLock()
    private var currentGlucoseRevision = UUID()

    var glucoseInputRevision: UUID? {
        glucoseRevisionLock.lock()
        defer { glucoseRevisionLock.unlock() }
        return currentGlucoseRevision
    }

    private func advanceGlucoseInputRevision() {
        glucoseRevisionLock.lock()
        defer { glucoseRevisionLock.unlock() }
        currentGlucoseRevision = UUID()
    }

    func withGlucoseInputRevision(_ revision: UUID?, perform operation: () throws -> Void) rethrows -> Bool {
        glucoseRevisionLock.lock()
        defer { glucoseRevisionLock.unlock() }
        guard revision == currentGlucoseRevision else { return false }
        try operation()
        return true
    }

    /// Watch command revocation happens in `willSet`, on the writing queue: the observer
    /// notification below is asynchronous and delivers only the latest value, so it cannot tell
    /// that a command setting was switched off and back on in between.
    @SyncAccess var settings: TrioSettings {
        willSet {
            if settings.smoothGlucose != newValue.smoothGlucose || settings.smoothingAlgorithm != newValue.smoothingAlgorithm ||
                settings.cgm != newValue.cgm || settings.cgmPluginIdentifier != newValue.cgmPluginIdentifier
            {
                advanceGlucoseInputRevision()
            }
            watchCommandAuthorization.settingsWillChange(from: settings, to: newValue)
        }
        didSet {
            if oldValue != settings {
                saveSettings()
                DispatchQueue.main.async {
                    self.broadcaster.notify(SettingsObserver.self, on: .main) {
                        $0.settingsDidChange(self.settings)
                    }
                }
            }
        }
    }

    @SyncAccess var preferences: Preferences {
        // profile activation writes even equal preferences; invalidate before observers can lag behind
        willSet { advanceGlucoseInputRevision() }
        didSet {
            if oldValue != preferences {
                savePreferences()
                DispatchQueue.main.async {
                    self.broadcaster.notify(PreferencesObserver.self, on: .main) {
                        $0.preferencesDidChange(self.preferences)
                    }
                }
            }
        }
    }

    private func saveSettings() {
        storage.save(settings, as: OpenAPS.Trio.settings)
    }

    private func savePreferences() {
        storage.save(preferences, as: OpenAPS.Settings.preferences)
        ActiveProfileMirror.shared.updatePreferences(preferences)
    }

    init(resolver: Resolver) {
        let storage = resolver.resolve(FileStorage.self)!
        settings = storage.retrieve(OpenAPS.Trio.settings, as: TrioSettings.self)
            ?? TrioSettings(from: OpenAPS.defaults(for: OpenAPS.Trio.settings))
            ?? TrioSettings()

        preferences =
            storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
                ?? Preferences(from: OpenAPS.defaults(for: OpenAPS.Settings.preferences))
                ?? Preferences()

        injectServices(resolver)
    }

    var pumpSettings: PumpSettings {
        storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
            ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
            ?? PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2)
    }

    func updateInsulinCurve(_ insulinType: InsulinType?) {
        var prefs = preferences

        switch insulinType {
        case .apidra,
             .humalog,
             .novolog:
            prefs.curve = .rapidActing

        case .fiasp,
             .lyumjev:
            prefs.curve = .ultraRapid
        default:
            prefs.curve = .rapidActing
        }

        preferences = prefs
        savePreferences()
    }
}
