import CoreData
import Foundation
import UserNotifications

/// Re-entrancy guard: `activate()` can take a couple of seconds (pump sync paths
/// and Core Data writes), and the timer fires every 5s. Without a flag a slow
/// activate could overlap with the next tick's check.
@MainActor private var profileExpirationSweepInFlight: Bool = false

extension Home.StateModel {
    /// Auto-expiration sweep for the active timed profile, run on the 5-second
    /// `timerDate` tick. Mirrors how Override / TempTarget chips refresh:
    /// the tick re-renders the Home adjustment area AND gives us a hook to
    /// flip Core Data state so the `@FetchRequest` for `activeProfile` stops
    /// returning a stale row.
    ///
    /// If the active profile's `expiresAt` has passed:
    ///  - With an anchor (`previousProfileID`): re-activate it indefinitely via
    ///    `AdaptProfile.Provider.activate` with `skipPumpSync: true`. The anchor
    ///    is, by construction, the last indefinite profile (its basal is already
    ///    on the pump), so a pump write would be redundant — same contract as
    ///    `revertActiveProfile()`.
    ///  - Without an anchor: clear `isActive` / `expiresAt` in place. No pump
    ///    write (timed activations never touched the pump anyway).
    @MainActor func checkExpiredProfileAndAutoRevert() async {
        guard !profileExpirationSweepInFlight else { return }
        guard let resolver = resolver else { return }
        profileExpirationSweepInFlight = true
        defer { profileExpirationSweepInFlight = false }

        let context = CoreDataStack.shared.newTaskContext()

        struct Expired {
            let objectID: NSManagedObjectID
            let name: String
            let previousID: UUID?
            let previousName: String?
        }

        let expired: Expired? = await context.perform {
            let req = ProfileStored.fetchRequest()
            req.predicate = NSPredicate(format: "isActive == %@", true as NSNumber)
            req.fetchLimit = 1
            guard let active = try? context.fetch(req).first,
                  let expiresAt = active.expiresAt,
                  expiresAt <= Date()
            else { return nil }
            let previousName: String? = {
                guard let pid = active.previousProfileID else { return nil }
                let anchorReq = ProfileStored.fetchRequest()
                anchorReq.predicate = NSPredicate(format: "id == %@", pid as CVarArg)
                anchorReq.fetchLimit = 1
                return (try? context.fetch(anchorReq).first)?.name
            }()
            return Expired(
                objectID: active.objectID,
                name: active.name ?? "",
                previousID: active.previousProfileID,
                previousName: previousName
            )
        }
        guard let expired = expired else { return }

        if let previousID = expired.previousID {
            let provider = AdaptProfile.Provider(resolver: resolver)
            _ = await provider.activate(
                id: previousID,
                durationMinutes: nil,
                confirmedPumpSync: true,
                skipPumpSync: true
            )
            postRevertedNotification(expiredName: expired.name, anchorName: expired.previousName ?? "")
            return
        }

        // No anchor — just deactivate in place so the chip stops showing.
        await context.perform {
            guard let profile = try? context.existingObject(with: expired.objectID) as? ProfileStored else { return }
            if let startedAt = profile.activatedAt {
                let run = ProfileRunStored(context: context)
                run.id = UUID()
                run.name = profile.name
                run.startDate = startedAt
                run.endDate = Date()
                run.isUploadedToNS = false
                run.wasIndefinite = false
                let tuned = AdaptProfile.Provider.computeTunedFlags(for: profile, in: context)
                run.preferencesTuned = tuned.prefs
                run.targetsTuned = tuned.targets
                run.profile = profile
            }
            profile.isActive = false
            profile.activatedAt = nil
            profile.expiresAt = nil
            try? context.save()
        }
    }
}

@MainActor private func postRevertedNotification(expiredName: String, anchorName: String) {
    let content = UNMutableNotificationContent()
    content.title = String(
        localized: "Profile \"\(expiredName)\" expired",
        comment: "Title of profile-expired notification — interpolated value is the expiring profile's name"
    )
    content.body = String(
        localized: "Reverted to \"\(anchorName)\".",
        comment: "Body of profile-expired notification — interpolated value is the anchor profile name we reverted to"
    )
    content.sound = .default
    content.categoryIdentifier = NotificationCategoryIdentifier.profileReverted.rawValue
    let request = UNNotificationRequest(
        identifier: "Trio.profile.reverted.\(expiredName).\(Int(Date().timeIntervalSince1970))",
        content: content,
        trigger: nil
    )
    UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
            warning(.alerts, "Posting profile reverted notification failed", error: error)
        } else {
            debug(.alerts, "Profile reverted notification queued")
        }
    }
}
