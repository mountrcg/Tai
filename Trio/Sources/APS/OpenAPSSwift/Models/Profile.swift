import Foundation

struct Profile: JSON {
    // Kotlin-defined properties from AndroidAPS OapsProfile.kt
    // with defaults pulled from profile.js
    var dia: Decimal?
    var min5mCarbImpact: Decimal = 8
    var maxIob: Decimal = 0 // if max_iob is not provided, will default to zero
    var maxDailyBasal: Decimal?
    var maxBasal: Decimal?
    var minBg: Decimal?
    var maxBg: Decimal?
    @JavascriptOptional var targetBg: Decimal?
    var smbDeliveryRatio: Decimal = 0.5
    var carbRatio: Decimal?
    var sens: Decimal?
    var maxDailySafetyMultiplier: Decimal = 3
    var currentBasalSafetyMultiplier: Decimal = 4
    var highTemptargetRaisesSensitivity: Bool = false // raise sensitivity for temptargets >= 101
    var lowTemptargetLowersSensitivity: Bool = false // lower sensitivity for temptargets <= 99
    var sensitivityRaisesTarget: Bool = false // raise BG target when autosens detects sensitivity
    var resistanceLowersTarget: Bool = false // lower BG target when autosens detects resistance
    var halfBasalExerciseTarget: Decimal = 160 // when temptarget is 160 mg/dL *and* exercise_mode=true, run 50% basal
    var maxCOB: Decimal = 120 // maximum carbs a typical body can absorb over 4 hours
    var skipNeutralTemps: Bool = false
    var remainingCarbsCap: Decimal = 90
    var enableUAM: Bool = false
    var a52RiskEnable: Bool = false
    var smbInterval: Decimal = 3
    var enableSMBWithCOB: Bool = false
    var enableSMBWithTemptarget: Bool = false
    var allowSMBWithHighTemptarget: Bool = false
    var enableSMBAlways: Bool = false
    var enableSMBAfterCarbs: Bool = false
    var maxSMBBasalMinutes: Decimal = 30
    var maxUAMSMBBasalMinutes: Decimal = 30
    var bolusIncrement: Decimal = 0.1
    var carbsReqThreshold: Decimal = 1
    var currentBasal: Decimal?
    var temptargetSet: Bool?
    var autosensMax: Decimal = 1.2
    var autosensMin: Decimal = 0.7
    var outUnits: GlucoseUnits?

    // Additional properties
    var maxMealAbsorptionTime: Decimal = 6.0
    var rewindResetsAutosens: Bool = true
    var remainingCarbsFraction: Decimal = 1.0
    var unsuspendIfNoTemp: Bool = false
    var autotuneIsfAdjustmentFraction: Decimal = 1.0
    var enableSMBHighBg: Bool = false
    var enableSMBHighBgTarget: Decimal = 110
    var maxDeltaBgThreshold: Decimal = 0.2
    var curve: InsulinCurve = .rapidActing
    var useCustomPeakTime: Bool = false
    var insulinPeakTime: Decimal = 75
    var noisyCGMTargetMultiplier: Decimal = 1.3
    var suspendZerosIob: Bool = true
    var calcGlucoseNoise: Bool = false
    var adjustmentFactor: Decimal = 0.8
    var adjustmentFactorSigmoid: Decimal = 0.5
    var useNewFormula: Bool = false
    var sigmoid: Bool = false
    var weightPercentage: Decimal = 0.65
    var tddAdjBasal: Bool = false
    var thresholdSetting: Decimal = 60
    var model: String?
    var basalprofile: [BasalProfileEntry]?
    var isfProfile: ComputedInsulinSensitivities?
    var bgTargets: ComputedBGTargets?
    var carbRatios: CarbRatios?

    // start autoISF config
    var floatingcarbs: Bool = false
    var autoisf: Bool = true
    var enableAutosens: Bool = true
    var autoISFmax: Decimal = 1.2
    var autoISFmin: Decimal = 0.7
    var smbThresholdRatio: Decimal = 0.5
    var smbMaxRangeExtension: Decimal = 1
    var smbDeliveryRatioBGrange: Decimal = 0
    var smbDeliveryRatioMin: Decimal = 0.5
    var smbDeliveryRatioMax: Decimal = 0.8
    var autoISFhourlyChange: Decimal = 0
    var higherISFrangeWeight: Decimal = 0
    var lowerISFrangeWeight: Decimal = 0
    var postMealISFweight: Decimal = 0
    var enableBGacceleration: Bool = false
    var bgAccelISFweight: Decimal = 0
    var bgBrakeISFweight: Decimal = 0
    var iobThresholdPercent: Decimal = 1
    var enableSMBEvenOnOddOffAlways: Bool = false
    var autoISFoffSport: Bool = false
    var targetUnits: GlucoseUnits = .mgdL
    // start B30 config
    var enableB30: Bool = false
    var B30iTimeStartBolus: Decimal = 1
    var B30iTime: Decimal = 30
    var B30iTimeTarget: Decimal = 80
    var B30upperLimit: Decimal = 130
    var B30upperDelta: Decimal = 8
    var B30basalFactor: Decimal = 7
    // start keto protect
    var ketoProtect: Bool = false
    var variableKetoProtect: Bool = false
    var ketoProtectBasalPercent: Decimal = 0.2
    var ketoProtectAbsolut: Bool = false
    var ketoProtectBasalAbsolut: Decimal = 0
    var useProfileCSF: Bool = false

