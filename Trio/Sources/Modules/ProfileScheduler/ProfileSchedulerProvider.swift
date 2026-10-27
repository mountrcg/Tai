import CoreData
import Foundation

extension ProfileScheduler {
    final class Provider: BaseProvider, ProfileSchedulerProvider {
        private let coreDataStack = CoreDataStack.shared

        func fetchAllSchedules() async -> [ProfileScheduleListItem] {
            let context = coreDataStack.newTaskContext()
            return await context.perform {
                // Fetch all profile names first so each schedule row can carry its profile label.
                let profiles = (try? context.fetch(ProfileStored.fetchRequest())) ?? []
                let nameByID: [UUID: String] = profiles.reduce(into: [:]) { dict, p in
                    if let id = p.id { dict[id] = p.name ?? "" }
                }

                let request: NSFetchRequest<ProfileScheduleStored> = ProfileScheduleStored.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
                let rows = (try? context.fetch(request)) ?? []
                let now = Date()

                let items: [ProfileScheduleListItem] = rows.compactMap { s in
                    guard let id = s.id,
                          let profileID = s.profileID,
                          let rule = s.rule,
                          let duration = s.duration
                    else { return nil }
                    return ProfileScheduleListItem(
                        id: id,
                        profileID: profileID,
                        profileName: nameByID[profileID] ?? String(
                            localized: "Missing profile",
                            comment: "Schedule list row shown when the schedule's target profile has been deleted"
                        ),
                        repeatRule: rule.repeatRule,
                        firesAt: rule.firesAt,
                        duration: duration,
                        enabled: s.enabled,
                        createdAt: s.createdAt ?? .distantPast,
                        nextFire: s.enabled ? rule.nextFire(after: now) : nil
                    )
                }

                // Auto-sort: enabled rows first, ascending by next fire. Disabled rows sink to the
                // bottom, ordered by most-recently-created first (their createdAt from the fetch
                // sort above).
                return items.sorted { a, b in
                    if a.enabled != b.enabled { return a.enabled && !b.enabled }
                    if a.enabled {
                        let aNext = a.nextFire ?? .distantFuture
                        let bNext = b.nextFire ?? .distantFuture
                        if aNext != bNext { return aNext < bNext }
                    }
                    return a.createdAt > b.createdAt
                }
            }
        }

        func fetchProfiles() async -> [ProfilePickerChoice] {
            let context = coreDataStack.newTaskContext()
            return await context.perform {
                let request: NSFetchRequest<ProfileStored> = ProfileStored.fetchRequest()
                request.sortDescriptors = [
                    NSSortDescriptor(key: "orderPosition", ascending: true),
                    NSSortDescriptor(key: "createdAt", ascending: false)
                ]
                let rows = (try? context.fetch(request)) ?? []
                return rows.compactMap { p -> ProfilePickerChoice? in
                    guard let id = p.id else { return nil }
                    return ProfilePickerChoice(id: id, name: p.name ?? "", isActive: p.isActive)
                }
            }
        }

        func saveNewSchedule(_ draft: ProfileScheduleDraft) async -> UUID? {
            guard let profileID = draft.profileID else { return nil }
            let context = coreDataStack.newTaskContext()
            return await context.perform {
                let entity = ProfileScheduleStored(context: context)
                let id = UUID()
                entity.id = id
                entity.profileID = profileID
                entity.name = draft.name.isEmpty ? nil : draft.name
                entity.enabled = true
                entity.createdAt = Date()
                entity.repeatRule = draft.repeatRule
                entity.firesAt = draft.firesAt
                entity.duration = draft.duration
                do {
                    try context.save()
                    return id
                } catch {
                    warning(.storage, "Saving new profile schedule failed", error: error)
                    return nil
                }
            }
        }

        func setEnabled(id: UUID, enabled: Bool) async {
            let context = coreDataStack.newTaskContext()
            await context.perform {
                let request = ProfileScheduleStored.fetch(.scheduleByID(id), fetchLimit: 1)
                guard let row = (try? context.fetch(request))?.first else { return }
                row.enabled = enabled
                try? context.save()
            }
        }

        func deleteSchedule(id: UUID) async {
            let context = coreDataStack.newTaskContext()
            await context.perform {
                let request = ProfileScheduleStored.fetch(.scheduleByID(id), fetchLimit: 1)
                guard let row = (try? context.fetch(request))?.first else { return }
                context.delete(row)
                try? context.save()
            }
        }
    }
}
