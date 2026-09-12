import CoreData
import Foundation

/// Shared scheduling backend for Shortcut-driven Temp Targets.
///
/// Both `CreateCustomTempTargetIntent` (custom input) and
/// `ApplyTempPresetIntent` (preset values cloned into a custom-shaped row)
/// route their scheduled path through `enact`. The behavior matches the
/// post-persist half of `Adjustments.StateModel.saveScheduledTempTarget`:
///
/// 1. Persist a new (non-preset) row with `enabled = false`,
///    `createdAt = startTime`.
/// 2. Detach a task that sleeps until `startTime`, disables any actives,
///    flips the scheduled row to `enabled = true`, and pushes JSON for oref.
///
/// The detached task runs in the Trio app process for the same lifetime an
/// in-app Add-TT submission would.
@MainActor enum ScheduledTempTargetHelper {
    /// Persist a scheduled custom-shaped Temp Target and detach the
    /// wait+activate task. Returns `false` if persistence fails.
    static func enact(
        name: String,
        targetMgdl: Decimal,
        durationMinutes: Decimal,
        halfBasalTarget: Decimal?,
        startTime: Date,
        tempTargetsStorage: TempTargetsStorage,
        viewContext: NSManagedObjectContext
    ) async -> Bool {
        let scheduledTT = makeTempTarget(
            name: name,
            createdAt: startTime,
            targetMgdl: targetMgdl,
            durationMinutes: durationMinutes,
            halfBasalTarget: halfBasalTarget,
            enabled: false
        )
        do {
            try await tempTargetsStorage.storeTempTarget(tempTarget: scheduledTT)
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to store scheduled TempTarget: \(error)"
            )
            return false
        }

        // Nudge Adjustments to refresh its scheduled-TT list immediately
        // (otherwise the user only sees the row after switching tabs).
        Foundation.NotificationCenter.default.post(
            name: .willUpdateTempTargetConfiguration,
            object: nil
        )

        // Detached — survives the intent's perform().
        Task.detached {
            await waitUntilDate(startTime)
            await activate(
                name: name,
                targetMgdl: targetMgdl,
                durationMinutes: durationMinutes,
                halfBasalTarget: halfBasalTarget,
                startTime: startTime,
                tempTargetsStorage: tempTargetsStorage,
                viewContext: viewContext
            )
        }
        return true
    }

    /// Disable any currently active TempTargetStored rows (creates a
    /// `TempTargetRunStored` audit entry for the first one) and write a
    /// cancel marker to JSON for oref. Shared with the immediate path.
    static func disableAllActiveTempTargets(
        tempTargetsStorage: TempTargetsStorage,
        viewContext: NSManagedObjectContext
    ) async {
        do {
            let ids = try await tempTargetsStorage.loadLatestTempTargetConfigurations(fetchLimit: 0)
            let results = try ids.compactMap {
                try viewContext.existingObject(with: $0) as? TempTargetStored
            }
            guard !results.isEmpty else { return }

            if let canceled = results.first {
                let run = TempTargetRunStored(context: viewContext)
                run.id = UUID()
                run.name = canceled.name
                run.startDate = canceled.date ?? .distantPast
                run.endDate = Date()
                run.target = canceled.target ?? 0
                run.tempTarget = canceled
                run.isUploadedToNS = false
            }
            for tt in results {
                tt.enabled = false
                tt.isUploadedToNS = false
            }

            if viewContext.hasChanges {
                try viewContext.save()
                Foundation.NotificationCenter.default.post(
                    name: .willUpdateTempTargetConfiguration,
                    object: nil
                )
                tempTargetsStorage.saveTempTargetsToStorage(
                    [TempTarget.cancel(at: Date().addingTimeInterval(-1))]
                )
                await awaitNotification(.didUpdateTempTargetConfiguration)
            }
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to disable active TempTargets: \(error)"
            )
        }
    }

    // MARK: - Internals

    @MainActor private static func activate(
        name: String,
        targetMgdl: Decimal,
        durationMinutes: Decimal,
        halfBasalTarget: Decimal?,
        startTime: Date,
        tempTargetsStorage: TempTargetsStorage,
        viewContext: NSManagedObjectContext
    ) async {
        await disableAllActiveTempTargets(
            tempTargetsStorage: tempTargetsStorage,
            viewContext: viewContext
        )
        do {
            let ids = try await tempTargetsStorage.fetchScheduledTempTarget(for: startTime)
            guard let firstID = ids.first,
                  let row = try viewContext.existingObject(with: firstID) as? TempTargetStored
            else {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Scheduled TempTarget not found for \(startTime)"
                )
                return
            }
            row.enabled = true
            row.isUploadedToNS = false
            if viewContext.hasChanges {
                try viewContext.save()
            }
            let liveTT = makeTempTarget(
                name: name,
                createdAt: startTime,
                targetMgdl: targetMgdl,
                durationMinutes: durationMinutes,
                halfBasalTarget: halfBasalTarget,
                enabled: true
            )
            tempTargetsStorage.saveTempTargetsToStorage([liveTT])
            Foundation.NotificationCenter.default.post(
                name: .willUpdateTempTargetConfiguration,
                object: nil
            )
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to activate scheduled TempTarget: \(error)"
            )
        }
    }

    private static func makeTempTarget(
        name: String,
        createdAt: Date,
        targetMgdl: Decimal,
        durationMinutes: Decimal,
        halfBasalTarget: Decimal?,
        enabled: Bool
    ) -> TempTarget {
        TempTarget(
            name: name,
            createdAt: createdAt,
            targetTop: targetMgdl,
            targetBottom: targetMgdl,
            duration: durationMinutes,
            enteredBy: TempTarget.local,
            reason: TempTarget.custom,
            isPreset: false,
            enabled: enabled,
            halfBasalTarget: halfBasalTarget
        )
    }

    /// Sleep until `targetDate`. Mirrors `Adjustments.StateModel.waitUntilDate`.
    private static func waitUntilDate(_ targetDate: Date) async {
        while Date() < targetDate {
            let delta = targetDate.timeIntervalSince(Date())
            let sleepSeconds = min(delta, 60.0)
            try? await Task.sleep(nanoseconds: UInt64(sleepSeconds * 1_000_000_000))
        }
    }
}
