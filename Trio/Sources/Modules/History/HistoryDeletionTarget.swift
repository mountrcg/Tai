import CoreData
import Foundation

extension History {
    /// Single source of truth for what a History row delete swipe is about to remove.
    /// Replaces three separate `.alert` modifiers (glucose, insulin, carbs — the meals
    /// tab and the combined treatments tab both route carb deletion through the same
    /// `.carbs` case) that used to share state and could misfire across each other.
    enum DeletionTarget: Identifiable {
        case glucose(GlucoseStored)
        case insulin(PumpEventStored)
        case carbs(CarbEntryStored)

        var id: NSManagedObjectID {
            switch self {
            case let .glucose(glucose): return glucose.objectID
            case let .insulin(pumpEvent): return pumpEvent.objectID
            case let .carbs(carbEntry): return carbEntry.objectID
            }
        }

        func title(units _: GlucoseUnits) -> String {
            switch self {
            case .glucose:
                return String(localized: "Delete Glucose?", comment: "Alert title for deleting glucose")
            case .insulin:
                return String(localized: "Delete Insulin?", comment: "Alert title for deleting insulin")
            case let .carbs(carbEntry):
                guard carbEntry.fpuID != nil else {
                    return String(localized: "Delete Carbs?", comment: "Alert title for deleting carbs")
                }
                return carbEntry.isFPU
                    ? String(localized: "Delete Carbs Equivalents?", comment: "Alert title for deleting carb equivalents")
                    : String(localized: "Delete Carbs?", comment: "Alert title for deleting carbs")
            }
        }

        func message(units: GlucoseUnits) -> String {
            switch self {
            case let .glucose(glucose):
                let glucoseToDisplay = units == .mgdL
                    ? glucose.glucose.description
                    : Int(glucose.glucose).formattedAsMmolL
                return Formatter.dateFormatter.string(from: glucose.date ?? Date())
                    + ", " + glucoseToDisplay + " " + units.rawValue
            case let .insulin(pumpEvent):
                var text = Formatter.dateFormatter.string(from: pumpEvent.timestamp ?? Date())
                    + ", "
                    + (Formatter.decimalFormatterWithThreeFractionDigits.string(from: pumpEvent.bolus?.amount ?? 0) ?? "0")
                    + String(localized: " U", comment: "Insulin unit")
                if let bolus = pumpEvent.bolus, bolus.isSMB {
                    text += String(localized: " SMB", comment: "Super Micro Bolus indicator in delete alert")
                }
                return text
            case let .carbs(carbEntry):
                guard carbEntry.fpuID != nil else {
                    return Formatter.dateFormatter.string(from: carbEntry.date ?? Date())
                        + ", "
                        + (Formatter.decimalFormatterWithTwoFractionDigits.string(for: carbEntry.carbs) ?? "0")
                        + String(localized: " g", comment: "gram of carbs")
                }
                return String(
                    localized: "All FPUs and the carbs of the meal will be deleted.",
                    comment: "Alert message for meal deletion"
                )
            }
        }

        /// True for a meal that will cascade-delete FPU rows on top of its own carbs.
        var isFpuOrComplexMeal: Bool {
            guard case let .carbs(carbEntry) = self else { return false }
            return carbEntry.isFPU || carbEntry.fat > 0 || carbEntry.protein > 0
        }
    }
}
