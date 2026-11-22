import CoreData
@testable import Trio
import XCTest

final class Sub5MinutePartAMigrationTests: XCTestCase {
    func testOldStoreMigratesWithoutInventingProvenance() throws {
        let bundle = Bundle(for: GlucoseStored.self)
        let directory = try XCTUnwrap(bundle.url(forResource: "TrioCoreDataPersistentContainer", withExtension: "momd"))
        let oldModel =
            try XCTUnwrap(NSManagedObjectModel(
                contentsOf: directory
                    .appendingPathComponent("TrioCoreDataPersistentContainer.mom")
            ))
        let newModel = try XCTUnwrap(NSManagedObjectModel(contentsOf: directory.appendingPathComponent("Sub5MinuteGlucose.mom")))
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let url = temporary.appendingPathComponent("migration.sqlite")
        let oldCoordinator = NSPersistentStoreCoordinator(managedObjectModel: oldModel)
        let oldStore = try oldCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = oldCoordinator
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try context.performAndWait {
            let row = NSEntityDescription.insertNewObject(forEntityName: "GlucoseStored", into: context)
            row.setValue(id, forKey: "id")
            row.setValue(date, forKey: "date")
            row.setValue(123, forKey: "glucose")
            try context.save()
            context.reset()
        }
        try oldCoordinator.remove(oldStore)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: newModel)
        let store = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType, configurationName: nil, at: url,
            options: [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true]
        )
        defer { try? coordinator.remove(store) }
        let migrated = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        migrated.persistentStoreCoordinator = coordinator
        try migrated.performAndWait {
            let rows = try migrated.fetch(GlucoseStored.fetchRequest())
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows[0].id, id)
            XCTAssertEqual(rows[0].date, date)
            XCTAssertEqual(rows[0].glucose, 123)
            XCTAssertNil(rows[0].sourceIdentifier)
            XCTAssertNil(rows[0].observationEpochID)
        }
    }
}
