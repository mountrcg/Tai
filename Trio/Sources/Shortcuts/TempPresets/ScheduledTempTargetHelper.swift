import CoreData
import Foundation

/// Shared scheduling backend for Shortcut-driven Temp Targets.
///
/// Both `CreateCustomTempTargetIntent` (custom input) and
/// `ApplyTempPresetIntent` (preset values cloned into a custom-shaped row)
/// route their scheduled path through `enact`.
///
/// 1. Persist a new (non-preset), disabled row with `createdAt = startTime`.
/// 2. Detach a task that sleeps until `startTime`, then hands the row's
///    `NSManagedObjectID` to `AdjustmentManager.activateTempTarget`, which
///    ends whatever else is running and enables this row in one transaction.
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
        adjustmentManager: AdjustmentManager
    ) async -> Bool {
        let scheduledTT = TempTarget(
            name: name,
            createdAt: startTime,
            targetTop: targetMgdl,
            targetBottom: targetMgdl,
            duration: durationMinutes,
            enteredBy: TempTarget.local,
            reason: TempTarget.custom,
            isPreset: false,
            enabled: false,
            halfBasalTarget: halfBasalTarget
        )

        let objectID: NSManagedObjectID
        do {
            objectID = try await tempTargetsStorage.storeTempTarget(tempTarget: scheduledTT)
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
            do {
                try await adjustmentManager.activateTempTarget(
                    .objectID(objectID),
                    source: .shortcut,
                    waitForUpload: false
                )
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Failed to activate scheduled TempTarget: \(error)"
                )
            }
        }
        return true
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
