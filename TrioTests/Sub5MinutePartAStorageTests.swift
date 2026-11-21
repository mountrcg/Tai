import CoreData
import Swinject
@testable import Trio
import XCTest

final class Sub5MinutePartAStorageTests: XCTestCase {
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
}
