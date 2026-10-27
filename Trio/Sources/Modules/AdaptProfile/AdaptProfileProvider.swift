import CoreData
import Foundation
import LoopKit

extension AdaptProfile {
    final class Provider: BaseProvider, AdaptProfileProvider {
        @Injected() private var apsManager: APSManager!
        @Injected() private var settingsManager: SettingsManager!
        private let coreDataStack = CoreDataStack.shared

        func fetchAll() async -> [AdaptProfileListItem] {
            let context = coreDataStack.newTaskContext()
            return await context.perform {
                let request: NSFetchRequest<ProfileStored> = ProfileStored.fetchRequest()
                request.sortDescriptors = [
                    NSSortDescriptor(key: "orderPosition", ascending: true),
                    NSSortDescriptor(key: "createdAt", ascending: false)
                ]
                do {
                    let rows = try context.fetch(request)
                    // Build a lookup of id → (name, preferences, bgTargets) so each row can
                    // reference its source profile without triggering repeated fetches.
                    struct SourceSnapshot {
                        let name: String
                        let preferences: Preferences?
                        let bgTargets: BGTargets?
                    }
                    let byID: [UUID: SourceSnapshot] = rows.reduce(into: [:]) { dict, p in
                        guard let id = p.id else { return }
                        dict[id] = SourceSnapshot(
                            name: p.name ?? "",
                            preferences: p.preferences,
                            bgTargets: p.therapy?.bgTargets
                        )
                    }

                    return rows.compactMap { profile -> AdaptProfileListItem? in
                        guard let id = profile.id else { return nil }
                        let source = profile.sourceProfileID.flatMap { byID[$0] }
                        let profilePrefs = profile.preferences
                        let profileTargets = profile.therapy?.bgTargets

                        let prefsChanged: Bool = {
                            guard let source = source,
                                  let sp = source.preferences,
                                  var a = profilePrefs
                            else { return false }
                            // `Preferences.timestamp` is metadata (last-written marker) and drifts
                            // independently of user-tunable fields; strip it before comparing so a
                            // pure %-scaled copy that didn't touch any algorithm toggle doesn't
                            // read as "Algorithm Settings tuned" just because of timestamp skew.
                            var b = sp
                            a.timestamp = nil
                            b.timestamp = nil
                            return a != b
                        }()
                        let targetsChanged: Bool = {
                            guard let source = source, let st = source.bgTargets else { return false }
                            return profileTargets?.targets != st.targets
                        }()

                        let applied = profile.appliedPercent?.decimalValue ?? 100
                        let totalBasal = profile.therapy?.totalDailyBasal ?? 0
                        return AdaptProfileListItem(
                            id: id,
                            name: profile.name ?? "",
                            createdAt: profile.createdAt ?? .distantPast,
                            isActive: profile.isActive,
                            expiresAt: profile.expiresAt,
                            orderPosition: profile.orderPosition,
                            sourceProfileName: source?.name,
                            appliedPercent: applied,
                            preferencesChangedFromSource: prefsChanged,
                            targetsChangedFromSource: targetsChanged,
                            previousProfileID: profile.previousProfileID,
                            totalDailyBasal: totalBasal
                        )
                    }
                } catch {
                    warning(.storage, "Fetching profiles failed", error: error)
                    return []
                }
            }
        }

        func fetchUpcoming() async -> [UpcomingScheduleItem] {
            let context = coreDataStack.newTaskContext()
            return await context.perform {
                let profiles = (try? context.fetch(ProfileStored.fetchRequest())) ?? []
                let nameByID: [UUID: String] = profiles.reduce(into: [:]) { dict, p in
                    if let id = p.id { dict[id] = p.name ?? "" }
                }

                let request = ProfileScheduleStored.fetch(.enabledSchedule, ascending: true)
                let rows = (try? context.fetch(request)) ?? []
                let now = Date()

                return rows.compactMap { s -> UpcomingScheduleItem? in
                    guard let id = s.id,
                          let profileID = s.profileID,
                          let rule = s.rule,
                          let duration = s.duration,
                          let next = rule.nextFire(after: now)
                    else { return nil }
                    let profileName = nameByID[profileID] ?? String(
                        localized: "Profile missing",
                        comment: "Upcoming-schedule row shown when the target profile has been deleted"
                    )
                    return UpcomingScheduleItem(
                        id: id,
                        nextFire: next,
                        duration: duration,
                        profileName: profileName,
                        profileExists: nameByID[profileID] != nil
                    )
                }
                .sorted { $0.nextFire < $1.nextFire }
            }
        }

