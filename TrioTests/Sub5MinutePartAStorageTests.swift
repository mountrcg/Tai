import CoreData
import Swinject
@testable import Trio
import XCTest

final class Sub5MinutePartAStorageTests: XCTestCase {
    func testConcurrentSourceUpdatesAndIdentityReads() async throws {
        let epochKey = "denseGlucoseObservationEpoch"
        let savedEpoch = UserDefaults.standard.data(forKey: epochKey)
        defer { UserDefaults.standard.set(savedEpoch, forKey: epochKey) }
        let stack = try await CoreDataStack.createForTests()
        let context = stack.newTaskContext()
        let assembler = Assembler([
            StorageAssembly(), ServiceAssembly(), APSAssembly(), NetworkAssembly(), UIAssembly(), SecurityAssembly(),
            TestAssembly(testContext: context)
        ])
        let settings = try XCTUnwrap(assembler.resolver.resolve(SettingsManager.self))
        settings.settings.cgm = .none
        settings.settings.cgmPluginIdentifier = ""
        let manager = try XCTUnwrap(assembler.resolver.resolve(FetchGlucoseManager.self) as? BaseFetchGlucoseManager)
        let completed = expectation(description: "Concurrent source updates finish without deadlock")
        DispatchQueue.global().async {
            // run with Thread Sanitizer to detect unsynchronized identity getters as well as writes
            DispatchQueue.concurrentPerform(iterations: 200) { index in
                if index.isMultiple(of: 2) {
                    manager.updateGlucoseSource(
                        cgmGlucoseSourceType: .none, cgmGlucosePluginId: "source-\(index % 4)", newManager: nil
                    )
                } else {
                    XCTAssertEqual(manager.cgmGlucoseSourceType, .none)
                    XCTAssertTrue(["", "source-0", "source-2"].contains(manager.cgmGlucosePluginId))
                    XCTAssertNil(manager.cgmManager)
                    XCTAssertNil(manager.glucoseSource)
                }
            }
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 10)
        manager.updateGlucoseSource(cgmGlucoseSourceType: .none, cgmGlucosePluginId: "final", newManager: nil)
        XCTAssertEqual(manager.cgmGlucosePluginId, "final")
        XCTAssertNil(manager.cgmManager)
    }

    func testDenseReplayDeduplicationTombstonesProvenanceAndRevocation() async throws {
        let stack = try await CoreDataStack.createForTests()
        let context = stack.newTaskContext()
        let assembler = Assembler([
            StorageAssembly(), ServiceAssembly(), APSAssembly(), NetworkAssembly(), UIAssembly(), SecurityAssembly(),
            TestAssembly(testContext: context)
        ])
        let settings = try XCTUnwrap(assembler.resolver.resolve(SettingsManager.self))
        settings.preferences.enableSub5MinuteGlucose = true
        settings.settings.cgm = .plugin
        settings.settings.cgmPluginIdentifier = "LibreTransmitterManagerV3"
        settings.settings.smoothGlucose = false
        let storage = BaseGlucoseStorage(resolver: assembler.resolver, contextProvider: { context })
        let now = Date().addingTimeInterval(-1)
        let readings = (0 ..< 31).map { index -> BloodGlucose in
            let date = now.addingTimeInterval(-Double(index) * 60)
            return BloodGlucose(
                sgv: 140 - index,
                date: Decimal(date.timeIntervalSince1970 * 1000),
                dateString: date,
                glucose: 140 - index
            )
        }
        let observation = GlucoseObservationContext(
            sourceIdentifier: "LibreTransmitterManagerV3", epochID: UUID(), epochStart: now.addingTimeInterval(-3600),
            generationID: UUID(), cadence: .dense(medianSpacing: 60),
            preferencesJSON: settings.preferences.glucoseObservationFingerprint, smoothingEnabled: false,
            smoothingAlgorithm: settings.settings.smoothingAlgorithm.rawValue, settingsRevision: settings.glucoseInputRevision
        )
        storage.setObservationContext(observation)
        try await context.perform {
            let deleted = DeletedGlucoseStored(context: context)
            deleted.date = readings[12].dateString
            deleted.glucose = 128
            deleted.isManualGlucoseEntry = false
            try context.save()
        }
        try await storage.storeGlucose(Array(readings.prefix(8)), observation: observation)
        try await storage.backfillGlucose(readings + readings, observation: observation)
        try await context.perform {
            let rows = try context.fetch(GlucoseStored.fetchRequest())
            XCTAssertEqual(rows.count, 30)
            XCTAssertTrue(rows.allSatisfy { $0.observationEpochID == observation.epochID })
            XCTAssertFalse(rows.contains { $0.date == readings[12].dateString })
            XCTAssertTrue(rows.allSatisfy { $0.smoothedGlucose == nil })
        }
        let restored = try await storage.observationHistory(
            sourceIdentifier: observation.sourceIdentifier,
            epochID: observation.epochID
        )
        XCTAssertEqual(restored.count, 30)
        let foreign = try await storage.observationHistory(sourceIdentifier: observation.sourceIdentifier, epochID: UUID())
        XCTAssertTrue(foreign.isEmpty)
        let input = try await storage.getGlucoseAlgorithmInput(shouldSmoothGlucose: false, fetchHours: 24, context: observation)
        XCTAssertTrue(input.cadence.isDense)
        XCTAssertEqual(input.dosingReadings.count, 7)
        XCTAssertEqual(input.denseRawReadings?.count, 30)
        let unchangedPreferences = settings.preferences
        settings.preferences = unchangedPreferences
        XCTAssertNil(storage.observationContext)
        var staleWriteRan = false
        XCTAssertFalse(settings.withGlucoseInputRevision(observation.settingsRevision) { staleWriteRan = true })
        XCTAssertFalse(staleWriteRan)
        settings.preferences.enableSub5MinuteGlucose = false
        XCTAssertNil(storage.observationContext)
        try await storage.storeGlucose([BloodGlucose(
            sgv: 200,
            date: Decimal(now.timeIntervalSince1970 * 1000 + 60000),
            dateString: now.addingTimeInterval(60),
            glucose: 200
        )], observation: observation)
        let off = try await storage.getGlucoseAlgorithmInput(shouldSmoothGlucose: false, fetchHours: 24, context: observation)
        XCTAssertEqual(off.cadence, .legacy)
        XCTAssertNil(off.denseRawReadings)
        XCTAssertLessThan(off.dosingReadings.count, 30)
        let count = try await context.perform { try context.count(for: GlucoseStored.fetchRequest()) }
        XCTAssertEqual(count, 30)
    }

