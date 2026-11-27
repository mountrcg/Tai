import AppIntents
import Foundation

/// Apply a Temp Target preset immediately. For scheduling a preset for a
/// future date, use `ScheduleTempPresetIntent` instead.
struct ApplyTempPresetIntent: AppIntent {
    static var title: LocalizedStringResource = "Activate TT preset"

    static var description = IntentDescription("Activate a Temporary Target preset now")

    @Parameter(
        title: "Preset",
        description: "the preset to apply",
        requestValueDialog: IntentDialog(stringLiteral: String(localized: "Which preset to apply?"))
    ) var preset: TempPreset?

    @Parameter(
        title: "Confirm Before applying",
        description: "If toggled, you will need to confirm before applying",
        default: true
    ) var confirmBeforeApplying: Bool

    static var parameterSummary: some ParameterSummary {
        When(\ApplyTempPresetIntent.$confirmBeforeApplying, .equalTo, true, {
            Summary("Apply \(\.$preset)") {
                \.$confirmBeforeApplying
            }
        }, otherwise: {
            Summary("Immediately apply \(\.$preset)") {
                \.$confirmBeforeApplying
            }
        })
    }

    /// Executes the intent to apply the selected temporary target preset.
    ///
    /// - Returns: A dialog indicating whether the temporary target was successfully applied or failed.
    /// - Throws: An error if an issue occurs during execution.
    @MainActor func perform() async throws -> some ProvidesDialog {
        let intentRequest = TempPresetsIntentRequest()
        let presetToApply: TempPreset
        if let preset = preset {
            presetToApply = preset
        } else {
            presetToApply = try await $preset.requestDisambiguation(
                among: intentRequest.fetchAndProcessTempTargets(),
                dialog: "Select Temporary Target"
            )
        }

        if confirmBeforeApplying {
            try await requestConfirmation(
                result: .result(
                    dialog: IntentDialog(
                        stringLiteral: String(localized: "Confirm to apply Temporary Target '\(presetToApply.name)'")
                    )
                )
            )
        }

        if await intentRequest.enactTempTarget(presetToApply) {
            return .result(
                dialog: IntentDialog(
                    stringLiteral: String(localized: "Temporary Target '\(presetToApply.name)' applied")
                )
            )
        } else {
            return .result(
                dialog: IntentDialog(
                    stringLiteral: String(localized: "Temporary Target '\(presetToApply.name)' failed")
                )
            )
        }
    }
}
