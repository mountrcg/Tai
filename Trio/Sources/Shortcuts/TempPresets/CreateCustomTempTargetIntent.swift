import AppIntents
import CoreData
import Foundation
import UIKit

/// Create and activate a fully custom Temp Target now — no preset selection
/// required. For scheduling a custom Temp Target for a future date+time,
/// use `ScheduleCustomTempTargetIntent` instead.
///
/// Target value is interpreted in the user's configured glucose unit
/// (mg/dL or mmol/L).
struct CreateCustomTempTargetIntent: AppIntent {
    static var title: LocalizedStringResource = "Create TT"

    static var description = IntentDescription(
        "Create and activate a Temporary Target now with name, target value and duration"
    )

    @Parameter(
        title: "Name",
        description: "Name shown in history",
        requestValueDialog: IntentDialog(stringLiteral: String(localized: "Name for this Temp Target?"))
    ) var name: String

    @Parameter(
        title: "Target value",
        description: "Target glucose value in the unit configured in Trio (mg/dL or mmol/L)",
        requestValueDialog: IntentDialog(stringLiteral: String(localized: "Target value?"))
    ) var targetValue: Double

    @Parameter(
        title: "Duration (minutes)",
        description: "How long the Temp Target should run (5–1440 min)",
        inclusiveRange: (5, 1440),
        requestValueDialog: IntentDialog(stringLiteral: String(localized: "Duration in minutes?"))
    ) var durationMinutes: Int

    @Parameter(
        title: "Confirm Before applying",
        description: "If toggled, you will need to confirm before applying",
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Create Temporary Target \(\.$name) now") {
            \.$targetValue
            \.$durationMinutes
            \.$confirmBeforeApplying
        }
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        let request = CustomTempTargetIntentRequest()

        guard targetValue > 0 else {
            return .result(
                dialog: IntentDialog(stringLiteral: String(localized: "Target value must be positive"))
            )
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return .result(
                dialog: IntentDialog(stringLiteral: String(localized: "Name is required"))
            )
        }

        // Convert from user unit to mg/dL for storage.
        let targetMgdl = request.targetInMgdl(entered: Decimal(targetValue))

        if confirmBeforeApplying {
            try await requestConfirmation(
                result: .result(
                    dialog: IntentDialog(
                        stringLiteral: String(
                            localized:
                            "Confirm Temp Target '\(trimmedName)': \(formatted(targetValue)) for \(durationMinutes) min, now"
                        )
                    )
                )
            )
        }

        let success = await request.enactImmediate(
            name: trimmedName,
            targetMgdl: targetMgdl,
            durationMinutes: Decimal(durationMinutes)
        )

        guard success else {
            return .result(
                dialog: IntentDialog(
                    stringLiteral: String(localized: "Temp Target '\(trimmedName)' failed")
                )
            )
        }

        return .result(
            dialog: IntentDialog(
                stringLiteral: String(
                    localized: "Temp Target '\(trimmedName)' applied for \(durationMinutes) min"
                )
            )
        )
    }

    private func formatted(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

/// Backend for `CreateCustomTempTargetIntent` and `ScheduleCustomTempTargetIntent`.
/// Immediate path mirrors `Adjustments.StateModel.saveCustomTempTarget`; the
/// scheduled path is delegated to `ScheduledTempTargetHelper`.
final class CustomTempTargetIntentRequest: BaseIntentsRequest {
    /// Convert a user-entered target into mg/dL for storage.
    func targetInMgdl(entered: Decimal) -> Decimal {
        switch settingsManager.settings.units {
        case .mgdL: return entered
        case .mmolL: return entered.asMgdL
        }
    }

    // MARK: - Immediate

    @MainActor func enactImmediate(
        name: String,
        targetMgdl: Decimal,
        durationMinutes: Decimal
    ) async -> Bool {
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = startBackgroundTask(withName: "TempTarget Custom Enact")

        await ScheduledTempTargetHelper.disableAllActiveTempTargets(
            tempTargetsStorage: tempTargetsStorage,
            viewContext: viewContext
        )

        let tempTarget = TempTarget(
            name: name,
            createdAt: Date(),
            targetTop: targetMgdl,
            targetBottom: targetMgdl,
            duration: durationMinutes,
            enteredBy: TempTarget.local,
            reason: TempTarget.custom,
            isPreset: false,
            enabled: true,
            halfBasalTarget: settingsManager.preferences.halfBasalExerciseTarget
        )

        do {
            try await tempTargetsStorage.storeTempTarget(tempTarget: tempTarget)
            tempTargetsStorage.saveTempTargetsToStorage([tempTarget])
            Foundation.NotificationCenter.default.post(name: .willUpdateTempTargetConfiguration, object: nil)
            await awaitNotification(.didUpdateTempTargetConfiguration)
            endBackgroundTaskSafely(&backgroundTaskID, taskName: "TempTarget Custom Enact")
            return true
        } catch {
            debug(
                .default,
                "\(DebuggingIdentifiers.failed) Failed to enact custom TempTarget: \(error)"
            )
            endBackgroundTaskSafely(&backgroundTaskID, taskName: "TempTarget Custom Enact")
            return false
        }
    }

    // MARK: - Scheduled (delegated)

    @MainActor func scheduleCustom(
        name: String,
        targetMgdl: Decimal,
        durationMinutes: Decimal,
        startTime: Date
    ) async -> Bool {
        await ScheduledTempTargetHelper.enact(
            name: name,
            targetMgdl: targetMgdl,
            durationMinutes: durationMinutes,
            halfBasalTarget: settingsManager.preferences.halfBasalExerciseTarget,
            startTime: startTime,
            tempTargetsStorage: tempTargetsStorage,
            viewContext: viewContext
        )
    }
}
