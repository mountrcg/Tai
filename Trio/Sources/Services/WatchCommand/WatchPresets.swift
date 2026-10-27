import CoreData
import Foundation
import Swinject

/// An adjustment preset as the watch names it, plus the reference that activates exactly that row.
struct WatchPresetEntry: Equatable {
    let name: String
    /// `enabled` on the stored row: whether the preset runs now, never whether it may be started.
    let isActive: Bool
    let ref: AdjustmentRef
}

/// The preset lists a watch shows, sorted by display name.
struct WatchPresets: Equatable {
    let overridePresets: [OverridePresetWatch]
    let tempTargetPresets: [TempTargetPresetWatch]
}

/// Every configured override and temp target preset, running or not.
protocol WatchPresetsProvider {
    func overridePresets() async throws -> [WatchPresetEntry]
    func tempTargetPresets() async throws -> [WatchPresetEntry]
}

extension WatchPresetsProvider {
    func presets() async throws -> WatchPresets {
        async let overrides = overridePresets()
        async let tempTargets = tempTargetPresets()

        return try await WatchPresets(
            overridePresets: overrides.sortedByName.map { OverridePresetWatch(name: $0.name, isEnabled: $0.isActive) },
            tempTargetPresets: tempTargets.sortedByName.map { TempTargetPresetWatch(name: $0.name, isEnabled: $0.isActive) }
        )
    }
}

private extension Array where Element == WatchPresetEntry {
    var sortedByName: [WatchPresetEntry] {
        sorted {
            switch $0.name.localizedStandardCompare($1.name) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            // equal display names keep a stable order across replies
            case .orderedSame: return $0.name < $1.name
            }
        }
    }
}

final class BaseWatchPresetsProvider: WatchPresetsProvider, Injectable {
    @Injected() private var overrideStorage: OverrideStorage!
    @Injected() private var tempTargetStorage: TempTargetsStorage!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func overridePresets() async throws -> [WatchPresetEntry] {
        let ids = try await overrideStorage.fetchForOverridePresets()
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "watchOverridePresets"
        let rows: [OverrideStored] = try await CoreDataStack.shared.getNSManagedObject(with: ids, context: context)

        return await context.perform {
            rows.compactMap { row in
                guard let name = row.name, let id = row.id else { return nil }
                return WatchPresetEntry(name: name, isActive: row.enabled, ref: .presetID(id))
            }
        }
    }

    func tempTargetPresets() async throws -> [WatchPresetEntry] {
        let ids = try await tempTargetStorage.fetchForTempTargetPresets()
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "watchTempTargetPresets"
        let rows: [TempTargetStored] = try await CoreDataStack.shared.getNSManagedObject(with: ids, context: context)

        return await context.perform {
            rows.compactMap { row in
                guard let name = row.name, let id = row.id else { return nil }
                return WatchPresetEntry(name: name, isActive: row.enabled, ref: .presetID(id.uuidString))
            }
        }
    }
}
