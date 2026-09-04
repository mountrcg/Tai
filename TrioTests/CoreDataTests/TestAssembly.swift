import CoreData
import Foundation
import Swinject
@testable import Trio

class TestAssembly: Assembly {
    private let testContext: NSManagedObjectContext

    init(testContext: NSManagedObjectContext) {
        self.testContext = testContext
    }

    func assemble(container: Container) {
        // Isolate SettingsManager/FileStorage from the simulator's real Documents
        // directory, whose persisted preferences.json/settings.json would otherwise
        // leak the developer's own settings (curve, concentration, ...) into tests.
        container.register(FileStorage.self) { _ in InMemoryFileStorage() }
            .inObjectScope(.container)

        // Swinject's default `.graph` scope hands out a fresh SettingsManager per top-level
        // resolve() call; pin it container-wide so a test mutating settings via resolver.resolve
        // affects the same instance storage received through @Injected.
        container.register(SettingsManager.self) { r in BaseSettingsManager(resolver: r) }
            .inObjectScope(.container)

        // Override PumpHistoryStorage registration for tests
        container.register(PumpHistoryStorage.self) { r in
            BasePumpHistoryStorage(resolver: r, contextProvider: { self.testContext })
        }.inObjectScope(.container)

        // Override DeterminationStorage registration for tests
        container.register(DeterminationStorage.self) { r in
            BaseDeterminationStorage(resolver: r, contextProvider: { self.testContext })
        }.inObjectScope(.container)

        // Override CarbsStorage registration for tests
        container.register(CarbsStorage.self) { r in
            BaseCarbsStorage(resolver: r, contextProvider: { self.testContext })
        }.inObjectScope(.container)

        // Override GlucoseStorage registration for tests
        container.register(GlucoseStorage.self) { r in
            BaseGlucoseStorage(resolver: r, contextProvider: { self.testContext })
        }.inObjectScope(.container)

        // Override TempTargetStorage registration for tests
        container.register(TempTargetsStorage.self) { r in
            BaseTempTargetsStorage(resolver: r, contextProvider: { self.testContext })
        }.inObjectScope(.container)

        // Override OverrideStorage registration for tests
        container.register(OverrideStorage.self) { r in
            BaseOverrideStorage(resolver: r, contextProvider: { self.testContext })
        }.inObjectScope(.container)
    }
}