    private enum CodingKeys: String, CodingKey {
        case dia
        case min5mCarbImpact = "min_5m_carbimpact"
        case maxIob = "max_iob"
        case maxDailyBasal = "max_daily_basal"
        case maxBasal = "max_basal"
        case minBg = "min_bg"
        case maxBg = "max_bg"
        case targetBg = "target_bg"
        case smbDeliveryRatio = "smb_delivery_ratio"
        case carbRatio = "carb_ratio"
        case sens
        case maxDailySafetyMultiplier = "max_daily_safety_multiplier"
        case currentBasalSafetyMultiplier = "current_basal_safety_multiplier"
        case highTemptargetRaisesSensitivity = "high_temptarget_raises_sensitivity"
        case lowTemptargetLowersSensitivity = "low_temptarget_lowers_sensitivity"
        case sensitivityRaisesTarget = "sensitivity_raises_target"
        case resistanceLowersTarget = "resistance_lowers_target"
        case halfBasalExerciseTarget = "half_basal_exercise_target"
        case maxCOB
        case skipNeutralTemps = "skip_neutral_temps"
        case remainingCarbsCap
        case enableUAM
        case a52RiskEnable = "A52_risk_enable"
        case smbInterval = "SMBInterval"
        case enableSMBWithCOB = "enableSMB_with_COB"
        case enableSMBWithTemptarget = "enableSMB_with_temptarget"
        case allowSMBWithHighTemptarget = "allowSMB_with_high_temptarget"
        case enableSMBAlways = "enableSMB_always"
        case enableSMBAfterCarbs = "enableSMB_after_carbs"
        case maxSMBBasalMinutes
        case maxUAMSMBBasalMinutes
        case bolusIncrement = "bolus_increment"
        case carbsReqThreshold
        case currentBasal = "current_basal"
        case temptargetSet
        case autosensMax = "autosens_max"
        case autosensMin = "autosens_min"
        case outUnits = "out_units"
        case maxMealAbsorptionTime
        case rewindResetsAutosens = "rewind_resets_autosens"
        case remainingCarbsFraction
        case unsuspendIfNoTemp = "unsuspend_if_no_temp"
        case autotuneIsfAdjustmentFraction = "autotune_isf_adjustmentFraction"
        case enableSMBHighBg = "enableSMB_high_bg"
        case enableSMBHighBgTarget = "enableSMB_high_bg_target"
        case maxDeltaBgThreshold = "maxDelta_bg_threshold"
        case curve
        case useCustomPeakTime
        case insulinPeakTime
        case noisyCGMTargetMultiplier
        case suspendZerosIob = "suspend_zeros_iob"
        case adjustmentFactor
        case adjustmentFactorSigmoid
        case useNewFormula
        case sigmoid
        case weightPercentage
        case tddAdjBasal
        case thresholdSetting = "threshold_setting"
        case model
        case basalprofile
        case isfProfile
        case bgTargets = "bg_targets"
        case carbRatios = "carb_ratios"
        // start autoISF config for oref variables
        case autoisf = "use_autoisf"
        case enableAutosens = "enable_autosens"
        case smbThresholdRatio = "smb_threshold_ratio"
        case targetUnits = "target_units"
        case autoISFhourlyChange = "dura_ISF_weight"
        case autoISFmax = "autoISF_max"
        case autoISFmin = "autoISF_min"
        case smbMaxRangeExtension = "smb_max_range_extension"
        case floatingcarbs = "floating_carbs"
        case iobThresholdPercent = "iob_threshold_percent"
        case enableSMBEvenOnOddOffAlways = "enableSMB_EvenOn_OddOff_always"
        case smbDeliveryRatioBGrange = "smb_delivery_ratio_bg_range"
        case smbDeliveryRatioMin = "smb_delivery_ratio_min"
        case smbDeliveryRatioMax = "smb_delivery_ratio_max"
        case higherISFrangeWeight = "higher_ISFrange_weight"
        case lowerISFrangeWeight = "lower_ISFrange_weight"
        case postMealISFweight = "pp_ISF_weight"
        case bgAccelISFweight = "bgAccel_ISF_weight"
        case bgBrakeISFweight = "bgBrake_ISF_weight"
        case enableBGacceleration = "enable_BG_acceleration"
        case autoISFoffSport = "autoISF_off_Sport"
        // start B30 config
        case enableB30 = "use_B30"
        case B30iTimeStartBolus = "iTime_Start_Bolus"
        case B30iTime = "b30_duration"
        case B30iTimeTarget = "iTime_target"
        case B30upperLimit = "b30_upperBG"
        case B30upperDelta = "b30_upperdelta"
        case B30basalFactor = "b30_factor"
        // start keto protect
        case ketoProtect = "keto_protect"
        case variableKetoProtect = "variable_keto_protect_strategy"
        case ketoProtectBasalPercent = "keto_protect_basal_percent"
        case ketoProtectAbsolut = "keto_protect_absolute"
        case ketoProtectBasalAbsolut = "keto_protect_basal_absolute"
        case useProfileCSF = "use_profile_csf"
    }
}
