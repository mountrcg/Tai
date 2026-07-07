import SwiftUI

/// Shared label / mini-hint / verbose-hint providers for algorithm preferences.
///
/// Centralising these here keeps the `String(localized:)` calls in a single file so
/// every translation lives exactly once, and both the live Settings screens and the
/// profile draft editors render identical help text.
///
/// Conventions:
/// - Labels and mini hints are static `String` constants (or `(units:)` functions when
///   they interpolate glucose units).
/// - Verbose hints are `@ViewBuilder` functions returning `some View`, taking `units`
///   only when the hint body depends on the glucose unit.
enum AlgorithmSettingHints {
    // MARK: - Autosens

    static let autosensMaxLabel = String(localized: "Autosens Max", comment: "Autosens Max")
    static let autosensMaxMini = String(
        localized: "Upper limit of the Sensitivity Ratio.",
        comment: "Mini-hint for Autosens Max setting"
    )

    @ViewBuilder static func autosensMaxVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 120%").bold()
            Text(
                "Autosens Max sets the maximum Sensitivity Ratio used by Autosens, Dynamic ISF, and Sigmoid Formula."
            )
            Text(
                "The Sensitivity Ratio is used to calculate the amount of adjustment needed to basal rates and ISF."
            )
            Text(
                "Tip: Increasing this value allows automatic adjustments of basal rates to be higher and ISF to be lower."
            )
        }
    }

    static let autosensMinLabel = String(localized: "Autosens Min", comment: "Autosens Min")
    static let autosensMinMini = String(
        localized: "Lower limit of the Sensitivity Ratio.",
        comment: "Mini-hint for Autosens Min setting"
    )

    @ViewBuilder static func autosensMinVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 70%").bold()
            Text(
                "Autosens Min sets the minimum Sensitivity Ratio used by Autosens, Dynamic ISF, and Sigmoid Formula."
            )
            Text(
                "The Sensitivity Ratio is used to calculate the amount of adjustment needed to basal rates and ISF."
            )
            Text(
                "Tip: Decreasing this value allows automatic adjustments of basal rates to be lower and ISF to be higher."
            )
        }
    }

    static let rewindResetsAutosensLabel = String(localized: "Rewind Resets Autosens", comment: "Rewind Resets Autosens")
    static let rewindResetsAutosensMini = String(
        localized: "Pump rewind initiates a reset in Sensitivity Ratio.",
        comment: "Mini-hint for Rewind Resets Autosens setting"
    )

    @ViewBuilder static func rewindResetsAutosensVerbose() -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Default: ON").bold()
            Text("Medtronic and Dana Users Only").bold()
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "This feature resets the Sensitivity Ratio to neutral when you rewind your pump on the assumption that this corresponds to a site change."
                )
                Text(
                    "Autosens will begin learning sensitivity anew from the time of the rewind, which may take up to 6 hours."
                )
                Text(
                    "Tip: If you usually rewind your pump independently of site changes, you may want to consider disabling this feature."
                )
            }
        }
    }

    // MARK: - Target Behavior

    static let highTempTargetRaisesSensitivityLabel = String(
        localized: "High Temp Target Raises Sensitivity",
        comment: "High Temp Target Raises Sensitivity"
    )
    static func highTempTargetRaisesSensitivityMini(units: GlucoseUnits) -> String {
        String(
            localized: "Increase sensitivity when glucose is above target if a manual Temp Target > \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue) is set.",
            comment: "Mini-hint for High Temp Target Raises Sensitivity — interpolated values are the threshold number and the glucose unit"
        )
    }

    @ViewBuilder static func highTempTargetRaisesSensitivityVerbose(units: GlucoseUnits) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: OFF").bold()
            Text(
                "When this feature is enabled, manually setting a temporary target above \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue) will decrease the Autosens Ratio used for ISF and basal adjustments, resulting in less insulin delivered overall. This scales with the temporary target set; the higher the temp target, the lower the Autosens Ratio used."
            )
            Text(
                "If Half Basal Exercise Target is set to \(units == .mgdL ? "160" : 160.formattedAsMmolL) \(units.rawValue), a temp target of \(units == .mgdL ? "120" : 120.formattedAsMmolL) \(units.rawValue) uses an Autosens Ratio of 0.75. A temp target of \(units == .mgdL ? "140" : 140.formattedAsMmolL) \(units.rawValue) uses an Autosens Ratio of 0.6."
            )
            Text("Note: The effect of this can be adjusted with the Half Basal Exercise Target")
        }
    }

    static let lowTempTargetLowersSensitivityLabel = String(
        localized: "Low Temp Target Lowers Sensitivity",
        comment: "Low Temp Target Lowers Sensitivity"
    )
    static func lowTempTargetLowersSensitivityMini(units: GlucoseUnits) -> String {
        String(
            localized: "Decrease sensitivity when glucose is below target if a manual Temp Target < \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue) is set.",
            comment: "Mini-hint for Low Temp Target Lowers Sensitivity — interpolated values are the threshold number and the glucose unit"
        )
    }

    @ViewBuilder static func lowTempTargetLowersSensitivityVerbose(units: GlucoseUnits) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: OFF").bold()
            Text(
                "When this feature is enabled, setting a temporary target below \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue) will increase the Autosens Ratio used for ISF and basal adjustments, resulting in more insulin delivered overall. This scales with the temporary target set; the lower the Temp Target, the higher the Autosens Ratio used. It requires Algorithm Settings > Autosens > Autosens Max to be set to > 100% to work."
            )
            Text(
                "If Half Basal Exercise Target is \(units == .mgdL ? "160" : 160.formattedAsMmolL) \(units.rawValue), a Temp Target of \(units == .mgdL ? "95" : 95.formattedAsMmolL) \(units.rawValue) uses an Autosens Ratio of 1.09. A Temp Target of \(units == .mgdL ? "85" : 85.formattedAsMmolL) \(units.rawValue) uses an Autosens Ratio of 1.33."
            )
            Text("Note: The effect of this can be adjusted with the Half Basal Exercise Target")
        }
    }

    static let sensitivityRaisesTargetLabel = String(
        localized: "Sensitivity Raises Target", comment: "Sensitivity Raises Target"
    )
    static let sensitivityRaisesTargetMini = String(
        localized: "Raise target glucose when Autosens Ratio is less than 1.",
        comment: "Mini-hint for Sensitivity Raises Target setting"
    )

    @ViewBuilder static func sensitivityRaisesTargetVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: OFF").bold()
            Text(
                "Enabling this feature causes Trio to automatically raise the targeted glucose if it detects an increase in insulin sensitivity from your baseline."
            )
        }
    }

    static let resistanceLowersTargetLabel = String(
        localized: "Resistance Lowers Target", comment: "Resistance Lowers Target"
    )
    static let resistanceLowersTargetMini = String(
        localized: "Lower target glucose when Autosens Ratio is greater than 1.",
        comment: "Mini-hint for Resistance Lowers Target setting"
    )

    @ViewBuilder static func resistanceLowersTargetVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: OFF").bold()
            Text(
                "Enabling this feature causes Trio to automatically reduce the targeted glucose if it detects a decrease in sensitivity (resistance) from your baseline."
            )
        }
    }

    static let halfBasalExerciseTargetLabel = String(
        localized: "Half Basal Exercise Target", comment: "Half Basal Exercise Target"
    )
    static let halfBasalExerciseTargetMini = String(
        localized: "Scales down your basal rate to 50% at this value.",
        comment: "Mini-hint for Half Basal Exercise Target setting"
    )

    @ViewBuilder static func halfBasalExerciseTargetVerbose(units: GlucoseUnits) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "Default: \(units == .mgdL ? "160" : 160.formattedAsMmolL) \(units.rawValue)"
            )
            .bold()
            Text(
                "The Half Basal Exercise Target allows you to scale down your basal insulin during exercise or scale up your basal insulin when eating soon when a temporary glucose target is set."
            )
            Text(
                "For example, at a temp target of \(units == .mgdL ? "160" : 160.formattedAsMmolL) \(units.rawValue), your basal is reduced to 50%, but this scales depending on the target (e.g., 75% at \(units == .mgdL ? "120" : 120.formattedAsMmolL) \(units.rawValue), 60% at \(units == .mgdL ? "140" : 140.formattedAsMmolL) \(units.rawValue))."
            )
            Text(
                "Note: This setting is only utilized if the settings \"Low Temp Target Lowers Sensitivity\" OR \"High Temp Target Raises Sensitivity\" are enabled."
            )
        }
    }

    // MARK: - SMB

    static let enableSMBAlwaysLabel = String(localized: "Enable SMB Always", comment: "Enable SMB Always")
    static let enableSMBAlwaysMini = String(
        localized: "Allow SMBs at all times except when a high Temp Target is set.",
        comment: "Mini-hint for Enable SMB Always setting"
    )

    @ViewBuilder static func enableSMBAlwaysVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: OFF").bold()
            Text(
                "When enabled, Super Micro Boluses (SMBs) will always be allowed if dosing calculations determine insulin is needed via the SMB delivery method, except when a high Temp Target is set. Enabling SMB Always will remove redundant \"Enable SMB\" options when this setting is enacted."
            )
            Text(
                "Note: If you would like to allow SMBs when a high Temp Target is set, enable the \"Allow SMBs with High Temptarget\" setting."
            )
        }
    }

    static let enableSMBWithCOBLabel = String(localized: "Enable SMB With COB", comment: "Enable SMB With COB")
    static let enableSMBWithCOBMini = String(
        localized: "Allow SMB when carbs are on board.",
        comment: "Mini-hint for Enable SMB With COB setting"
    )

    @ViewBuilder static func enableSMBWithCOBVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: OFF").bold()
            Text(
                "When there are carbs on board (COB > 0), enabling this feature allows Trio to use Super Micro Boluses (SMB) to deliver the insulin required."
            )
            Text(
                "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
            )
        }
    }

    static let enableSMBWithTemptargetLabel = String(
        localized: "Enable SMB With Temptarget", comment: "Enable SMB With Temptarget"
    )
    static func enableSMBWithTemptargetMini(units: GlucoseUnits) -> String {
        String(
            localized: "Allow SMB when a manual Temporary Target is set under \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue).",
            comment: "Mini-hint for Enable SMB With Temptarget — interpolated values are the threshold number and the glucose unit"
        )
    }

    @ViewBuilder static func enableSMBWithTemptargetVerbose(units: GlucoseUnits) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: OFF").bold()
            Text(
                "Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) at times when a manual Temporary Target under \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue) is set."
            )
            Text(
                "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
            )
        }
    }

    static let enableSMBAfterCarbsLabel = String(localized: "Enable SMB After Carbs", comment: "Enable SMB After Carbs")
    static let enableSMBAfterCarbsMini = String(
        localized: "Allow SMB for 6 hrs after a carb entry.",
        comment: "Mini-hint for Enable SMB After Carbs setting"
    )

    @ViewBuilder static func enableSMBAfterCarbsVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: OFF").bold()
            Text(
                "Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) for 6 hours after a carb entry, regardless of whether there are active carbs on board (COB)."
            )
            Text(
                "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
            )
        }
    }

    static let enableSMBWithHighGlucoseLabel = String(
        localized: "Enable SMB With High Glucose", comment: "Enable SMB With High Glucose"
    )
    static let enableSMBWithHighGlucoseConditionalLabel = String(
        localized: "High Glucose Target",
        comment: "Row label for the high-glucose target field that gates Enable SMB With High Glucose"
    )
    static let enableSMBWithHighGlucoseMini = String(
        localized: "Allow SMB when glucose is above the High Glucose Target value.",
        comment: "Mini-hint for Enable SMB With High Glucose setting"
    )

    @ViewBuilder static func enableSMBWithHighGlucoseVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: OFF").bold()
            Text(
                "Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) when glucose reading is above the value set as High Glucose Target."
            )
            Text(
                "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
            )
        }
    }

    static let allowSMBWithHighTemptargetLabel = String(
        localized: "Allow SMB With High Temptarget", comment: "Allow SMB With High Temptarget"
    )
    static func allowSMBWithHighTemptargetMini(units: GlucoseUnits) -> String {
        String(
            localized: "Allow SMB when a manual Temporary Target is set greater than \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue).",
            comment: "Mini-hint for Allow SMB With High Temptarget — interpolated values are the threshold number and the glucose unit"
        )
    }

    @ViewBuilder static func allowSMBWithHighTemptargetVerbose(units: GlucoseUnits) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: OFF").bold()
            Text(
                "Enabling this feature allows Trio to deliver insulin required using Super Micro Boluses (SMB) when a manual Temporary Target above \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue) is set."
            )
            Text(
                "Note: If this is enabled and the criteria are met, SMBs could be utilized regardless of other SMB settings being enabled or not."
            )
            Text(
                "Warning: High Temp Targets are often set when recovering from lows. If you use High Temp Targets for that purpose, this feature should remain disabled."
            ).bold()
        }
    }

    static let enableUAMLabel = String(localized: "Enable UAM", comment: "Enable UAM")
    static let enableUAMMini = String(localized: "Enable Unannounced Meals SMB.", comment: "Mini-hint for Enable UAM setting")

    @ViewBuilder static func enableUAMVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: OFF").bold()
            Text(
                "Enabling the UAM (Unannounced Meals) feature allows the system to detect and respond to unexpected rises in glucose readings caused by unannounced or miscalculated carbs, meals high in fat or protein, or other factors like adrenaline."
            )
            Text(
                "It uses the SMB (Super Micro Bolus) algorithm to deliver insulin in small amounts to correct glucose spikes. UAM also works in reverse, reducing or stopping SMBs if glucose levels drop unexpectedly."
            )
            Text(
                "This feature ensures more accurate insulin adjustments when carb entries are missing or incorrect."
            )
        }
    }

    static let maxSMBBasalMinutesLabel = String(localized: "Max SMB Basal Minutes", comment: "Max SMB Basal Minutes")
    static let maxSMBBasalMinutesMini = String(
        localized: "Limits the size of a single Super Micro Bolus (SMB) dose.",
        comment: "Mini-hint for Max SMB Basal Minutes setting"
    )

    @ViewBuilder static func maxSMBBasalMinutesVerbose() -> some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Default: 30 minutes").bold()
                    Text("(50% current basal rate)").bold()
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "This is a limit on the size of a single SMB. One SMB can only be as large as this many minutes of your current profile basal rate."
                    )
                    Text(
                        "To calculate the maximum SMB allowed based on this setting, use the following formula:"
                    )
                }
            }
            VStack(alignment: .center, spacing: 5) {
                Text("𝒳 = Max SMB Basal Minutes")
                Text("(𝒳 / 60) × current basal rate")
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "Warning: Increasing this value above 90 minutes may impact Trio's ability to effectively zero temp and prevent lows."
                ).bold()
                Text("Note: SMBs must be enabled to use this limit.")
            }
        }
    }

    static let smbThresholdRatioLabel = String(localized: "SMB Threshold Ratio", comment: "SMB Threshold Ratio")
    static let smbThresholdRatioMini = String(
        localized: "Raises the glucose floor below which SMBs are blocked. 0.5 keeps default behaviour, 1.0 blocks SMBs until above target.",
        comment: "Mini-hint for SMB Threshold Ratio setting"
    )

    @ViewBuilder static func smbThresholdRatioVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 0.5 — valid range (0.5, 1.0]").bold()
            Text(
                "A safety knob that controls how close to your low-target SMBs are still allowed. It shifts the SMB cutoff (\"threshold\") along the line between your low-target and 40 mg/dL."
            )
            Text("Formula:").bold()
            Text("threshold = minBG − (1 − ratio) × (minBG − 40)")
            Text("Examples (minBG = 100 mg/dL):").bold()
            Text("• 0.5 — threshold 70 mg/dL (midway between target and 40)")
            Text("• 0.7 — threshold 82 mg/dL (SMBs cut off sooner)")
            Text("• 1.0 — threshold 100 mg/dL (no SMBs below target)")
            Text(
                "Higher = more conservative. Useful if you find the default cuts SMBs off too late for your comfort. Values at or below 0.5 fall back to the default; values above 1.0 are ignored (clamped to (0.5, 1.0])."
            )
            Text("Note: the threshold is also clamped to at least 60 mg/dL and at most 120 mg/dL.")
        }
    }

    static let maxUAMBasalMinutesLabel = String(localized: "Max UAM Basal Minutes", comment: "Max UAM Basal Minutes")
    static let maxUAMBasalMinutesMini = String(
        localized: "Limits the size of a single Unannounced Meal (UAM) SMB dose.",
        comment: "Mini-hint for Max UAM Basal Minutes setting"
    )

    static let smbIntervalLabel = String(localized: "SMB Interval", comment: "SMB Interval")
    static let smbIntervalMini = String(
        localized: "Minimum minutes since the last SMB or manual bolus to allow an automated SMB.",
        comment: "Mini-hint for SMB Interval setting"
    )

    @ViewBuilder static func smbIntervalVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 3 min").bold()
            Text(
                "This is the minimum number of minutes since the last SMB or manual bolus before Trio will permit an automated SMB."
            )
        }
    }

    @ViewBuilder static func maxUAMBasalMinutesVerbose() -> some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Default: 30 minutes").bold()
                    Text("(50% current basal rate)").bold()
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "This is a limit on the size of a single UAM SMB. One UAM SMB can only be as large as this many minutes of your current profile basal rate."
                    )
                    Text(
                        "To calculate the maximum UAM SMB allowed based on this setting, use the following formula:"
                    )
                }
            }
            VStack(alignment: .center, spacing: 5) {
                Text("𝒳 = Max UAM SMB Basal Minutes")
                Text("(𝒳 / 60) × current basal rate")
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(
                    "Warning: Increasing this value above 90 minutes may impact Trio's ability to effectively zero temp and prevent lows."
                ).bold()
                Text("Note: UAM SMBs must be enabled to use this limit.")
            }
        }
    }

    // MARK: - Dynamic ISF

    /// Top-level "Dynamic ISF" umbrella hint (shown from the header in live Settings; reused by
    /// the draft's `useNewFormula` toggle — Draft models dynISF as a plain boolean rather than
    /// the Settings picker, but the help content is identical).
    static let dynamicISFLabel = String(localized: "Dynamic ISF", comment: "Dynamic ISF")
    static let useDynamicISFMini = String(
        localized: "Dynamically adjust insulin sensitivity using Dynamic Ratio rather than Autosens Ratio.",
        comment: "Mini-hint for Use Dynamic ISF setting"
    )

    @ViewBuilder static func dynamicISFVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: Disabled").bold()
            Text(
                "Enabling this feature allows Trio to calculate a new Insulin Sensitivity Factor with each loop cycle dynamically. Trio offers two dynamic formulas:"
            )
            VStack(alignment: .leading, spacing: 10) {
                Text("Logarithmic Dynamic ISF").bold()
                Text(
                    "Enabling this feature allows Trio to calculate a new Insulin Sensitivity Factor with each loop cycle by considering your current glucose, the weighted total daily dose of insulin, the set adjustment factor, and a few other data points. This helps tailor your insulin response more accurately in real time."
                )
                Text(
                    "Dynamic ISF produces a Dynamic Ratio, replacing the Autosens Ratio, determining how much your profile ISF will be adjusted every loop cycle, ensuring it stays within safe limits set by your Autosens Min/Max settings. It provides more precise insulin dosing by responding to changes in insulin needs throughout the day."
                )
                Text(
                    "You can influence the adjustments made by Dynamic ISF primarily by adjusting Autosens Max, Autosens Min, and Adjustment Factor. Other settings also influence Dynamic ISF's response, such as Glucose Target, Profile ISF, Peak Insulin Time, and Weighted Average of TDD."
                )
                Text(
                    "Warning: Before adjusting these settings, make sure you are fully aware of the impact those changes will have."
                )
                .bold()
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Sigmoid Dynamic ISF").bold()
                Text(
                    "Turning on the Sigmoid Formula setting alters how your Dynamic Ratio, and thus your New ISF, are calculated using a sigmoid curve."
                )
                Text(
                    "The curve's steepness is influenced by the Adjustment Factor, while the Autosens Min/Max settings determine the limits of the ratio adjustment, which can also influence the steepness of the sigmoid curve."
                )
                Text(
                    "When using the Sigmoid Formula, the weighted Total Daily Dose has a much lower impact on the dynamic adjustments to sensitivity."
                )
                Text("Careful tuning is essential to avoid overly aggressive insulin changes.")
                Text(
                    "It is not recommended to set Autosens Max above 150% to maintain safe insulin dosing."
                )
                Text(
                    "There has been no empirical data analysis to support the use of the Sigmoid Formula for dynamic sensitivity determination."
                ).bold()
            }
        }
    }

    static let adjustmentFactorLabel = String(
        localized: "Adjustment Factor (AF)",
        comment: "Row label for the Dynamic ISF Adjustment Factor (AF) setting"
    )
    static let adjustmentFactorMini = String(
        localized: "Alter the rate of Dynamic ISF (Sensitivity) adjustments.",
        comment: "Mini-hint for Dynamic ISF Adjustment Factor (AF) setting"
    )

    @ViewBuilder static func adjustmentFactorVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 80%").bold()
            Text(
                "The Adjustment Factor (AF) allows you to control how quickly and effectively Dynamic ISF responds to changes in glucose levels."
            )
            Text(
                "Adjusting this value not only can adjust how quickly your sensitivity will respond to changing glucose readings, but also at what glucose readings you reach your Autosens Max/Min limits."
            )
            Text(
                "Increasing this setting can make ISF adjustments quicker, but will also change the glucose value that coincides with the ISF used at your Autosens Max and Autosens Min limits. Likewise, decreasing this setting can make ISF adjustments slower and will also change the glucose value that coincides with the ISF used when it reaches the Autosens Max and Autosens Min limits. It is best to utilize the Desmos graphs from TrioDocs.org to optimize all Dynamic Settings."
            )
        }
    }

    static let adjustmentFactorSigmoidLabel = String(
        localized: "Sigmoid Adjustment Factor",
        comment: "Row label for the Sigmoid variant of the Dynamic ISF Adjustment Factor"
    )
    static let adjustmentFactorSigmoidMini = String(
        localized: "Alter the rate of dynamic sensitivity adjustments for Sigmoid.",
        comment: "Mini-hint for Sigmoid Dynamic ISF Adjustment Factor"
    )

    @ViewBuilder static func adjustmentFactorSigmoidVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 50%").bold()
            Text(
                "The Sigmoid Adjustment Factor (AF) allows you to control how quickly Sigmoid Dynamic ISF responds to changes in glucose levels and at what glucose value you will reach your Autosens Max and Autosens Min limits."
            )
            Text(
                "Sigmoid Adjustment Factor influences both how fast your ISF values will change and how quickly you will reach your Autosens Max and Min limits set. Increasing Sigmoid Adjustment Factor increases the rate of change of your ISF and reduces the range of glucose values between your Autosens Max and Min limits."
            )
            Text(
                "This setting allows for a more responsive system, but the effects are restricted by the Autosens Min/Max settings."
            )
            Text(
                "Due to how the curve is calculated when using the Sigmoid Formula, increasing this setting has a different impact on the steepness of the curve than in the standard logarithmic Dynamic ISF calculation. Use caution when adjusting this setting."
            )
        }
    }

    static let weightPercentageLabel = String(
        localized: "Weighted Average of TDD",
        comment: "Row label for the Dynamic ISF Weighted-Average-of-TDD setting"
    )
    static let weightPercentageMini = String(
        localized: "Weight of 24-hr TDD against 10-day TDD.",
        comment: "Mini-hint for Dynamic ISF Weighted-Average-of-TDD setting"
    )

    @ViewBuilder static func weightPercentageVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 35%").bold()
            Text(
                "This setting adjusts how much weight is given to your recent total daily insulin dose when calculating Dynamic ISF and Dynamic CR."
            )
            Text(
                "At the default setting, 35% of the calculation is based on the last 24 hours of insulin use, with the remaining 65% considering the last 10 days of data."
            )
            Text("Setting this to 100% means only the past 24 hours will be used.")
            Text("A lower value smooths out these variations for more stability.")
        }
    }

    static let tddAdjBasalLabel = String(localized: "Adjust Basal", comment: "Row label for the Dynamic-ISF Adjust-Basal toggle")
    static let tddAdjBasalMini = String(
        localized: "Use Dynamic Ratio to adjust basal rates.",
        comment: "Mini-hint for Dynamic-ISF Adjust-Basal toggle"
    )

    @ViewBuilder static func tddAdjBasalVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: OFF").bold()
            Text(
                "Turn this setting on to give basal adjustments more agility. Keep this setting off if your basal needs are not highly variable."
            )
            Text(
                "Enabling Adjust Basal replaces the standard Autosens Ratio calculation with its own Autosens Ratio calculated as such:"
            )
            Text("Autosens Ratio =\n(Weighted Average of TDD) / (10-day Average of TDD)")
            Text("New Basal Profile =\n(Current Basal Profile) × (Autosens Ratio)")
        }
    }

    // Draft-only master/sub toggles for Dynamic ISF. Settings uses a picker; the draft models
    // dynISF as two booleans (`useNewFormula`, `sigmoid`). Both reuse the full `dynamicISFVerbose`.
    static let useDynamicISFLabel = String(localized: "Use Dynamic ISF", comment: "Row label for the Use Dynamic ISF toggle")
    static let sigmoidLabel = String(
        localized: "Sigmoid",
        comment: "Row label for the Sigmoid (vs logarithmic) Dynamic-ISF formula toggle"
    )
    static let sigmoidMini = String(
        localized: "Use the sigmoid dynISF formula instead of logarithmic.",
        comment: "Mini-hint for the Sigmoid (vs logarithmic) Dynamic-ISF formula toggle"
    )

    // MARK: - autoISF

    static let autoISFTitleLabel = String(
        localized: "autoISF 3.01",
        comment: "Title label of the autoISF extension (version 3.01)"
    )
    static let activateAutoISFLabel = String(localized: "Activate autoISF", comment: "Row label for the Activate autoISF toggle")
    static let activateAutoISFMini = String(
        localized: "autoISF 3.01 calculates insulin sensitivity (ISF) each loop cycle based on glucose behaviour within set limits.",
        comment: "Mini-hint for Activate autoISF toggle"
    )

    @ViewBuilder static func activateAutoISFVerbose() -> some View {
        VStack(alignment: .leading) {
            Text(
                "autoISF allows to adapt the insulin sensitivity factor (ISF) in the following scenarios of glucose behaviour:"
            )
            .multilineTextAlignment(.leading)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            BulletList(
                listItems: [
                    "Accelaration: acce_ISF is a factor derived from acceleration of glucose levels.",
                    "Glucose Level: bg_ISF is a factor derived from the deviation of glucose from target.",
                    "Postprandial situation: pp_ISF is a factor derived from glucose rise delta.",
                    "Long lasting Highs: dura_ISF is a factor derived from glucose being stuck at high levels."
                ],
                listItemSpacing: 10
            )
            Image("autoISF_factors")
                .resizable()
                .scaledToFit()
                .frame(width: 300)
                .padding(2)
            Text(
                "When autoISF is turned on the autoISF Ratio (aiSR) will be displayed on Homeview, showing the final ISF / Sensitivity adaption, instead of the regular Autosens Sensitivity Ratio (AS)"
            )
            Divider()
            Text("When all 4 effects are configured, how to deduce an end result?").bold()
            Text("""
            The normal case is to pick the strongest factor as the one and only factor to be applied. Here autosense is also part of the game. But how about the exceptions, i.e., when different factors pull in different directions? In order of precedence they are:
            """)
                .font(.body)
                .multilineTextAlignment(.leading)
            BulletList(
                listItems: [
                    "bg_ISF < 1, i.e., glucose is below target.",
                    "If acce_ISF > 1, i.e., glucose is accelerating although below target, both factors get multiplied as a trade-off between them. Then the weaker of bg_ISF and Autosens is used as the final sensitivity ISF.",
                    "acce_ISF < 1, i.e., glucose is decelerating while other effects want to strengthen ISF. In this case, the strongest of the remaining, positive factors will be multiplied by acce_ISF to reach a compromise. This overall factor will be compared with autosense and the stronger of the two will be used in calculating the final sensitivity ISF.",
                    "In all of the above, the autoISF limits for maximum and minimum changes will also be applied."
                ],
                listItemSpacing: 10
            )
            Image("autoISF_flow")
                .resizable()
                .scaledToFit()
                .frame(width: 300)
                .padding(2)
            Text("""
            With v3.01 the following 5 settings were withdrawn because over time it proved they were not really necessary. One direct impact is a flatter menu structure for the remaining settings:
            """)
                .font(.body)
                .multilineTextAlignment(.leading)
            BulletList(
                listItems: [
                    "pp_ISF_hours no longer required because …",
                    "enable_pp_ISF_always is now always true which means …",
                    "delta_ISFrange_weight is no longer used in favour of pp_ISF",
                    "enable_dura_ISF_with_COB is now always true",
                    "enable_SMB_EvenOn_OddOff was discontinued and unified with enableSMB_EvenOn_OddOff_always"
                ],
                listItemSpacing: 10
            )
            Divider()
            Text("Full-Loop mode").bold()
            Text(
                "When the even/odd target toggle is enabled, setting an even-numbered temp target below 100 mg/dL (e.g. 80 or 90) puts autoISF into full-loop mode — a signal that you want maximum SMB power. In that mode the SMB delivery ratio is forced to at least the fixed SMB DeliveryRatio, even when the BG-range ramp would otherwise give a lower value."
            )
        }
    }

    static let enableAutosensAutoISFLabel = String(localized: "Enable Autosens", comment: "Enable Autosens")
    static let enableAutosensAutoISFMini = String(localized: "Switch Autosens on/off", comment: "Autosens miniHint")

    @ViewBuilder static func enableAutosensAutoISFVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default:  OFF ").bold()
            Text(
                "autosens is not needed for autoISF as it adapts on a longer time frame than autoISF, so any autosens adjustment is lagging behind what is done by autoISF. It can be kept to ON, and in some border cases the autosens ISF will be used. Check on Discord."
            )
            Text(
                "When autoISF is turned off Autosens will always be activated and on HomwView, the Autosens Sensitivity Ratio (AS) will be shown instead of the autoISF Ratio (aiSR)"
            )
        }
    }

    static let oddTargetDisablesSMBLabel = String(
        localized: "Odd Target disables SMB for autoISF", comment: "Odd Target disables SMB"
    )
    static let oddTargetDisablesSMBMini = String(
        localized: "autoISF will enable SMBs for even and block them for odd Targets.",
        comment: "Odd Target disables SMB miniHint"
    )

    @ViewBuilder static func oddTargetDisablesSMBVerbose(units: GlucoseUnits) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "Very neat feature that allows the use of profile and temporary targets to trigger SMB's being enabled or disabled. So a profile target at 3:00 am of \(units == .mgdL ? "121" : 121.formattedAsMmolL) \(units.rawValue) will prevent any SMB's in that time window. Schedule a TT of \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue) at 3:20 am and from then on SMB's can be enacted."
            )
            Divider()
            Text("Full-Loop mode").bold()
            Text(
                "A special case: setting an even-numbered temp target below \(units == .mgdL ? "100" : 100.formattedAsMmolL) \(units.rawValue) (e.g. \(units == .mgdL ? "80 or 90" : "\(80.formattedAsMmolL) or \(90.formattedAsMmolL)") \(units.rawValue)) signals that you want maximum SMB aggression — autoISF calls this full-loop mode."
            )
            Text(
                "In full-loop mode, the SMB delivery ratio becomes the greater of the fixed SMB DeliveryRatio and the linearly-rising ramp value — so the fixed ratio acts as a floor the ramp can only raise, never lower."
            )
        }
    }

    static let autoISFoffSportLabel = String(
        localized: "Exercise toggles all autoISF adjustments off", comment: "autoISF Off for Sport"
    )
    static let autoISFoffSportMini = String(
        localized: "Completely switches off autoISF during a high TT with adjusted sensitivity.",
        comment: "Exercise toggles all autoISF adjustments off miniHint"
    )

    @ViewBuilder static func autoISFoffSportVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "If enabled this function will switch off autoISF adaptions completely if you are exercising. Exercising means you have a high TempTarget enabled and  HighTTraisesSens, so that this high TT will already increase your sensitivity (will be displayed in active TempTarget)."
            )
        }
    }

    static let iobThresholdPercentLabel = String(
        localized: "autoISF IOB Threshold Percent", comment: "IOB Threshold"
    )
    static let iobThresholdPercentMini = String(
        localized: "This is the share of maxIOB above which autoISF will disable SMB. 100% neutralizes it's effect.",
        comment: "autoISF IOB Threshold miniHint"
    )

    @ViewBuilder static func iobThresholdPercentVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 100% ").bold()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("""
                    The variable IOB Threshold Percent holds a percentage of the maxIOB which is used as the threshold to disable SMB. If this is enabled by setting it lower than 100%, any sensitivity changes defined by the user are modulated internally into an effective IOB Threshold.

                    The new capabilities are:
                    """)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                    BulletList(
                        listItems: [
                            "IOB Threshold Percent gets modulated while sensitivity changes from TT - high TT raises Sens or low TT lowers Sens are active (Algorithm Settings > Target Behaviour)- in this respect high TT's lower effective max IOB and low TT raise it. These effects only activate if the IOB Threshold is set below 100%",
                            "A very special modification happens during the initial rise after carbs intake. After the first few SMBs the IOB Threshold may eventually be surpassed. Often this initial overshoot was far too much due to limited capabilities using automations and led to hypo later. The code will limit this overshoot or tolerance to 130% of the effective IOB Threshold. During the next loop the IOB will most probably still be above that threshold and therefore SMBs stay disabled until iob drops below the effective threshold."
                        ],
                        listItemSpacing: 10
                    )
                }
            }
        }
    }

    static let autoISFmaxLabel = String(localized: "autoISF Max", comment: "autoISF Max")
    static let autoISFmaxMini = String(localized: "Highest ISF factor allowed.", comment: "autoISF Max miniHint")

    @ViewBuilder static func autoISFmaxVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Typical: 2").bold()
            Text("Multiplier cap on how high the autoISF ratio can be and therefore how low it can adjust ISF.")
        }
    }

    static let autoISFminLabel = String(localized: "autoISF Min", comment: "autoISF Min")
    static let autoISFminMini = String(localized: "Lowest ISF factor allowed.", comment: "autoISF Min miniHint")

    @ViewBuilder static func autoISFminVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Typical: 0.7").bold()
            Text(
                "This is a multiplier cap for autoISF to set a limit on how low the autoISF ratio can be, which in turn determines how high it can adjust ISF."
            )
        }
    }

    static let enableBGaccelerationLabel = String(
        localized: "Enable BG Acceleration", comment: "Enable BG Acceleration"
    )
    static let enableBGaccelerationMini = String(
        localized: "Enables the BG acceleration adaptions, adjusting ISF for accelerating/decelerating blood glucose.",
        comment: "Enable BG Acceleration miniHint"
    )

    @ViewBuilder static func enableBGaccelerationVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text("""
                acce_ISF is calculated by
                acce_ISF = 1 + acce_weight * fit_share * cap_weight * acceleration
                where fit_share is a measure of fit quality, i.e., 0% if unacceptable up to 100% if perfect;
                cap_weight is 0.5 below target and 1.0 otherwise;
                acce_weight is bgAccel_ISF_weight for acceleration away from target, i.e., mostly positive
                or bgBrake_ISF_weight for acceleration towards target, i.e., mostly negative.

                Initially, it was assumed that the weights for accelerating and braking are of similar size.
                First experiences suggest that the weight while decelerating should be 30-40% lower than for acceleration to reduce glucose oscillations. Quite often the acce_ISF contribution plays the dominant role inside autoISF and is therefore very important and delicate.

                Weights for acce_ISF of 0 disable this contribution. Start small with weights like 0.02 and observe the results before increasing them. Keep in mind that negative acceleration will start to happen while glucose is apparently still rising but the slope reduces. Here, acce_ISF will be <1, i.e., sensitivity grows and less insulin than normal will be required even before the glucose peak is reached.
                """)
                    .font(.body)
                    .multilineTextAlignment(.leading)
            }
            Image("acce_flow")
                .resizable()
                .scaledToFit()
                .frame(width: 300)
                .padding(2)
        }
    }

    static let bgAccelISFweightLabel = String(
        localized: "ISF Weight While BG Accelerates", comment: "BG Acceleration ISF Weight"
    )
    static let bgAccelISFweightMini = String(
        localized: "Strengthens ISF decrease while glucose accelerates.",
        comment: "ISF Weight While BG Accelerates miniHint"
    )

    @ViewBuilder static func bgAccelISFweightVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Typical:  0.1 ").bold()
            Text("Strength of acce_ISF contribution with positive acceleration. Start with 0.02 as initial value.")
        }
    }

    static let bgBrakeISFweightLabel = String(
        localized: "ISF Weight While BG Decelerates.", comment: "BG Brake ISF Weight"
    )
    static let bgBrakeISFweightMini = String(
        localized: "Strengthens ISF increase while glucose decelarates.",
        comment: "ISF Weight While BG Accelerates miniHint"
    )

    @ViewBuilder static func bgBrakeISFweightVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Typical:  0.07 ").bold()
            Text("Strength of acce_ISF contribution with negative acceleration.")
        }
    }

    static let higherISFrangeWeightLabel = String(
        localized: "ISF Weight for Higher BGs", comment: "ISF High BG Weight"
    )
    static let higherISFrangeWeightMini = String(
        localized: "This is the weight applied to the polygon which adapts ISF if glucose is above target.",
        comment: "ISF Weight for Higher BGs miniHint"
    )

    @ViewBuilder static func higherISFrangeWeightVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Typical: 0.4").bold()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("""
                    Used above target, strengthens ISF the more the higher this weight is. 0 disables this contribution, i.e., ISF is constant in the whole range above target.

                    Start with a weight of 0.2 and observe the reactions.

                    There are indicators that higher glucose needs stronger ISF. This was evident from all the successful AAPS users defining automation rules which strengthen the profile at higher glucose levels. The drawback is that there are sudden jumps in ISF at switch points and no further or minor adaptations in between.

                    In autoISF a polygon is provided that defines a relationship between glucose and ISF and interpolates in between. This is currently hard coded but the user can apply weights to easily strengthen or weaken it in order to fit personal needs. In principle the polygon itself can be edited and the apk rebuilt if a different shape is required. Developing a GUI for that purpose was considered very tedious especially before knowing whether the results warrant the effort. With this approach you could even approximate the formula well enough that is used in DynamicISF for the ISF dependency on glucose.

                    There is a special case possible, namely below target i.e. when bg_ISF < 1. ISF will be weakened and there is no point in checking the remaining effects. Only with positive acceleration the weakening will be less pronounced as that is a sign of rising glucose to come soon.
                    """)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                }
            }
            Image("bgISF_flow")
                .resizable()
                .scaledToFit()
                .frame(width: 300)
                .padding(2)
        }
    }

    static let lowerISFrangeWeightLabel = String(
        localized: "ISF Weight for Lower BGs", comment: "ISF Low BG Weight"
    )
    static let lowerISFrangeWeightMini = String(
        localized: "This is the weight applied to the polygon which adapts ISF if glucose is below target.",
        comment: "ISF Weight for Lower BGs miniHint"
    )

    @ViewBuilder static func lowerISFrangeWeightVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Typical: 0.6").bold()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("""
                    Used below target, weakens ISF the more the higher this weight is. 0 disables this contribution, i.e., ISF is constant in the whole range below target. This weight is less critical as the loop is probably running at Temp basal Rate = 0 anyway and you can start around 0.2.
                    """)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }

    static let postMealISFweightLabel = String(
        localized: "ISF Weight for Postprandial BG Rise", comment: "Postprandial ISF weight"
    )
    static let postMealISFweightMini = String(
        localized: "This is the weight applied to the linear slope while glucose rises and adapts ISF. With 0 this contribution is effectively disabled. Start with 0.01 - it hardly goes beyond 0.05!",
        comment: "ISF weight for postprandial BG rise miniHint"
    )

    @ViewBuilder static func postMealISFweightVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Typical: 0.02").bold()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("""
                    autoISF can adapt ISF based on glucose delta. It was introduced to help users with gastroparesis. It is also useful for users in pure UAM mode because in their case no meal start can be detected. Given a positive short_avgdelta and glucose being above target+10, the result is:

                    pp_ISF = 1 + delta * pp_ISF_weight.

                    As a starting value for pp_ISF_weight, use 0.005. Observe the reactions and check the Enacted Popup before you increase it with care. A weight of 0 disables this contribution.
                    """)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }

    static let autoISFhourlyChangeLabel = String(localized: "DuraISF Weight", comment: "DuraISF Weight")
    static let autoISFhourlyChangeMini = String(
        localized: "Rate at which ISF is reduced per hour assuming BG level remains at double target for that time.",
        comment: "DuraISF Weight miniHint"
    )

    @ViewBuilder static func autoISFhourlyChangeVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Typical: 0.6").bold()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("""
                    This is the original effect of autoISF in action since August 2020. Because autoISF is now a toolbox of several effects, this original effect was renamed dura_ISF. It addresses situations when:
                    """)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                    BulletList(
                        listItems: [
                            "Glucose is varying within a +/- 5% interval only.",
                            "The average glucose (dura_ISF_average) within that interval is above target.",
                            "This situation lasted at least for the last 10 minutes (dura_ISF_minutes)."
                        ],
                        listItemSpacing: 10
                    )
                    Text("""
                    This is a classical insulin resistance and is typically caused by free fatty acids which grab available insulin before glucose can. Quite often, users get impatient in such a situation and administer one or even more rage boluses. Again and again, that leads to hypos later which the dura_ISF approach avoids if carefully tuned.

                    The strengthening of ISF is stronger the longer the situation lasts and the higher the average glucose is above target:

                    dura_ISF = 1 + (avg05 - target_bg) / target_bg * dura05 * dura_ISF_weight

                    where:
                    avg05 = dura_ISF_average
                    dura05 = dura_ISF_minutes

                    The user can apply his personal weighting by using dura_ISF_weight. Start cautiously with a value of 0.2 and be very careful when you approach 1.5 or even higher. By using 0 this effect is disabled.
                    """)
                        .font(.body)
                        .multilineTextAlignment(.leading)
                    Image("duraISF_flow")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 300)
                        .padding(2)
                }
            }
        }
    }

    /// autoISF-context SMB delivery ratio (fixed). AlgorithmAdvanced has its own separate entry.
    static let smbDeliveryRatioFixedLabel = String(localized: "SMB DeliveryRatio (fixed)", comment: "SMB DeliveryRatio")
    static let smbDeliveryRatioFixedHintLabel = String(localized: "SMB DeliveryRatio", comment: "SMB DeliveryRatio")
    static let smbDeliveryRatioFixedMini = String(
        localized: "This is another key OpenAPS safety cap, and specifies what share of the total insulin required can be delivered as SMB.",
        comment: "SMB DeliveryRatio miniHint"
    )

    @ViewBuilder static func smbDeliveryRatioFixedVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 0.5").bold()
            Text(
                "In oref smb_delivery_ratio is normally hard coded as 0.5 of the insulin requested. This is a safety feature for master/follower setups in case both phones trigger an SMB in the same situation. If this does not apply in your case you may increase this setting to a value above 0.5 and up to even 1.0 if you are very courageous."
            )
        }
    }

    static let smbDeliveryRatioBGrangeLabel = String(
        localized: "SMB DeliveryRatio BG Range", comment: "SMB DeliveryRatio BG Range"
    )
    static func smbDeliveryRatioBGrangeMini(units: GlucoseUnits) -> String {
        String(
            localized: "How far above your BG target the delivery ratio ramps up. Sensible values are \(units == .mgdL ? "40" : 40.formattedAsMmolL)–\(units == .mgdL ? "120" : 120.formattedAsMmolL) \(units.rawValue). Set to 0 to disable the ramp and use the fixed SMB DeliveryRatio instead.",
            comment: "SMB DeliveryRatio BG Range miniHint"
        )
    }

    @ViewBuilder static func smbDeliveryRatioBGrangeVerbose(units: GlucoseUnits) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Typical: \(units == .mgdL ? "90" : 90.formattedAsMmolL) \(units.rawValue)")
                .bold()
            Text(
                "Instead of a single fixed ratio, the delivery ratio can rise linearly with glucose: starting cautiously at SMB DeliveryRatio BG Minimum when glucose is at your BG target, and reaching the more ambitious SMB DeliveryRatio BG Maximum once glucose is this many points above target."
            )
            Text(
                "A wider range makes SMBs ramp up more gradually; a narrower range makes them reach full aggression sooner."
            )
            Text("Set to 0 to disable the ramp — the fixed SMB DeliveryRatio is used instead.")
            Text(
                "Full-Loop exception: when autoISF's full-loop mode is active (an even-numbered temp target below 100 mg/dL, e.g. 80 or 90, signalling you want maximum SMB power), the delivery ratio becomes the greater of the fixed ratio and the ramp value — so the fixed ratio acts as a floor and the ramp can only raise it further."
            )
        }
    }

    static let smbDeliveryRatioMinLabel = String(
        localized: "SMB DeliveryRatio BG Minimum", comment: "SMB DeliveryRatio Minimum"
    )
    static let smbDeliveryRatioMinMini = String(
        localized: "Default value: 0.5 This is the lower end of a linearly increasing SMB Delivery Ratio rather than the fix value above in SMB DeliveryRatio.",
        comment: "SMB DeliveryRatio Minimum miniHint"
    )

    @ViewBuilder static func smbDeliveryRatioMinVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 0.5").bold()
            Text(
                "Lower end of the linearly increasing SMB delivery ratio. This value is applied at your BG target — i.e. the share of insulinReq delivered as SMB when glucose is right at target."
            )
            Text(
                "Set it conservatively; from here the ratio climbs linearly toward SMB DeliveryRatio BG Maximum as glucose rises across SMB DeliveryRatio BG Range."
            )
            Text("Only active when SMB DeliveryRatio BG Range is non-zero; otherwise the fixed SMB DeliveryRatio applies.")
        }
    }

    static let smbDeliveryRatioMaxLabel = String(
        localized: "SMB DeliveryRatio BG Maximum", comment: "SMB DeliveryRatio Maximum"
    )
    static let smbDeliveryRatioMaxMini = String(
        localized: "Default value: 0.5 This is the higher end of a linearly increasing SMB Delivery Ratio rather than the fix value above in SMB DeliveryRatio.",
        comment: "SMB DeliveryRatio Maximum miniHint"
    )

    @ViewBuilder static func smbDeliveryRatioMaxVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 0.5").bold()
            Text(
                "Upper end of the linearly increasing SMB delivery ratio. Reached once glucose sits at BG target plus SMB DeliveryRatio BG Range — i.e. the maximum share of insulinReq delivered as SMB when glucose is deep above target."
            )
            Text(
                "Values above 0.5 make SMBs more aggressive at high glucose. Raise with care; the ratio climbs linearly from SMB DeliveryRatio BG Minimum up to this value."
            )
            Text("Only active when SMB DeliveryRatio BG Range is non-zero; otherwise the fixed SMB DeliveryRatio applies.")
        }
    }

    static let smbMaxRangeExtensionLabel = String(
        localized: "SMB Max RangeExtension", comment: "SMB Max RangeExtension"
    )
    static let smbMaxRangeExtensionMini = String(
        localized: "This specifies by what factor you can exceed the limit of 180 maxSMB/maxUAM minutes.",
        comment: "SMB Max RangeExtension miniHint"
    )

    @ViewBuilder static func smbMaxRangeExtensionVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 1").bold()
            Text(
                "A factor that multiplies the current maxSMBBasalMinutes and maxUAM/SMBBasalMinutes beyond the 180 minute limit set in Trio."
            )
        }
    }

    // MARK: - Algorithm Advanced

    static let useProfileCSFLabel = String(localized: "Use Profile CSF", comment: "Use Profile CSF")
    static let useProfileCSFMini = String(
        localized: "Calculate CSF from profile CR and ISF.",
        comment: "Mini hint for Use Profile CSF"
    )

    @ViewBuilder static func useProfileCSFVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: OFF").bold()
            Text(
                "Important: Enabling this setting changes how the algorithm handles carb absorption. Review your algorithm and therapy settings, and consider starting with a higher glucose target while you adjust. Settings will generally need to be less aggressive, as the stable CSF combined with a reduced CR in insulin resistance situations can increase insulin dosing for meals."
            ).bold()
            Text(
                "Note: If \"Low Target Lowers Sensitivity\" is active, using an \"Eating Soon\" temporary target will be more aggressive than before. The lower target reduces ISF, which with a now reduced CR also increases meal insulin dosing. Review your targets and sensitivity settings accordingly."
            ).bold()
            Text(
                "When enabled, oref will calculate CSF (Carb Sensitivity Factor) from your profile's Carb Ratio and profile's Insulin Sensitivity Factor, keeping CSF stable as a profile-based value."
            )
            Text(
                "This makes CSF independent of short-term ISF changes that occur with features like Dynamic ISF, autoISF, or Autosens."
            )
            VStack(alignment: .leading, spacing: 5) {
                Text("What is CSF?").bold()
                Text(
                    "Carb Sensitivity Factor (CSF) represents how much your blood glucose rises per gram of carbohydrate consumed. It is calculated as: CSF = ISF / CR (Insulin Sensitivity Factor divided by Carb Ratio)."
                )
                Text(
                    "CSF describes the digestive process of carbs entering your bloodstream as glucose. This process is not dependent on insulin sensitivity, which describes a different process: removing glucose from the blood."
                )
                Text(
                    "In the algorithm, CSF is used to estimate carb absorption rates, convert carb impact to grams absorbed, project remaining carb absorption, and calculate carbs required to prevent lows. With this setting enabled, all of these calculations use a stable, profile-based CSF."
                )
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Why is CSF not dependent on ISF when this setting is enabled?").bold()
                Text(
                    "Normally, CSF is calculated using the current dynamic ISF value, which can change frequently based on algorithms like Dynamic ISF, autoISF, or Autosens. This can cause CSF to fluctuate as your ISF adjusts."
                )
                Text(
                    "With this setting enabled, CSF is calculated using your static profile ISF value instead, ensuring CSF remains constant and predictable, unaffected by temporary ISF adjustments."
                )
                Text(
                    "This also means that when calculating meal insulin, your Carb Ratio effectively becomes dynamic: since CR = ISF / CSF and CSF is held constant, CR automatically adjusts as ISF changes throughout the day. Some refer to this as \"dynamic CR\"."
                )
            }
        }
    }

    static let maxDailySafetyMultiplierLabel = String(
        localized: "Max Daily Safety Multiplier", comment: "Max Daily Safety Multiplier"
    )
    static let maxDailySafetyMultiplierMini = String(
        localized: "Limits temporary basal rates to this percentage of your largest basal rate.",
        comment: "Mini Hint for Max Daily Safety Multiplier"
    )

    @ViewBuilder static func maxDailySafetyMultiplierVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 300%").bold()
            Text(
                "This setting restricts the maximum temporary basal rate Trio can set. At the default of 300%, it caps it at 3 times your highest programmed basal rate."
            )
            Text("It serves as a safety limit, ensuring no temporary basal rates exceed safe levels.")
            Text("Warning: Increasing this setting is not advised.").bold()
        }
    }

    static let currentBasalSafetyMultiplierLabel = String(
        localized: "Current Basal Safety Multiplier", comment: "Current Basal Safety Multiplier"
    )
    static let currentBasalSafetyMultiplierMini = String(
        localized: "Limits temporary basal rates to this percentage of the current basal rate.",
        comment: "Mini Hint for Current Basal Safety Multiplier"
    )

    @ViewBuilder static func currentBasalSafetyMultiplierVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 400%").bold()
            Text(
                "This limits the automatic adjustment of the temporary basal rate to this percentage of the current hourly profile basal rate at the time of the loop cycle."
            )
            Text("This prevents excessive dosing, especially during times of variable insulin sensitivity, enhancing safety.")
            Text("Warning: Increasing this setting is not advised.").bold()
        }
    }

    static let skipNeutralTempsLabel = String(localized: "Skip Neutral Temps", comment: "Skip Neutral Temps")
    static let skipNeutralTempsMini = String(
        localized: "Skip neutral temporary basal rates to reduce MDT pump alerts.",
        comment: "Mini Hint for Skip Neutral Temps"
    )

    @ViewBuilder static func skipNeutralTempsVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: OFF").bold()
            Text(
                "When Skip Neutral Temps is enabled, Trio will not set neutral basal rates shortly before the hour, minimizing hourly pump alerts on MDT pumps. This can help light sleepers avoid alerts but will delay basal adjustments. This will also only come into effect if SMB's are disabled for whatever reason."
            )
            Text(
                "For most users, leaving this OFF is recommended to ensure consistent basal delivery and loop calculation. If this option is effective, loops will be skipped during the last 5 minutes of the hour."
            )
        }
    }

    static let unsuspendIfNoTempLabel = String(localized: "Unsuspend If No Temp", comment: "Unsuspend If No Temp")
    static let unsuspendIfNoTempMini = String(
        localized: "Resume pump automatically after suspension.",
        comment: "Mini Hint for Unsuspend If No Temp"
    )

    @ViewBuilder static func unsuspendIfNoTempVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: OFF").bold()
            Text(
                "Enabling Unsuspend If No Temp allows Trio to resume your pump if you forget, as long as a zero temp basal was set first. This feature ensures insulin delivery restarts if you forget to manually unsuspend, adding a safeguard for pump reconnections."
            )
            Text("Note: Applies only to pumps with on-pump suspend options")
        }
    }

    /// AlgorithmAdvanced-context SMB delivery ratio. AutoISF has a different variant
    /// (`smbDeliveryRatioFixed*`).
    static let smbDeliveryRatioLabel = String(localized: "SMB Delivery Ratio", comment: "SMB Delivery Ratio")
    static let smbDeliveryRatioMini = String(
        localized: "Percentage of calculated insulin required that is given as SMB.",
        comment: "Mini-hint for SMB Delivery Ratio (AlgorithmAdvanced) setting"
    )

    @ViewBuilder static func smbDeliveryRatioVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 50%").bold()
            Text(
                "Once the total insulin required is calculated, this safety limit specifies what percentage of the insulin required can be delivered as an SMB."
            )
            Text(
                "Due to SMBs potentially occurring every 5 minutes with each loop cycle, it is important to set this value to a reasonable level that allows Trio to safely zero temp should dosing needs suddenly change. Increase this value with caution."
            )
            Text("Note: Allowed range is 30 - 70%")
        }
    }

    static let min5mCarbimpactLabel = String(localized: "Min 5m Carb Impact", comment: "Min 5m Carb Impact")
    static let min5mCarbimpactMini = String(
        localized: "Default impact of carb absorption over a 5 minute interval.",
        comment: "Mini-hint for Min 5m Carb Impact setting"
    )

    @ViewBuilder static func min5mCarbimpactVerbose(units: GlucoseUnits) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "Min 5m Carb Impact sets the expected glucose rise from carbs over 5 minutes when absorption isn't obvious from glucose data."
            )
            Text(
                "The default is an expected \(units == .mgdL ? "8" : 8.formattedAsMmolL) \(units.rawValue)/5min. This affects how fast COB is decayed in situations when carb absorption is not visible in BG deviations. The default of \(units == .mgdL ? "8" : 8.formattedAsMmolL) \(units.rawValue)/5min corresponds to a minimum carb absorption rate of 24 g/hr at a CSF of \(units == .mgdL ? "4" : 4.formattedAsMmolL) \(units.rawValue)/g."
            )
            Text(
                "This setting helps the system estimate how much glucose your body is absorbing, even when it's not immediately visible in your glucose data, ensuring more accurate insulin dosing during carb absorption."
            )
        }
    }

    static let remainingCarbsFractionLabel = String(
        localized: "Remaining Carbs Percentage", comment: "Remaining Carbs Percentage"
    )
    static let remainingCarbsFractionMini = String(
        localized: "Percentage of carbs still available if no absorption is detected.",
        comment: "Mini Hint for Remaining Carbs Percentage"
    )

    @ViewBuilder static func remainingCarbsFractionVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 100%").bold()
            Text(
                "Remaining Carbs Percentage estimates carbs still absorbing over 4 hours if glucose data doesn't show clear absorption."
            )
            Text(
                "This fallback setting prevents under-dosing by spreading a portion of the entered carbs over time, balancing insulin needs with undetected carb impact."
            )
        }
    }

    static let remainingCarbsCapLabel = String(localized: "Remaining Carbs Cap", comment: "Remaining Carbs Cap")
    static let remainingCarbsCapMini = String(
        localized: "Maximum amount of carbs still available if no absorption is detected.",
        comment: "Mini hint for Remaining Carbs Cap"
    )

    @ViewBuilder static func remainingCarbsCapVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 90 g").bold()
            Text(
                "The Remaining Carbs Cap defines the upper limit for how many carbs the system will assume are absorbing over 4 hours, even when there's no clear sign of absorption from your glucose readings."
            )
            Text(
                "This cap prevents the system from overestimating how much insulin is needed when carb absorption isn't visible, offering a safeguard for accurate dosing."
            )
        }
    }

    static let noisyCGMTargetMultiplierLabel = String(
        localized: "Noisy CGM Target Increase", comment: "Noisy CGM Target Increase"
    )
    static let noisyCGMTargetMultiplierHintLabel = String(
        localized: "Noisy CGM Target Multiplier", comment: "Noisy CGM Target Multiplier"
    )
    static let noisyCGMTargetMultiplierMini = String(
        localized: "Percentage increase of glucose target when CGM is inconsistent.",
        comment: "Mini Hint for Noisy CGM Target Increase"
    )

    @ViewBuilder static func noisyCGMTargetMultiplierVerbose() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Default: 130%").bold()
            Text(
                "The Noisy CGM Target Increase raises your glucose target when the system detects noisy or raw CGM data. By default, the target is increased to 130% of your set target glucose to account for the less reliable glucose readings."
            )
            Text(
                "This helps reduce the risk of incorrect insulin dosing based on inaccurate sensor data, ensuring safer insulin adjustments during periods of poor CGM accuracy."
            )
            Text("Note: A CGM is considered noisy when it provides inconsistent readings.")
        }
    }

    // MARK: - B30

    static let enableB30Label = String(localized: "Activate B30 EatingSoon", comment: "Enable B30")
    static let enableB30Mini = String(
        localized: "Enables an increased basal rate after an EatingSoon TT and a manual bolus to saturate the infusion site with insulin.",
        comment: "Enable B30 miniHint"
    )

    @ViewBuilder static func enableB30Verbose() -> some View {
        VStack(alignment: .leading) {
            Text(
                "Enables an increased basal rate after an EatingSoon TT and a manual bolus to saturate the infusion site with insulin to increase insulin absorption for SMB's following a meal with no carb counting."
            )
            BulletList(
                listItems: [
                    "needs an EatingSoon TempTarget (TT) with a specific GlucoseTarget",
                    "in order to activate B30 a minimum manual Bolus needs to be given",
                    "you can specify how long B30 run and how high it is",
                    "while B30 TBR runs no SMB's will be enacted",
                    "TBR ignores maxBasal multipliers, but respects maxBasal of pump",
                    "once activated you can stop the B30 TBR and allowing SMB's by just cancelling the TT"
                ],
                listItemSpacing: 10
            )
            Text(
                "Initiating B30 can be done by Apple Shortcuts\nhttps://tinyurl.com/aimiB30shortcut\n"
            )
        }
    }

    static let b30iTimeTargetLabel = String(localized: "TempTarget Level for B30", comment: "B30 TT Level")
    static let b30iTimeTargetMini = String(
        localized: "An EatingSoon TempTarget needs to be enabled to start B30 adaption. Set level for this target to be identified.",
        comment: "B30 TT Level miniHint"
    )

    @ViewBuilder static func b30iTimeTargetVerbose(units: GlucoseUnits) -> some View {
        Text(
            String(
                localized: "Set the EatingSoon TempTarget glucose level to trigger B30. Should be a low TT like \(units == .mgdL ? "80" : 80.formattedAsMmolL) \(units.rawValue). Keep in mind it should be an even TT to allow autoISF SMB's after the duration specified, if the target would still be active. Canceling this TT will imediatly stop B30 adaptions.",
                comment: "B30 TT Level VerboseHint"
            )
        )
    }

    static let b30iTimeStartBolusLabel = String(localized: "Minimum Start Bolus Size", comment: "B30 Start Bolus")
    static let b30iTimeStartBolusMini = String(
        localized: "Minimum manual bolus to start a B30 adaption.",
        comment: "B30 Start Bolus miniHint"
    )

    @ViewBuilder static func b30iTimeStartBolusVerbose() -> some View {
        Text(
            String(
                localized: "Specify the minimum bolus size required to trigger B30.",
                comment: "B30 Start Bolus VerboseHint"
            )
        )
    }

    static let b30iTimeLabel = String(localized: "Duration of Increased B30 Basal Rate", comment: "B30 Duration")
    static let b30iTimeMini = String(
        localized: "Duration of increased basal rate that saturates the infusion site with insulin. Default 30 minutes.",
        comment: "B30 Duration miniHint"
    )

    @ViewBuilder static func b30iTimeVerbose() -> some View {
        Text(
            String(
                localized: "Set the duration for the increased basal rate in B30 mode. Default is 30 minutes.",
                comment: "B30 Duration VerboseHint"
            )
        )
    }

    static let b30basalFactorLabel = String(localized: "B30 Basal Rate Increase Factor", comment: "B30 Factor")
    static let b30basalFactorMini = String(
        localized: "Factor that multiplies your regular basal rate from profile for B30. Max is 10. The TBR will ignore the maxBasalMultipliers but respect maxBasal setting!",
        comment: "B30 Factor miniHint"
    )

    @ViewBuilder static func b30basalFactorVerbose() -> some View {
        Text(
            String(
                localized: "Specify the factor to increase the basal rate during B30. Max is 10x.",
                comment: "B30 Factor VerboseHint"
            )
        )
    }

    static let b30upperLimitLabel = String(localized: "Upper BG Limit for B30", comment: "B30 Upper BG Limit")
    static func b30upperLimitMini(units: GlucoseUnits) -> String {
        String(
            localized: "B30 will only run & supress SMB as long as BG stays underneath that level. Default is \(units == .mgdL ? "130" : 130.formattedAsMmolL) \(units.rawValue).",
            comment: "B30 Upper BG Limit miniHint"
        )
    }

    @ViewBuilder static func b30upperLimitVerbose(units: GlucoseUnits) -> some View {
        Text(
            String(
                localized: "Set the maximum BG level for B30 & suppressed SMB to remain active. Default is \(units == .mgdL ? "130" : 130.formattedAsMmolL) \(units.rawValue).",
                comment: "B30 Upper BG Limit VerboseHint"
            )
        )
    }

    static let b30upperDeltaLabel = String(localized: "Upper Delta Limit for B30", comment: "B30 Upper Delta")
    static func b30upperDeltaMini(units: GlucoseUnits) -> String {
        String(
            localized: "B30 will only run & supress SMB's as long as BG delta stays below that level. Default is \(units == .mgdL ? "8" : 8.formattedAsMmolL) \(units.rawValue).",
            comment: "B30 Upper Delta miniHint"
        )
    }

    @ViewBuilder static func b30upperDeltaVerbose(units: GlucoseUnits) -> some View {
        Text(
            String(
                localized: "Set the maximum BG delta limit for B30 & suppressed SMB to remain active. Default is \(units == .mgdL ? "8" : 8.formattedAsMmolL) \(units.rawValue).",
                comment: "B30 Upper Delta VerboseHint"
            )
        )
    }

    // MARK: - Keto Protection

    static let ketoProtectLabel = String(localized: "Activate KetoProtection", comment: "Enable KetoProtection")
    static let ketoProtectMini = String(
        localized: "This feature enables a small safety Temp Basal Rate (TBR) to reduce ketoacidosis risk. Without the Variable Protection, the safety TBR is always applied.",
        comment: "Mini-hint for Activate KetoProtection setting"
    )

    @ViewBuilder static func ketoProtectVerbose() -> some View {
        Text(
            String(
                localized: "Ketoacidosis protection will apply a small configurable Temp Basal Rate (TBR) instead of a Zero Temp. This is done either always or if certain conditions arise. For the later you need to enable the Variable KetoProtect Strategy.",
                comment: "KetoProtect VerboseHint"
            )
        )
    }

    static let variableKetoProtectLabel = String(localized: "Variable Strategy", comment: "Variable Keto Protection")
    static let variableKetoProtectMini = String(
        localized: "In addition to the Zero Temp the activiation of KetoProtect is dependant on IOB levels and last Active Insulin.",
        comment: "Variable protection miniHint"
    )

    @ViewBuilder static func variableKetoProtectVerbose() -> some View {
        Text(
            String(
                localized: "Activated: Safety TBR only kicks in when IOB is in neg. range below current Basal Rate and Active Insulin is also negative.",
                comment: "Variable Protection VerboseHint"
            )
        )
    }

    static let ketoProtectBasalPercentLabel = String(localized: "Safety TBR in %", comment: "Safety TBR")
    static let ketoProtectBasalPercentMini = String(
        localized: "Quantity of the small safety TBR in % of Profile BR, which is given to avoid ketoacidosis.",
        comment: "Safety TBR miniHint"
    )

    @ViewBuilder static func ketoProtectBasalPercentVerbose() -> some View {
        Text(
            String(
                localized: "Set the percentage of the current basal rate to apply for safety against ketoacidosis. Recommended between 10% - 20%",
                comment: "Safety TBR VerboseHint"
            )
        )
    }

    static let ketoProtectAbsolutLabel = String(localized: "Enable Absolute Safety TBR", comment: "Enable Absolute TBR")
    static let ketoProtectAbsolutMini = String(
        localized: "Specify an absolute TBR between 0 and 2 U/hr instead of a percentage of the current basal rate.",
        comment: "Enable Absolute Safety TBR miniHint"
    )

    @ViewBuilder static func ketoProtectAbsolutVerbose() -> some View {
        Text(
            String(
                localized: "Absolute safety TBR provides a fixed insulin rate for safety, useful for consistent protection.",
                comment: "Absolute TBR VerboseHint"
            )
        )
    }

    static let ketoProtectBasalAbsolutLabel = String(localized: "Absolute Safety TBR", comment: "Absolute TBR")
    static let ketoProtectBasalAbsolutMini = String(
        localized: "Amount in U/hr of small safety TBR to avoid ketoacidosis.",
        comment: "Absolute Safety TBR miniHint"
    )

    @ViewBuilder static func ketoProtectBasalAbsolutVerbose() -> some View {
        Text(
            String(
                localized: "Specify a fixed basal rate for safety against ketoacidosis.",
                comment: "Absolute TBR VerboseHint"
            )
        )
    }
}