        func disableSchedule(id: UUID) async {
            let context = coreDataStack.newTaskContext()
            await context.perform {
                let request = ProfileScheduleStored.fetch(.scheduleByID(id), fetchLimit: 1)
                guard let row = (try? context.fetch(request))?.first else { return }
                row.enabled = false
                try? context.save()
            }
        }

        func earliestPendingScheduledActivation() async -> ScheduledActivationRequest? {
            let context = coreDataStack.newTaskContext()
            return await context.perform {
                let request: NSFetchRequest<ProfileScheduleStored> = ProfileScheduleStored.fetchRequest()
                request.predicate = NSPredicate(format: "pendingOccurrence != nil AND enabled == %@", true as NSNumber)
                request.sortDescriptors = [NSSortDescriptor(key: "pendingOccurrence", ascending: true)]
                request.fetchLimit = 1
                guard let row = (try? context.fetch(request))?.first,
                      let sid = row.id,
                      let pid = row.profileID,
                      let occurrence = row.pendingOccurrence
                else { return nil }

                let profileReq = ProfileStored.fetch(.profileByID(pid), fetchLimit: 1)
                let name = (try? context.fetch(profileReq))?.first?.name ?? String(
                    localized: "Scheduled profile",
                    comment: "Fallback profile name used in the pending-activation pump-save alert when the scheduled profile can't be resolved by id"
                )
                return ScheduledActivationRequest(
                    scheduleID: sid,
                    profileID: pid,
                    profileName: name,
                    occurrence: occurrence
                )
            }
        }

        func markScheduleActivated(scheduleID: UUID, occurrence: Date) async {
            let context = coreDataStack.newTaskContext()
            await context.perform {
                let request = ProfileScheduleStored.fetch(.scheduleByID(scheduleID), fetchLimit: 1)
                guard let row = (try? context.fetch(request))?.first else { return }
                if case .once = row.rule?.repeatRule {
                    // One-off schedules cannot fire again; delete rather than leave a stamped row.
                    context.delete(row)
                } else {
                    row.lastFiredAt = occurrence
                    row.pendingOccurrence = nil
                }
                try? context.save()
            }
        }

