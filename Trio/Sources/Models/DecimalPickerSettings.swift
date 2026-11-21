import SwiftUI
import Swinject

class PickerSettingsProvider: ObservableObject, Injectable {
    static let shared = PickerSettingsProvider()

    @Injected() private var settingsManager: SettingsManager!

    private init() {} // Private init to enforce singleton pattern

    // Add this method to configure dependency injection
    func configure(resolver: Resolver) {
        injectServices(resolver)
    }

    var preferences: Preferences { settingsManager.preferences }

    var settings: DecimalPickerSettings {
        let bolusIncrementValue = preferences.bolusIncrement
        return DecimalPickerSettings(bolusIncrementValue: bolusIncrementValue)
    }

    /// Looks up a `PickerSetting` by its `DecimalPickerSettings` property name. Used by views that
    /// reference settings by string key (e.g. `SettingInputSection`, override forms) so all picker
    /// rows source bounds from the same place.
    func pickerSetting(for key: String) -> PickerSetting? {
        let s = settings
        switch key {
        case "carbsRequiredThreshold": return s.carbsRequiredThreshold
        case "individualAdjustmentFactor": return s.individualAdjustmentFactor
        case "delay": return s.delay
        case "timeCap": return s.timeCap
        case "minuteInterval": return s.minuteInterval
        case "high": return s.high
        case "low": return s.low
        case "hours": return s.hours
        case "maxCarbs": return s.maxCarbs
        case "maxMealAbsorptionTime": return s.maxMealAbsorptionTime
        case "maxFat": return s.maxFat
        case "maxProtein": return s.maxProtein
        case "overrideFactor": return s.overrideFactor
        case "fattyMealFactor": return s.fattyMealFactor
        case "sweetMealFactor": return s.sweetMealFactor
        case "maxIOB": return s.maxIOB
        case "maxDailySafetyMultiplier": return s.maxDailySafetyMultiplier
        case "currentBasalSafetyMultiplier": return s.currentBasalSafetyMultiplier
        case "autosensMax": return s.autosensMax
        case "autosensMin": return s.autosensMin
        case "sub5MinuteLoopInterval": return s.sub5MinuteLoopInterval
        case "autoISFParabolaMinMinutes": return s.autoISFParabolaMinMinutes
        case "smbDeliveryRatio": return s.smbDeliveryRatio
        case "smbThresholdRatio": return s.smbThresholdRatio
        case "halfBasalExerciseTarget": return s.halfBasalExerciseTarget
        case "maxCOB": return s.maxCOB
        case "min5mCarbimpact": return s.min5mCarbimpact
        case "remainingCarbsFraction": return s.remainingCarbsFraction
        case "remainingCarbsCap": return s.remainingCarbsCap
        case "maxSMBBasalMinutes": return s.maxSMBBasalMinutes
        case "maxUAMSMBBasalMinutes": return s.maxUAMSMBBasalMinutes
        case "smbInterval": return s.smbInterval
        case "insulinPeakTime": return s.insulinPeakTime
        case "carbsReqThreshold": return s.carbsReqThreshold
        case "noisyCGMTargetMultiplier": return s.noisyCGMTargetMultiplier
        case "maxDeltaBGthreshold": return s.maxDeltaBGthreshold
        case "adjustmentFactor": return s.adjustmentFactor
        case "adjustmentFactorSigmoid": return s.adjustmentFactorSigmoid
        case "weightPercentage": return s.weightPercentage
        case "enableSMB_high_bg_target": return s.enableSMB_high_bg_target
        case "threshold_setting": return s.threshold_setting
        case "updateInterval": return s.updateInterval
        case "dia": return s.dia
        case "maxBolus": return s.maxBolus
        case "maxBasal": return s.maxBasal
        case "autoISFmax": return s.autoISFmax
        case "autoISFmin": return s.autoISFmin
        case "smbMaxRangeExtension": return s.smbMaxRangeExtension
        case "smbDeliveryRatioBGrange": return s.smbDeliveryRatioBGrange
        case "smbDeliveryRatioMin": return s.smbDeliveryRatioMin
        case "smbDeliveryRatioMax": return s.smbDeliveryRatioMax
        case "autoISFhourlyChange": return s.autoISFhourlyChange
        case "higherISFrangeWeight": return s.higherISFrangeWeight
        case "lowerISFrangeWeight": return s.lowerISFrangeWeight
        case "deltaISFrangeWeight": return s.deltaISFrangeWeight
        case "postMealISFweight": return s.postMealISFweight
        case "bgAccelISFweight": return s.bgAccelISFweight
        case "bgBrakeISFweight": return s.bgBrakeISFweight
        case "iobThresholdPercent": return s.iobThresholdPercent
        case "B30iTimeStartBolus": return s.B30iTimeStartBolus
        case "B30iTime": return s.B30iTime
        case "B30iTimeTarget": return s.B30iTimeTarget
        case "B30upperLimit": return s.B30upperLimit
        case "B30upperDelta": return s.B30upperDelta
        case "B30basalFactor": return s.B30basalFactor
        case "ketoProtectBasalPercent": return s.ketoProtectBasalPercent
        case "ketoProtectBasalAbsolut": return s.ketoProtectBasalAbsolut
        case "therapyAdjustment": return s.therapyAdjustment
        default: return nil
        }
    }

