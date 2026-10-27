import CoreData
import Foundation

/// Seeds an implicit "Default Profile" `ProfileStored` from the current live settings on first launch.
///
/// Runs once after Core Data is ready. If any profile already exists, no-op (apart from a one-shot
/// rename of the legacy "Default" seed). The seeded profile is marked active so subsequent
/// live-settings writes mirror into it via `ActiveProfileMirror`.
enum ProfileSeeder {
    static func seedDefaultIfNeeded(storage: FileStorage) async {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "ProfileSeederContext"
        context.transactionAuthor = "ProfileSeeder"

        await context.perform {
            do {
                let request: NSFetchRequest<ProfileStored> = ProfileStored.fetchRequest()
                request.fetchLimit = 1
                let existing = try context.count(for: request)
                guard existing == 0 else {
                    renameLegacyDefault(in: context)
                    return
                }

                let preferences = storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
                    ?? Preferences(from: OpenAPS.defaults(for: OpenAPS.Settings.preferences))
                    ?? Preferences()

                let basalProfile = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
                    ?? [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
                    ?? []

                let sensitivities = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
                    ?? InsulinSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.insulinSensitivities))
                    ?? InsulinSensitivities(units: .mgdL, userPreferredUnits: .mgdL, sensitivities: [])

                let carbRatios = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
                    ?? CarbRatios(from: OpenAPS.defaults(for: OpenAPS.Settings.carbRatios))
                    ?? CarbRatios(units: .grams, schedule: [])

                let bgTargets = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
                    ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
                    ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])

                let profile = ProfileStored(context: context)
                profile.id = UUID()
                profile.name = "Default Profile"
                profile.createdAt = Date()
                profile.isActive = true
                profile.activatedAt = Date()
                profile.expiresAt = nil
                profile.previousProfileID = nil
                profile.orderPosition = 1
                profile.preferences = preferences
                profile.therapy = TherapyBundle(
                    basalProfile: basalProfile,
                    sensitivities: sensitivities,
                    carbRatios: carbRatios,
                    bgTargets: bgTargets
                )

                try context.save()
                info(.settings, "Default Profile created from current settings")
            } catch {
                warning(.storage, "Creating Default Profile failed", error: error)
            }
        }
    }

    /// One-shot migration: installs seeded before the rename carry a profile
    /// literally named "Default"; give it the current "Default Profile" name.
    private static func renameLegacyDefault(in context: NSManagedObjectContext) {
        do {
            let request: NSFetchRequest<ProfileStored> = ProfileStored.fetchRequest()
            request.predicate = NSPredicate(format: "name == %@", "Default")
            let legacy = try context.fetch(request)
            guard !legacy.isEmpty else { return }
            for profile in legacy {
                profile.name = "Default Profile"
            }
            try context.save()
            info(.settings, "Legacy Default profile renamed to Default Profile")
        } catch {
            warning(.storage, "Renaming legacy Default profile failed", error: error)
        }
    }
}
