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
        // sub-5 forces Adaptive UKF smoothing on (SmoothingPolicy); storage never smooths on store
        XCTAssertTrue(settings.settings.smoothGlucose)
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
            preferencesJSON: settings.preferences.glucoseObservationFingerprint, smoothingEnabled: true,
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

    /// Off-mode rollback must smooth the newest-first rows chronologically, exactly like the production path.
    /// Rows are 5 minutes apart because off mode admits dense history at the legacy cadence; the 1-minute sibling
    /// only marks the epoch as dense history.
    // retargeted from the removed exponential path (67db834d7): Adaptive UKF is the only legacy smoother left
    func testAdaptiveUkfRollbackMatchesChronologicalSmoothing() async throws {
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
        settings.settings.smoothGlucose = true
        settings.settings.smoothingAlgorithm = .adaptiveUkf
        let storage = BaseGlucoseStorage(resolver: assembler.resolver, contextProvider: { context })
        let now = Date().addingTimeInterval(-1)
        let reading = { (date: Date, value: Int) in
            BloodGlucose(sgv: value, date: Decimal(date.timeIntervalSince1970 * 1000), dateString: date, glucose: value)
        }
        let admitted = (0 ..< 10).map { index in
            reading(now.addingTimeInterval(-Double(9 - index) * 300), 100 + index * 10)
        }
        let sibling = reading(admitted[0].dateString.addingTimeInterval(60), 101)
        let observation = GlucoseObservationContext(
            sourceIdentifier: source, epochID: UUID(), epochStart: now.addingTimeInterval(-3600),
            generationID: UUID(), cadence: .dense(medianSpacing: 60),
            preferencesJSON: settings.preferences.glucoseObservationFingerprint, smoothingEnabled: true,
            smoothingAlgorithm: settings.settings.smoothingAlgorithm.rawValue, settingsRevision: settings.glucoseInputRevision
        )
        storage.setObservationContext(observation)
        try await storage.backfillGlucose(admitted + [sibling], observation: observation)

        let referenceStack = try await CoreDataStack.createForTests()
        let referenceContext = referenceStack.newTaskContext()
        try await referenceContext.perform {
            for value in admitted {
                let row = GlucoseStored(context: referenceContext)
                row.date = value.dateString
                row.glucose = Int16(value.glucose ?? 0)
                row.isManual = false
            }
            try referenceContext.save()
        }
        let manager = try XCTUnwrap(assembler.resolver.resolve(FetchGlucoseManager.self) as? BaseFetchGlucoseManager)
        await manager.adaptiveUkfSmoothingGlucose(context: referenceContext)
        let reference: [Date: Int] = try await referenceContext.perform {
            try Dictionary(uniqueKeysWithValues: referenceContext.fetch(GlucoseStored.fetchRequest()).compactMap { row in
                guard let date = row.date, let value = row.smoothedGlucose else { return nil }
                return (date, value.intValue)
            })
        }
        XCTAssertEqual(reference.count, 10)

        settings.preferences.enableSub5MinuteGlucose = false
        let input = try await storage.getGlucoseAlgorithmInput(shouldSmoothGlucose: true, fetchHours: 24, context: nil)
        XCTAssertEqual(input.dosingReadings.count, 10)
        for row in input.dosingReadings {
            XCTAssertEqual(row.sgv, reference[row.dateString], "\(row.dateString)")
        }
        let newest = try XCTUnwrap(input.dosingReadings.max { $0.dateString < $1.dateString })
        XCTAssertEqual(newest.sgv, reference[newest.dateString])
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
        // sub-5 forces Adaptive UKF smoothing on (SmoothingPolicy); storage never smooths on store
        XCTAssertTrue(settings.settings.smoothGlucose)
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
            smoothingEnabled: true, smoothingAlgorithm: settings.settings.smoothingAlgorithm.rawValue,
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

    /// A settings change wipes the in-memory candidates mid-session; the next single-reading callback must stay
    /// dense from the stored rows of the live epoch instead of waiting ~6 minutes for the buffer to requalify.
    func testSettingsResetKeepsDenseCadenceFromStoredRows() async throws {
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
        let storage = try XCTUnwrap(assembler.resolver.resolve(GlucoseStorage.self))
        let now = Date().addingTimeInterval(-2)
        let reading = { (secondsAgo: Double) -> BloodGlucose in
            let date = now.addingTimeInterval(-secondsAgo)
            return BloodGlucose(
                sgv: 120 + Int(secondsAgo / 60), date: Decimal(date.timeIntervalSince1970 * 1000), dateString: date,
                glucose: 120 + Int(secondsAgo / 60)
            )
        }
        let epoch = PersistedEpoch(
            sourceIdentifier: source, id: UUID(), start: now.addingTimeInterval(-3600),
            lastObservation: now.addingTimeInterval(-60)
        )
        let seed = GlucoseObservationContext(
            sourceIdentifier: source, epochID: epoch.id, epochStart: epoch.start, generationID: UUID(),
            cadence: .dense(medianSpacing: 60), preferencesJSON: settings.preferences.glucoseObservationFingerprint,
            smoothingEnabled: true, smoothingAlgorithm: settings.settings.smoothingAlgorithm.rawValue,
            settingsRevision: settings.glucoseInputRevision
        )
        storage.setObservationContext(seed)
        try await storage.backfillGlucose((1 ... 10).map { reading(Double($0) * 60) }, observation: seed)
        storage.setObservationContext(nil)
        UserDefaults.standard.setValue(epoch, forKey: epochKey, reportError: true)

        let manager = try XCTUnwrap(assembler.resolver.resolve(FetchGlucoseManager.self) as? BaseFetchGlucoseManager)
        let awaitObservation = { (previous: UUID?) async throws -> GlucoseObservationContext in
            var observation: GlucoseObservationContext?
            for _ in 0 ..< 100 {
                if let current = storage.observationContext, current.generationID != previous {
                    observation = current
                    break
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            return try XCTUnwrap(observation)
        }
        manager.newGlucoseFromCgmManager(newGlucose: [reading(1)], sourceManager: manager.cgmManager)
        let primed = try await awaitObservation(nil)
        XCTAssertEqual(primed.cadence, .dense(medianSpacing: 60))

        // any preference is part of the fingerprint, so this wipes the candidates on the next callback
        let fingerprint = settings.preferences.glucoseObservationFingerprint
        settings.preferences.smbInterval = settings.preferences.smbInterval == 3 ? 2 : 3
        XCTAssertNotEqual(settings.preferences.glucoseObservationFingerprint, fingerprint)

        let fresh = reading(0)
        XCTAssertEqual(GlucoseCadence.detect([fresh], trusted: true, enabled: true, now: Date()), .legacy)
        manager.newGlucoseFromCgmManager(newGlucose: [fresh], sourceManager: manager.cgmManager)
        let first = try await awaitObservation(primed.generationID)
        XCTAssertEqual(first.epochID, epoch.id)
        XCTAssertEqual(first.cadence, .dense(medianSpacing: 60))
        XCTAssertEqual(CGMCadenceChangeMonitor.minutes(for: first.cadence), 1)
        let frequency = LoopFrequency.current(
            enabled: true, detectedMinutes: CGMCadenceChangeMonitor.minutes(for: first.cadence)
        )
        XCTAssertEqual(frequency, .detected(1))
        XCTAssertEqual(frequency.minutes, 1)
    }
}