    // Helper function to generate values for the picker
    func generatePickerValues(from setting: PickerSetting, units: GlucoseUnits) -> [Decimal] {
        var values: [Decimal] = []
        var currentValue = setting.min

        while currentValue <= setting.max {
            values.append(currentValue)
            currentValue += setting.step
        }

        // Glucose values are stored as mg/dl values, so Integers.
        // Filter out duplicate values when rounded to 1 decimal place.
        if units == .mmolL, setting.type == PickerSetting.PickerSettingType.glucose {
            // Use a Set to track unique values rounded to 1 decimal
            var uniqueRoundedValues = Set<String>()
            values = values.filter { value in
                let roundedValue = String(format: "%.1f", NSDecimalNumber(decimal: value.asMmolL).doubleValue)
                return uniqueRoundedValues.insert(roundedValue).inserted
            }
        }

        return values
    }
}

struct DecimalPickerSettings {
    static let overridePercentageMin: Decimal = 40
    static let overridePercentageMax: Decimal = 200
    static let tempTargetGlucoseMin: Decimal = 80
    static let tempTargetGlucoseMax: Decimal = 200

    var carbsRequiredThreshold = PickerSetting(value: 10, step: 1, min: 0, max: 100, type: PickerSetting.PickerSettingType.gram)
    var individualAdjustmentFactor = PickerSetting(
        value: 0.5,
        step: 0.05,
        min: 0.1,
        max: 1.2,
        type: PickerSetting.PickerSettingType.factor
    )
    var high = PickerSetting(value: 180, step: 1, min: 100, max: 400, type: PickerSetting.PickerSettingType.glucose)
    var low = PickerSetting(value: 70, step: 1, min: 40, max: 100, type: PickerSetting.PickerSettingType.glucose)
    var maxCarbs = PickerSetting(value: 250, step: 5, min: 0, max: 300, type: PickerSetting.PickerSettingType.gram)
    var maxFat = PickerSetting(value: 250, step: 5, min: 0, max: 300, type: PickerSetting.PickerSettingType.gram)
    var maxProtein = PickerSetting(value: 250, step: 5, min: 0, max: 300, type: PickerSetting.PickerSettingType.gram)
    var overrideFactor = PickerSetting(value: 0.8, step: 0.05, min: 0.05, max: 1.5, type: PickerSetting.PickerSettingType.factor)
    var fattyMealFactor = PickerSetting(value: 0.7, step: 0.05, min: 0.05, max: 1, type: PickerSetting.PickerSettingType.factor)
    var sweetMealFactor = PickerSetting(value: 1, step: 0.05, min: 0.05, max: 2, type: PickerSetting.PickerSettingType.factor)

    // maxIOB now uses calculated step based on bolusIncrement
    var maxIOB: PickerSetting