    /// Mirrors the manager's private persisted epoch so the test can stage a restart.
    private struct PersistedEpoch: Codable {
        var sourceIdentifier: String
        var id: UUID
        var start: Date
        var lastObservation: Date?
    }

    /// Restart: the epoch comes back from defaults while the in-memory candidates are empty, so the
    /// first single-reading callback must be judged dense from the persisted epoch history alone.
    func testColdStartFirstCallbackUsesPersistedEpochHistory() async throws {
        let epochKey = "denseGlucoseObservationEpoch"
        let savedEpoch = UserDefaults.standard.data(forKey: epochKey)
        defer { UserDefaults.standard.set(savedEpoch, forKey: epochKey) }
        let source = "LibreTransmitterManagerV3"
        let stack = try await CoreDataStack.createForTests()
        let context = stack.newTaskContext()
        let assembler = Assembler([
            StorageAssembly(), ServiceAssembly(), APSAssembly(), NetworkAssembly(), UIAssembly(), SecurityAssembly(),
            TestAssembly(testContext: context)
        ])
        let settings = try XCTUnwrap(assembler.resolver.resolve(SettingsManager.self))
        settings.preferences.enableSub5MinuteGlucose = true
        settings.settings.cgm = .plugin
        settings.settings.cgmPluginIdentifier = source
        settings.settings.smoothGlucose = false
        let storage = try XCTUnwrap(assembler.resolver.resolve(GlucoseStorage.self))
        let now = Date().addingTimeInterval(-1)
        let reading = { (minutesAgo: Int) -> BloodGlucose in
            let date = now.addingTimeInterval(-Double(minutesAgo) * 60)
            return BloodGlucose(
                sgv: 120 + minutesAgo, date: Decimal(date.timeIntervalSince1970 * 1000), dateString: date,
                glucose: 120 + minutesAgo
            )
        }
        let epoch = PersistedEpoch(
            sourceIdentifier: source, id: UUID(), start: now.addingTimeInterval(-3600),
            lastObservation: now.addingTimeInterval(-60)
        )
        let seed = GlucoseObservationContext(
            sourceIdentifier: source, epochID: epoch.id, epochStart: epoch.start, generationID: UUID(),
            cadence: .dense(medianSpacing: 60), preferencesJSON: settings.preferences.glucoseObservationFingerprint,
            smoothingEnabled: false, smoothingAlgorithm: settings.settings.smoothingAlgorithm.rawValue,
            settingsRevision: settings.glucoseInputRevision
        )
        storage.setObservationContext(seed)
        try await storage.backfillGlucose((1 ... 10).map(reading), observation: seed)
        storage.setObservationContext(nil)
        UserDefaults.standard.setValue(epoch, forKey: epochKey, reportError: true)

        let manager = try XCTUnwrap(assembler.resolver.resolve(FetchGlucoseManager.self) as? BaseFetchGlucoseManager)
        let fresh = reading(0)
        XCTAssertEqual(GlucoseCadence.detect([fresh], trusted: true, enabled: true, now: Date()), .legacy)
        manager.newGlucoseFromCgmManager(newGlucose: [fresh], sourceManager: manager.cgmManager)
        var observation: GlucoseObservationContext?
        for _ in 0 ..< 100 where observation == nil {
            try await Task.sleep(nanoseconds: 50_000_000)
            observation = storage.observationContext
        }
        let first = try XCTUnwrap(observation)
        XCTAssertEqual(first.epochID, epoch.id)
        XCTAssertEqual(first.cadence, .dense(medianSpacing: 60))
    }
}
