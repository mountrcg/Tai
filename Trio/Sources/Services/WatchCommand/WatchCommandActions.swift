import Foundation
import Swinject

/// Pump and Core Data side effects of watch commands, behind a protocol so validation and
/// sequencing can be tested without a pump.
protocol WatchCommandActions {
    /// Throws unless the carb row was saved. `authorize` runs inside the save transaction; whatever
    /// it throws is rethrown with nothing written.
    func storeCarbs(_ grams: Int, date: Date, authorize: @escaping () throws -> Void) async throws
    /// Returns once the pump accepted or refused the bolus. Throws only what `authorize` threw,
    /// right before issuance; nothing reached the pump then.
    func enactBolus(_ units: Decimal, authorize: @escaping () throws -> Void) async throws -> Bool
}

final class BaseWatchCommandActions: WatchCommandActions, Injectable {
    @Injected() private var apsManager: APSManager!
    @Injected() private var carbsStorage: CarbsStorage!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storeCarbs(_ grams: Int, date: Date, authorize: @escaping () throws -> Void) async throws {
        let entry = CarbsEntry(
            id: UUID().uuidString,
            createdAt: date,
            actualDate: date,
            carbs: Decimal(grams),
            fat: 0,
            protein: 0,
            note: String(localized: "Via Watch", comment: "Note added to carb entry when entered via watch"),
            enteredBy: CarbsEntry.local,
            isFPU: false,
            fpuID: nil
        )
        try await carbsStorage.storeVerifiedCarbs(entry, authorize: authorize)
    }

    /// `authorize` runs in the task that issues the request, right before `APSManager.enactBolus` with
    /// nothing awaited in between; the task lets the ack return before the follow-up loop run.
    func enactBolus(_ units: Decimal, authorize: @escaping () throws -> Void) async throws -> Bool {
        // enactBolus never calls back for non-positive amounts, which would never resume
        guard units > 0, let apsManager = self.apsManager else { return false }
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    try authorize()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                await apsManager.enactBolus(amount: Double(truncating: units as NSNumber), isSMB: false) { success, _ in
                    continuation.resume(returning: success)
                }
            }
        }
    }
}