    var maxDailySafetyMultiplier = PickerSetting(
        value: 3,
        step: 0.1,
        min: 1,
        max: 10,
        type: PickerSetting.PickerSettingType.factor
    )
    var currentBasalSafetyMultiplier = PickerSetting(
        value: 4,
        step: 0.1,
        min: 1,
        max: 10,
        type: PickerSetting.PickerSettingType.factor
    )
    var autosensMax = PickerSetting(value: 1.2, step: 0.1, min: 0.5, max: 3, type: PickerSetting.PickerSettingType.factor)
    var autosensMin = PickerSetting(value: 0.7, step: 0.1, min: 0.5, max: 1, type: PickerSetting.PickerSettingType.factor)
    var sub5MinuteLoopInterval = PickerSetting(value: 5, step: 1, min: 1, max: 10, type: .minute)
    var autoISFParabolaMinMinutes = PickerSetting(value: 15, step: 1, min: 5, max: 20, type: .minute)
    var smbDeliveryRatio = PickerSetting(value: 0.5, step: 0.05, min: 0.1, max: 1.5, type: PickerSetting.PickerSettingType.factor)
    var smbThresholdRatio = PickerSetting(value: 0.5, step: 0.05, min: 0.5, max: 1, type: PickerSetting.PickerSettingType.factor)
    var halfBasalExerciseTarget = PickerSetting(
        value: 160,
        step: 5,
        min: 105, // must be >100 to work mathematically, 5mg/dl steps are fine enough as this is just a calculation helper value
        max: 300,
        type: PickerSetting.PickerSettingType.glucose
    )
    var maxCOB = PickerSetting(value: 120, step: 5, min: 0, max: 300, type: PickerSetting.PickerSettingType.gram)
    var maxMealAbsorptionTime = PickerSetting(value: 6, step: 1, min: 4, max: 10, type: PickerSetting.PickerSettingType.hour)
    var min5mCarbimpact = PickerSetting(value: 8, step: 1, min: 1, max: 20, type: PickerSetting.PickerSettingType.glucose)
    var remainingCarbsFraction = PickerSetting(
        value: 1.0,
        step: 0.05,
        min: 0.5,
        max: 1,
        type: PickerSetting.PickerSettingType.factor
    )
    var remainingCarbsCap = PickerSetting(value: 90, step: 5, min: 0, max: 200, type: PickerSetting.PickerSettingType.gram)
    var maxSMBBasalMinutes = PickerSetting(value: 30, step: 5, min: 15, max: 180, type: PickerSetting.PickerSettingType.minute)
    var maxUAMSMBBasalMinutes = PickerSetting(value: 30, step: 5, min: 15, max: 180, type: PickerSetting.PickerSettingType.minute)
    var smbInterval = PickerSetting(value: 3, step: 1, min: 1, max: 10, type: PickerSetting.PickerSettingType.minute)
    var insulinPeakTime = PickerSetting(value: 75, step: 1, min: 35, max: 120, type: PickerSetting.PickerSettingType.minute)
    var carbsReqThreshold = PickerSetting(value: 1.0, step: 0.1, min: 0, max: 10, type: PickerSetting.PickerSettingType.gram)
    var noisyCGMTargetMultiplier = PickerSetting(
        value: 1.3,
        step: 0.05,
        min: 1,
        max: 2,
        type: PickerSetting.PickerSettingType.factor
    )
    var maxDeltaBGthreshold = PickerSetting(
        value: 0.2,
        step: 0.05,
        min: 0.1,
        max: 0.4,
        type: PickerSetting.PickerSettingType.factor
    )
    var adjustmentFactor = PickerSetting(value: 0.8, step: 0.05, min: 0.3, max: 3.0, type: PickerSetting.PickerSettingType.factor)
    var adjustmentFactorSigmoid = PickerSetting(
        value: 0.5,
        step: 0.05,
        min: 0.1,
        max: 2,
        type: PickerSetting.PickerSettingType.factor
    )
    var weightPercentage = PickerSetting(value: 0.35, step: 0.05, min: 0.05, max: 1, type: PickerSetting.PickerSettingType.factor)
    var enableSMB_high_bg_target = PickerSetting(
        value: 110,
        step: 1,
        min: 70,
        max: 200,
        type: PickerSetting.PickerSettingType.glucose
    )
    var threshold_setting = PickerSetting(value: 60, step: 1, min: 60, max: 120, type: PickerSetting.PickerSettingType.glucose)
    var updateInterval = PickerSetting(value: 20, step: 5, min: 1, max: 60, type: PickerSetting.PickerSettingType.minute)
    var delay = PickerSetting(value: 60, step: 5, min: 15, max: 120, type: PickerSetting.PickerSettingType.minute)
    var minuteInterval = PickerSetting(value: 30, step: 5, min: 10, max: 60, type: PickerSetting.PickerSettingType.minute)
    var timeCap = PickerSetting(value: 8, step: 1, min: 5, max: 12, type: PickerSetting.PickerSettingType.hour)
    var hours = PickerSetting(value: 6, step: 0.5, min: 2, max: 24, type: PickerSetting.PickerSettingType.hour)
    var dia = PickerSetting(value: 10, step: 0.5, min: 5, max: 10, type: PickerSetting.PickerSettingType.hour)
    var carbSensitivity = PickerSetting(value: 40, step: 1, min: 5, max: 200, type: PickerSetting.PickerSettingType.glucose)