        func applyOrdering(_ orderedIDs: [UUID]) async {
            let context = coreDataStack.newTaskContext()
            await context.perform {
                do {
                    let request: NSFetchRequest<ProfileStored> = ProfileStored.fetchRequest()
                    request.predicate = NSPredicate(format: "id IN %@", orderedIDs)
                    let rows = try context.fetch(request)
                    let byID = Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (UUID, ProfileStored)? in
                        guard let id = row.id else { return nil }
                        return (id, row)
                    })
                    for (index, id) in orderedIDs.enumerated() {
                        byID[id]?.orderPosition = Int16(index + 1)
                    }
                    if context.hasChanges {
                        try context.save()
                    }
                } catch {
                    warning(.storage, "Saving profile order failed", error: error)
                }
            }
        }

        func rename(id: UUID, to newName: String) async {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let context = coreDataStack.newTaskContext()
            await context.perform {
                do {
                    let request = ProfileStored.fetch(.profileByID(id), fetchLimit: 1)
                    guard let profile = try context.fetch(request).first else { return }
                    profile.name = trimmed
                    try context.save()
                } catch {
                    warning(.storage, "Renaming profile failed", error: error)
                }
            }
        }

        func delete(id: UUID) async {
            let context = coreDataStack.newTaskContext()
            await context.perform {
                do {
                    let request = ProfileStored.fetch(.profileByID(id), fetchLimit: 1)
                    guard let profile = try context.fetch(request).first else { return }
                    if profile.isActive {
                        warning(.settings, "Active profile cannot be deleted")
                        return
                    }
                    // Cascade: any ProfileScheduleStored referencing this profile loses its target
                    // and would otherwise show as "Profile missing" forever. Delete them here.
                    let schedReq = ProfileScheduleStored.fetch(.schedulesForProfile(id))
                    let orphanedSchedules = (try? context.fetch(schedReq)) ?? []
                    for schedule in orphanedSchedules {
                        context.delete(schedule)
                    }
                    if !orphanedSchedules.isEmpty {
                        info(.settings, "Deleted profile removed \(orphanedSchedules.count) profile schedules")
                    }
                    context.delete(profile)
                    try context.save()
                    if !orphanedSchedules.isEmpty {
                        Task { @MainActor in
                            Foundation.NotificationCenter.default.post(
                                name: .didUpdateProfileSchedules,
                                object: nil
                            )
                        }
                    }
                } catch {
                    warning(.storage, "Deleting profile failed", error: error)
                }
            }
        }

        var supportedBasalRates: [Decimal]? {
            deviceManager.pumpManager?.supportedBasalRates.map { Decimal($0).rounded(scale: 3) }
        }

        func activate(
            id: UUID,
            durationMinutes: Int?,
            confirmedPumpSync: Bool,
            skipPumpSync: Bool = false
        ) async -> ActivationOutcome {
            let context = coreDataStack.newTaskContext()
            context.name = "AdaptProfileActivateContext"
            context.transactionAuthor = "AdaptProfileActivate"

            // Step 1: load target profile's decoded snapshot + active-profile metadata (all on the
            // context queue — we don't carry the NSManagedObject outside).
            let loaded: (
                preferences: Preferences,
                therapy: TherapyBundle,
                oldActiveID: UUID?,
                oldAnchorID: UUID?
            )? = await context.perform { () -> (Preferences, TherapyBundle, UUID?, UUID?)? in
                let req = ProfileStored.fetch(.profileByID(id), fetchLimit: 1)
                guard let target = try? context.fetch(req).first,
                      let prefs = target.preferences,
                      let therapy = target.therapy
                else {
                    return nil
                }
                let activeReq = ProfileStored.fetch(.activeProfile, fetchLimit: 1)
                let oldActive = try? context.fetch(activeReq).first
                return (prefs, therapy, oldActive?.id, oldActive?.previousProfileID)
            }

            guard let loaded = loaded else {
                return .failed(String(
                    localized: "Profile not found.",
                    comment: "Error returned when activating a profile whose Core Data record can't be loaded"
                ))
            }

            // Step 2: pump-sync decision. Only indefinite activations that would change the basal
            // schedule require a pump write; timed activations keep the pump schedule untouched.
            // Revert paths pass `skipPumpSync: true` because the anchor invariant guarantees the
            // pump already holds the target's basal — see Step 4 anchor rule and the doc comments
            // on `revertActiveProfile()` / `checkExpiredProfileAndAutoRevert()`. The basal-diff
            // comparison is short-circuited away in that case.
            let isIndefinite = (durationMinutes == nil)
            let needsPumpSync = !skipPumpSync
                && isIndefinite
                && scope.basalProfile != loaded.therapy.basalProfile

            if needsPumpSync, !confirmedPumpSync {
                return .needsPumpConfirm
            }

            // Step 3: pump sync (indefinite + basal changed + user confirmed).
            if needsPumpSync {
                guard let pump = deviceManager?.pumpManager else {
                    return .pumpSyncFailed(String(
                        localized: "No pump manager available.",
                        comment: "Pump-sync failure shown when activating a profile but no pump is paired"
                    ))
                }
                let concentration = settingsManager.settings.insulinConcentration
                let syncValues = loaded.therapy.basalProfile.map {
                    RepeatingScheduleValue(
                        startTime: TimeInterval($0.minutes * 60),
                        value: Double($0.rate) / Double(concentration)
                    )
                }
                do {
                    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                        pump.syncBasalRateSchedule(items: syncValues) { result in
                            switch result {
                            case .success: cont.resume()
                            case let .failure(error): cont.resume(throwing: error)
                            }
                        }
                    }
                } catch {
                    return .pumpSyncFailed(error.localizedDescription)
                }
            }

            // Step 4: flip Core Data on the VIEW context so SwiftUI `@FetchRequest` consumers
            // (Home's active-profile banner) pick up the change immediately. A background
            // context save would require a subsequent merge — viewContext has
            // `automaticallyMergesChangesFromParent = false` so @FetchRequest would stay stale
            // until persistent-history notifications caught up, which is why the Home banner
            // showed the previous profile until the next loop tick.
            let viewContext = coreDataStack.persistentContainer.viewContext
            let flipped: Bool = await viewContext.perform { () -> Bool in
                do {
                    let activeReq = ProfileStored.fetch(.activeProfile)
                    let actives = try viewContext.fetch(activeReq)
                    let now = Date()
                    for p in actives where p.id != id {
                        if let startedAt = p.activatedAt {
                            let run = ProfileRunStored(context: viewContext)
                            run.id = UUID()
                            run.name = p.name
                            run.startDate = startedAt
                            run.endDate = now
                            run.isUploadedToNS = false
                            run.wasIndefinite = p.expiresAt == nil
                            let tuned = Self.computeTunedFlags(for: p, in: viewContext)
                            run.preferencesTuned = tuned.prefs
                            run.targetsTuned = tuned.targets
                            run.profile = p
                        }
                        p.isActive = false
                        p.activatedAt = nil
                        p.expiresAt = nil
                    }
                    let targetReq = ProfileStored.fetch(.profileByID(id), fetchLimit: 1)
                    guard let target = try viewContext.fetch(targetReq).first else { return false }
                    target.isActive = true
                    target.activatedAt = Date()
                    target.expiresAt = durationMinutes.map { Date().addingTimeInterval(TimeInterval($0) * 60) }
                    // Anchor rule: indefinite activations clear previousProfileID (this profile
                    // is now the pump baseline). Timed activations inherit the outgoing profile's
                    // anchor, or fall back to the outgoing profile's id if it didn't have one.
                    // This guarantees reverting/stopping any temp always returns to the profile
                    // whose basal is on the pump — chains of temps can't sneak unfamiliar basal
                    // onto the pump.
                    if isIndefinite {
                        target.previousProfileID = nil
                    } else {
                        target.previousProfileID = loaded.oldAnchorID ?? loaded.oldActiveID
                    }
                    try viewContext.save()
                    return true
                } catch {
                    warning(.storage, "Saving active profile failed", error: error)
                    return false
                }
            }

            guard flipped else {
                return .failed(String(
                    localized: "Failed to update profile state.",
                    comment: "Error returned when the Core Data flip marking a profile active could not be saved"
                ))
            }

            // Step 5: write live settings. Order: preferences first, then therapy. The mirror will
            // re-write the same data into the now-active profile — harmless no-op.
            scope.preferences = loaded.preferences
            scope.basalProfile = loaded.therapy.basalProfile
            scope.sensitivities = loaded.therapy.sensitivities
            scope.carbRatios = loaded.therapy.carbRatios
            scope.bgTargets = loaded.therapy.bgTargets

            // Step 6: trigger a loop iteration so the algorithm picks up the new profile.
            do {
                try await apsManager.determineBasalSync()
            } catch {
                warning(.loop, "Loop run after profile activation failed", error: error)
                // non-fatal — activation itself succeeded
            }

            return .success
        }

        func updateProfile(
            id: UUID,
            name: String,
            preferences: Preferences,
            therapy: TherapyBundle,
            sourceProfileID: UUID?,
            appliedPercent: Decimal
        ) async -> Bool {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            let context = coreDataStack.newTaskContext()
            context.name = "AdaptProfileUpdateContext"
            return await context.perform {
                do {
                    let req = ProfileStored.fetch(.profileByID(id), fetchLimit: 1)
                    guard let profile = try context.fetch(req).first else { return false }
                    profile.name = trimmed
                    profile.preferences = preferences
                    profile.therapy = therapy
                    profile.sourceProfileID = sourceProfileID
                    profile.appliedPercent = NSDecimalNumber(decimal: appliedPercent)
                    try context.save()
                    return true
                } catch {
                    warning(.storage, "Updating profile failed", error: error)
                    return false
                }
            }
        }

        func loadProfileContent(id: UUID) async -> LoadedProfileContent? {
            let context = coreDataStack.newTaskContext()
            return await context.perform { () -> LoadedProfileContent? in
                let req = ProfileStored.fetch(.profileByID(id), fetchLimit: 1)
                guard let profile = try? context.fetch(req).first,
                      let profileID = profile.id,
                      let prefs = profile.preferences,
                      let therapy = profile.therapy
                else { return nil }

                var sourceName: String?
                if let sourceID = profile.sourceProfileID {
                    let srcReq = ProfileStored.fetch(.profileByID(sourceID), fetchLimit: 1)
                    sourceName = (try? context.fetch(srcReq).first)?.name
                }

                return LoadedProfileContent(
                    id: profileID,
                    name: profile.name ?? "",
                    preferences: prefs,
                    therapy: therapy,
                    sourceProfileID: profile.sourceProfileID,
                    sourceProfileName: sourceName,
                    appliedPercent: profile.appliedPercent?.decimalValue ?? 100
                )
            }
        }

        func saveNewProfile(
            name: String,
            preferences: Preferences,
            therapy: TherapyBundle,
            sourceProfileID: UUID?,
            appliedPercent: Decimal
        ) async -> UUID? {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let context = coreDataStack.newTaskContext()
            return await context.perform { () -> UUID? in
                do {
                    let request: NSFetchRequest<ProfileStored> = ProfileStored.fetchRequest()
                    request.sortDescriptors = [NSSortDescriptor(key: "orderPosition", ascending: false)]
                    request.fetchLimit = 1
                    let maxOrder = (try? context.fetch(request).first?.orderPosition) ?? 0

                    let newID = UUID()
                    let profile = ProfileStored(context: context)
                    profile.id = newID
                    profile.name = trimmed
                    profile.createdAt = Date()
                    profile.isActive = false
                    profile.activatedAt = nil
                    profile.expiresAt = nil
                    profile.previousProfileID = nil
                    profile.orderPosition = maxOrder + 1
                    profile.sourceProfileID = sourceProfileID
                    profile.appliedPercent = NSDecimalNumber(decimal: appliedPercent)
                    profile.preferences = preferences
                    profile.therapy = therapy
                    try context.save()
                    return newID
                } catch {
                    warning(.storage, "Saving new profile failed", error: error)
                    return nil
                }
            }
        }

        /// Snapshot whether this profile's preferences / glucose targets diverge from its
        /// source profile — used to freeze the "Algo / Targets tuned" indicator on run-history
        /// rows so later edits to the source don't retroactively change how past runs read.
        static func computeTunedFlags(
            for profile: ProfileStored,
            in context: NSManagedObjectContext
        ) -> (prefs: Bool, targets: Bool) {
            guard let sourceID = profile.sourceProfileID else { return (false, false) }
            let req = ProfileStored.fetch(.profileByID(sourceID), fetchLimit: 1)
            guard let source = try? context.fetch(req).first else { return (false, false) }
            let prefs: Bool = {
                guard let sp = source.preferences, let pp = profile.preferences else { return false }
                return pp != sp
            }()
            let targets: Bool = {
                guard let st = source.therapy?.bgTargets, let pt = profile.therapy?.bgTargets else { return false }
                return pt.targets != st.targets
            }()
            return (prefs, targets)
        }
    }
}