    // maxBolus and maxBasal now use calculated step based on bolusIncrement
    var maxBolus: PickerSetting
    var maxBasal: PickerSetting

    // autoISF
    var autoISFmax = PickerSetting(value: 2, step: 0.1, min: 1, max: 4, type: PickerSetting.PickerSettingType.factorRaw)
    var autoISFmin = PickerSetting(value: 0.4, step: 0.1, min: 0.1, max: 1, type: PickerSetting.PickerSettingType.factorRaw)
    var smbMaxRangeExtension = PickerSetting(
        value: 1,
        step: 0.25,
        min: 1,
        max: 5,
        type: PickerSetting.PickerSettingType.factorRaw
    )
    var smbDeliveryRatioBGrange = PickerSetting(
        value: 0,
        step: 10,
        min: 0,
        max: 120,
        type: PickerSetting.PickerSettingType.glucose
    )
    var smbDeliveryRatioMin = PickerSetting(
        value: 0.5,
        step: 0.05,
        min: 0.1,
        max: 1,
        type: PickerSetting.PickerSettingType.factor
    )
    var smbDeliveryRatioMax = PickerSetting(
        value: 0.8,
        step: 0.05,
        min: 0.1,
        max: 1.2,
        type: PickerSetting.PickerSettingType.factor
    )
    var autoISFhourlyChange = PickerSetting(
        value: 0.6,
        step: 0.05,
        min: 0,
        max: 3,
        type: PickerSetting.PickerSettingType.factorRaw
    )
    var higherISFrangeWeight = PickerSetting(
        value: 0.3,
        step: 0.05,
        min: 0,
        max: 2,
        type: PickerSetting.PickerSettingType.factorRaw
    )
    var lowerISFrangeWeight = PickerSetting(
        value: 0.7,
        step: 0.05,
        min: 0,
        max: 2,
        type: PickerSetting.PickerSettingType.factorRaw
    )
    var deltaISFrangeWeight = PickerSetting(
        value: 0.6,
        step: 0.01,
        min: 0,
        max: 1,
        type: PickerSetting.PickerSettingType.factorRaw
    )
    var postMealISFweight = PickerSetting(
        value: 0.02,
        step: 0.005,
        min: 0,
        max: 0.15,
        type: PickerSetting.PickerSettingType.factorRaw
    )
    var bgAccelISFweight = PickerSetting(
        value: 0.15,
        step: 0.01,
        min: 0,
        max: 1,
        type: PickerSetting.PickerSettingType.factorRaw
    )
    var bgBrakeISFweight = PickerSetting(
        value: 0.15,
        step: 0.01,
        min: 0,
        max: 1,
        type: PickerSetting.PickerSettingType.factorRaw
    )
    var iobThresholdPercent = PickerSetting(
        value: 1,
        step: 0.01,
        min: 0,
        max: 1,
        type: PickerSetting.PickerSettingType
            .factor
    )
    // AIMI B30
    var B30iTimeStartBolus = PickerSetting(
        value: 1,
        step: 0.5,
        min: 0.5,
        max: 30,
        type: PickerSetting.PickerSettingType.insulinUnit
    )
    var B30iTime = PickerSetting(value: 30, step: 5, min: 15, max: 60, type: PickerSetting.PickerSettingType.minute)
    var B30iTimeTarget = PickerSetting(value: 90, step: 5, min: 80, max: 120, type: PickerSetting.PickerSettingType.glucose)
    var B30upperLimit = PickerSetting(value: 130, step: 5, min: 110, max: 180, type: PickerSetting.PickerSettingType.glucose)
    var B30upperDelta = PickerSetting(value: 8, step: 1, min: 5, max: 15, type: PickerSetting.PickerSettingType.glucose)
    var B30basalFactor = PickerSetting(value: 5, step: 0.5, min: 1.5, max: 10, type: PickerSetting.PickerSettingType.factorRaw)
    // AdaptProfile — therapy percentage adjustment (like override %)
    var therapyAdjustment = PickerSetting(
        value: 100,
        step: 5,
        min: 40,
        max: 250,
        type: PickerSetting.PickerSettingType.percent
    )
    // KetoProtect
    var ketoProtectBasalPercent = PickerSetting(
        value: 0.2,
        step: 0.05,
        min: 0.05,
        max: 0.5,
        type: PickerSetting.PickerSettingType.factor
    )
    var ketoProtectBasalAbsolut = PickerSetting(
        value: 0.1,
        step: 0.05,
        min: 0.05,
        max: 2,
        type: PickerSetting.PickerSettingType.insulinUnit
    )

    // Initializer that accepts bolusIncrementValue for dynamic step calculation
    init(bolusIncrementValue: Decimal = 0.1) {
        // Initialize maxIOB with step size based on bolusIncrement * 10, but cap at 1.0
        let calculatedStep = bolusIncrementValue * 10
        let maxIOBStep = min(calculatedStep, 1.0)

        maxIOB = PickerSetting(
            value: 0,
            step: maxIOBStep,
            min: 0,
            max: 30,
            type: PickerSetting.PickerSettingType.insulinUnit
        )

        let maxBolusStep = min(calculatedStep, 0.5)
        maxBolus = PickerSetting(
            value: 10,
            step: maxBolusStep,
            min: 0.5,
            max: 30,
            type: PickerSetting.PickerSettingType.insulinUnit
        )

        let maxBasalStep = min(calculatedStep, 0.5)
        maxBasal = PickerSetting(
            value: 10,
            step: maxBasalStep,
            min: 0.5,
            max: 30,
            type: PickerSetting.PickerSettingType.insulinUnitPerHour
        )
    }
}

struct PickerSetting {
    var value: Decimal
    var step: Decimal
    var min: Decimal
    var max: Decimal
    var type: PickerSettingType

    enum PickerSettingType {
        case glucose
        case factor
        case factorRaw
        case gram
        case insulinUnit
        case insulinUnitPerHour
        case minute
        case hour
        case percent
    }

    /// Shared formatter so callers outside `SettingInputSection` (e.g. the override
    /// forms) render values identically to the algorithm settings editors.
    func displayText(for value: Decimal, units: GlucoseUnits) -> Text {
        switch type {
        case .glucose:
            let displayValue = units == .mmolL ? value.asMmolL : value
            return Text("\(displayValue.description) \(units.rawValue)")
        case .factor:
            return Text("\(value * 100) \(String(localized: "%", comment: "Percentage symbol"))")
        case .factorRaw:
            return Text("\(value)")
        case .insulinUnit:
            return Text("\(value) \(String(localized: "U", comment: "Insulin unit abbreviation"))")
        case .insulinUnitPerHour:
            return Text("\(value) \(String(localized: "U/hr", comment: "Insulin unit per hour abbreviation"))")
        case .gram:
            return Text("\(value) \(String(localized: "g", comment: "Gram abbreviation"))")
        case .minute:
            return Text("\(value) \(String(localized: "min", comment: "Minutes abbreviation"))")
        case .hour:
            return Text("\(value) \(String(localized: "hr", comment: "Hours abbreviation"))")
        case .percent:
            return Text("\(value) \(String(localized: "%", comment: "Percentage symbol"))")
        }
    }
}
