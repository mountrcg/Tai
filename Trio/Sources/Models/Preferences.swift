import Foundation

struct Preferences: JSON, Equatable {
    var maxIOB: Decimal = 0
    var maxDailySafetyMultiplier: Decimal = 3
    var currentBasalSafetyMultiplier: Decimal = 4
    var enableAutosens = false
    var autosensMax: Decimal = 1.2
    var autosensMin: Decimal = 0.7
    var rewindResetsAutosens: Bool = true
    var highTemptargetRaisesSensitivity: Bool = true
    var lowTemptargetLowersSensitivity: Bool = false
    var sensitivityRaisesTarget: Bool = false
    var resistanceLowersTarget: Bool = false
    var advTargetAdjustments: Bool = false
    var halfBasalExerciseTarget: Decimal = 160
    var maxCOB: Decimal = 120
    var maxMealAbsorptionTime: Decimal = 6
    var skipNeutralTemps: Bool = false
    var unsuspendIfNoTemp: Bool = false
    var min5mCarbimpact: Decimal = 8
    var remainingCarbsFraction: Decimal = 1.0
    var remainingCarbsCap: Decimal = 90
    var enableUAM: Bool = true
    var a52RiskEnable: Bool = false
    var enableSMBWithCOB: Bool = true
    var enableSMBWithTemptarget: Bool = true
    var enableSMBAlways: Bool = true
    var enableSMB_high_bg: Bool = false
    var enableSMB_high_bg_target: Decimal = 110
    var enableSMBAfterCarbs: Bool = true
    var allowSMBWithHighTemptarget: Bool = false
    var maxSMBBasalMinutes: Decimal = 120
    var maxUAMSMBBasalMinutes: Decimal = 120
    var smbInterval: Decimal = 2
    var bolusIncrement: Decimal = 0.05
    var curve: InsulinCurve = .rapidActing
    var useCustomPeakTime: Bool = false
    var insulinPeakTime: Decimal = 75
    var carbsReqThreshold: Decimal = 1.0
    var noisyCGMTargetMultiplier: Decimal = 1.3
    var suspendZerosIOB: Bool = true
    var timestamp: Date?
    var smbThresholdRatio: Decimal = 0.5
    var maxDeltaBGthreshold: Decimal = 0.2
    var useProfileCSF: Bool = false
    // start dynISF config for oref variables
    var adjustmentFactor: Decimal = 0.8
    var adjustmentFactorSigmoid: Decimal = 0.5
    var sigmoid: Bool = false
    var useNewFormula: Bool = false
    var useWeightedAverage: Bool = false
    var weightPercentage: Decimal = 0.35
    var tddAdjBasal: Bool = false
    var threshold_setting: Decimal = 65
    var updateInterval: Decimal = 20
    // start autoISF config
    var floatingcarbs: Bool = false
    var autoisf: Bool = true
    var autoISFmax: Decimal = 2
    var autoISFmin: Decimal = 0.5
    var smbMaxRangeExtension: Decimal = 2
    var smbDeliveryRatio: Decimal = 0.85
    var smbDeliveryRatioBGrange: Decimal = 0
    var smbDeliveryRatioMin: Decimal = 0.65
    var smbDeliveryRatioMax: Decimal = 0.80
    var autoISFhourlyChange: Decimal = 0.6
    var higherISFrangeWeight: Decimal = 0.3
    var lowerISFrangeWeight: Decimal = 0.7
    var postMealISFweight: Decimal = 0.02
    var enableBGacceleration: Bool = true
    var bgAccelISFweight: Decimal = 0.15
    var bgBrakeISFweight: Decimal = 0.15
    var iobThresholdPercent: Decimal = 1
    var enableSMBEvenOnOddOffAlways: Bool = true
    var autoISFoffSport: Bool = false
    var targetUnits: GlucoseUnits = .mgdL
    // start B30 config
    var enableB30: Bool = true
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
}

extension Preferences {
    private enum CodingKeys: String, CodingKey {
        case maxIOB = "max_iob"
        case maxDailySafetyMultiplier = "max_daily_safety_multiplier"
        case currentBasalSafetyMultiplier = "current_basal_safety_multiplier"
        case enableAutosens = "enable_autosens"
        case autosensMax = "autosens_max"
        case autosensMin = "autosens_min"
        case smbDeliveryRatio = "smb_delivery_ratio"
        case rewindResetsAutosens = "rewind_resets_autosens"
        case highTemptargetRaisesSensitivity = "high_temptarget_raises_sensitivity"
        case lowTemptargetLowersSensitivity = "low_temptarget_lowers_sensitivity"
        case sensitivityRaisesTarget = "sensitivity_raises_target"
        case resistanceLowersTarget = "resistance_lowers_target"
        case advTargetAdjustments = "adv_target_adjustments"
        case halfBasalExerciseTarget = "half_basal_exercise_target"
        case maxCOB
        case maxMealAbsorptionTime
        case skipNeutralTemps = "skip_neutral_temps"
        case unsuspendIfNoTemp = "unsuspend_if_no_temp"
        case min5mCarbimpact = "min_5m_carbimpact"
        case remainingCarbsFraction
        case remainingCarbsCap
        case enableUAM
        case a52RiskEnable = "A52_risk_enable"
        case enableSMBWithCOB = "enableSMB_with_COB"
        case enableSMBWithTemptarget = "enableSMB_with_temptarget"
        case enableSMBAlways = "enableSMB_always"
        case enableSMBAfterCarbs = "enableSMB_after_carbs"
        case allowSMBWithHighTemptarget = "allowSMB_with_high_temptarget"
        case maxSMBBasalMinutes
        case maxUAMSMBBasalMinutes
        case smbInterval = "SMBInterval"
        case bolusIncrement = "bolus_increment"
        case curve
        case useCustomPeakTime
        case insulinPeakTime
        case carbsReqThreshold
        case noisyCGMTargetMultiplier
        case suspendZerosIOB = "suspend_zeros_iob"
        case smbDeliveryRatioBGrange = "smb_delivery_ratio_bg_range"
        case maxDeltaBGthreshold = "maxDelta_bg_threshold"
        case useProfileCSF = "use_profile_csf"
        // start dynISF config for oref variables
        case adjustmentFactor
        case adjustmentFactorSigmoid
        case sigmoid
        case useNewFormula
        case useWeightedAverage
        case weightPercentage
        case tddAdjBasal
        case enableSMB_high_bg
        case enableSMB_high_bg_target
        case threshold_setting
        case updateInterval
        // start autoISF config for oref variables
        case autoisf = "use_autoisf"
        case targetUnits = "target_units"
        case autoISFhourlyChange = "dura_ISF_weight"
        case autoISFmax = "autoISF_max"
        case autoISFmin = "autoISF_min"
        case smbMaxRangeExtension = "smb_max_range_extension"
        case floatingcarbs = "floating_carbs"
        case iobThresholdPercent = "iob_threshold_percent"
        case enableSMBEvenOnOddOffAlways = "enableSMB_EvenOn_OddOff_always"
        case smbDeliveryRatioMin = "smb_delivery_ratio_min"
        case smbDeliveryRatioMax = "smb_delivery_ratio_max"
        case smbThresholdRatio = "smb_threshold_ratio"
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
    }
}

enum InsulinCurve: String, JSON, Identifiable, CaseIterable {
    case rapidActing = "rapid-acting"
    case ultraRapid = "ultra-rapid"
    case bilinear

    var id: InsulinCurve { self }
}

extension Preferences: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var preferences = Preferences()

        if let maxIOB = try? container.decode(Decimal.self, forKey: .maxIOB) {
            preferences.maxIOB = maxIOB
        }

        if let maxDailySafetyMultiplier = try? container.decode(Decimal.self, forKey: .maxDailySafetyMultiplier) {
            preferences.maxDailySafetyMultiplier = maxDailySafetyMultiplier
        }

        if let currentBasalSafetyMultiplier = try? container.decode(Decimal.self, forKey: .currentBasalSafetyMultiplier) {
            preferences.currentBasalSafetyMultiplier = currentBasalSafetyMultiplier
        }

        if let autosensMax = try? container.decode(Decimal.self, forKey: .autosensMax) {
            preferences.autosensMax = autosensMax
        }

        if let autosensMin = try? container.decode(Decimal.self, forKey: .autosensMin) {
            preferences.autosensMin = autosensMin
        }

        if let smbDeliveryRatio = try? container.decode(Decimal.self, forKey: .smbDeliveryRatio) {
            preferences.smbDeliveryRatio = smbDeliveryRatio
        }

        if let rewindResetsAutosens = try? container.decode(Bool.self, forKey: .rewindResetsAutosens) {
            preferences.rewindResetsAutosens = rewindResetsAutosens
        }

        if let highTemptargetRaisesSensitivity = try? container.decode(Bool.self, forKey: .highTemptargetRaisesSensitivity) {
            preferences.highTemptargetRaisesSensitivity = highTemptargetRaisesSensitivity
        }

        if let lowTemptargetLowersSensitivity = try? container.decode(Bool.self, forKey: .lowTemptargetLowersSensitivity) {
            preferences.lowTemptargetLowersSensitivity = lowTemptargetLowersSensitivity
        }

        if let sensitivityRaisesTarget = try? container.decode(Bool.self, forKey: .sensitivityRaisesTarget) {
            preferences.sensitivityRaisesTarget = sensitivityRaisesTarget
        }

        if let resistanceLowersTarget = try? container.decode(Bool.self, forKey: .resistanceLowersTarget) {
            preferences.resistanceLowersTarget = resistanceLowersTarget
        }

        if let advTargetAdjustments = try? container.decode(Bool.self, forKey: .advTargetAdjustments) {
            preferences.advTargetAdjustments = advTargetAdjustments
        }

        if let halfBasalExerciseTarget = try? container.decode(Decimal.self, forKey: .halfBasalExerciseTarget) {
            preferences.halfBasalExerciseTarget = halfBasalExerciseTarget
        }

        if let maxCOB = try? container.decode(Decimal.self, forKey: .maxCOB) {
            preferences.maxCOB = maxCOB
        }

        if let maxMealAbsorptionTime = try? container.decode(Decimal.self, forKey: .maxMealAbsorptionTime) {
            preferences.maxMealAbsorptionTime = maxMealAbsorptionTime
        }

        if let skipNeutralTemps = try? container.decode(Bool.self, forKey: .skipNeutralTemps) {
            preferences.skipNeutralTemps = skipNeutralTemps
        }

        if let unsuspendIfNoTemp = try? container.decode(Bool.self, forKey: .unsuspendIfNoTemp) {
            preferences.unsuspendIfNoTemp = unsuspendIfNoTemp
        }

        if let min5mCarbimpact = try? container.decode(Decimal.self, forKey: .min5mCarbimpact) {
            preferences.min5mCarbimpact = min5mCarbimpact
        }

        if let remainingCarbsFraction = try? container.decode(Decimal.self, forKey: .remainingCarbsFraction) {
            preferences.remainingCarbsFraction = remainingCarbsFraction
        }

        if let remainingCarbsCap = try? container.decode(Decimal.self, forKey: .remainingCarbsCap) {
            preferences.remainingCarbsCap = remainingCarbsCap
        }

        if let enableUAM = try? container.decode(Bool.self, forKey: .enableUAM) {
            preferences.enableUAM = enableUAM
        }

        if let a52RiskEnable = try? container.decode(Bool.self, forKey: .a52RiskEnable) {
            preferences.a52RiskEnable = a52RiskEnable
        }

        if let enableSMBWithCOB = try? container.decode(Bool.self, forKey: .enableSMBWithCOB) {
            preferences.enableSMBWithCOB = enableSMBWithCOB
        }

        if let enableSMBWithTemptarget = try? container.decode(Bool.self, forKey: .enableSMBWithTemptarget) {
            preferences.enableSMBWithTemptarget = enableSMBWithTemptarget
        }

        if let enableSMBAlways = try? container.decode(Bool.self, forKey: .enableSMBAlways) {
            preferences.enableSMBAlways = enableSMBAlways
        }

        if let enableSMBAfterCarbs = try? container.decode(Bool.self, forKey: .enableSMBAfterCarbs) {
            preferences.enableSMBAfterCarbs = enableSMBAfterCarbs
        }

        if let allowSMBWithHighTemptarget = try? container.decode(Bool.self, forKey: .allowSMBWithHighTemptarget) {
            preferences.allowSMBWithHighTemptarget = allowSMBWithHighTemptarget
        }

        if let maxSMBBasalMinutes = try? container.decode(Decimal.self, forKey: .maxSMBBasalMinutes) {
            preferences.maxSMBBasalMinutes = maxSMBBasalMinutes
        }

        if let maxUAMSMBBasalMinutes = try? container.decode(Decimal.self, forKey: .maxUAMSMBBasalMinutes) {
            preferences.maxUAMSMBBasalMinutes = maxUAMSMBBasalMinutes
        }

        if let smbInterval = try? container.decode(Decimal.self, forKey: .smbInterval) {
            preferences.smbInterval = smbInterval
        }

        if let bolusIncrement = try? container.decode(Decimal.self, forKey: .bolusIncrement) {
            preferences.bolusIncrement = bolusIncrement > 0 ? bolusIncrement : 0.1
        }

        if let curve = try? container.decode(InsulinCurve.self, forKey: .curve) {
            preferences.curve = curve
        }

        if let useCustomPeakTime = try? container.decode(Bool.self, forKey: .useCustomPeakTime) {
            preferences.useCustomPeakTime = useCustomPeakTime
        }

        if let insulinPeakTime = try? container.decode(Decimal.self, forKey: .insulinPeakTime) {
            preferences.insulinPeakTime = insulinPeakTime
        }

        if let carbsReqThreshold = try? container.decode(Decimal.self, forKey: .carbsReqThreshold) {
            preferences.carbsReqThreshold = carbsReqThreshold
        }

        if let noisyCGMTargetMultiplier = try? container.decode(Decimal.self, forKey: .noisyCGMTargetMultiplier) {
            preferences.noisyCGMTargetMultiplier = noisyCGMTargetMultiplier
        }

        if let suspendZerosIOB = try? container.decode(Bool.self, forKey: .suspendZerosIOB) {
            preferences.suspendZerosIOB = suspendZerosIOB
        }

        if let maxDeltaBGthreshold = try? container.decode(Decimal.self, forKey: .maxDeltaBGthreshold) {
            preferences.maxDeltaBGthreshold = maxDeltaBGthreshold
        }

        if let adjustmentFactor = try? container.decode(Decimal.self, forKey: .adjustmentFactor) {
            preferences.adjustmentFactor = adjustmentFactor
        }

        if let adjustmentFactorSigmoid = try? container.decode(Decimal.self, forKey: .adjustmentFactorSigmoid) {
            preferences.adjustmentFactorSigmoid = adjustmentFactorSigmoid
        }

        if let sigmoid = try? container.decode(Bool.self, forKey: .sigmoid) {
            preferences.sigmoid = sigmoid
        }

        if let useNewFormula = try? container.decode(Bool.self, forKey: .useNewFormula) {
            preferences.useNewFormula = useNewFormula
        }

        if let useWeightedAverage = try? container.decode(Bool.self, forKey: .useWeightedAverage) {
            preferences.useWeightedAverage = useWeightedAverage
        }

        if let weightPercentage = try? container.decode(Decimal.self, forKey: .weightPercentage) {
            preferences.weightPercentage = weightPercentage
        }

        if let tddAdjBasal = try? container.decode(Bool.self, forKey: .tddAdjBasal) {
            preferences.tddAdjBasal = tddAdjBasal
        }

        if let enableSMB_high_bg = try? container.decode(Bool.self, forKey: .enableSMB_high_bg) {
            preferences.enableSMB_high_bg = enableSMB_high_bg
        }

        if let enableSMB_high_bg_target = try? container.decode(Decimal.self, forKey: .enableSMB_high_bg_target) {
            preferences.enableSMB_high_bg_target = enableSMB_high_bg_target
        }

        if let threshold_setting = try? container.decode(Decimal.self, forKey: .threshold_setting) {
            preferences.threshold_setting = threshold_setting
        }

        if let updateInterval = try? container.decode(Decimal.self, forKey: .updateInterval) {
            preferences.updateInterval = updateInterval
        }
        // autoISF config
        if let floatingcarbs = try? container.decode(Bool.self, forKey: .floatingcarbs) {
            preferences.floatingcarbs = floatingcarbs
        }
        if let autoisf = try? container.decode(Bool.self, forKey: .autoisf) {
            preferences.autoisf = autoisf
        }
        if let targetUnits = try? container.decode(GlucoseUnits.self, forKey: .targetUnits) {
            preferences.targetUnits = targetUnits
        }
        if let enableAutosens = try? container.decode(Bool.self, forKey: .enableAutosens) {
            preferences.enableAutosens = enableAutosens
        }
        if let autoISFmax = try? container.decode(Decimal.self, forKey: .autoISFmax) {
            preferences.autoISFmax = autoISFmax
        }
        if let autoISFmin = try? container.decode(Decimal.self, forKey: .autoISFmin) {
            preferences.autoISFmin = autoISFmin
        }
        if let smbMaxRangeExtension = try? container.decode(Decimal.self, forKey: .smbMaxRangeExtension) {
            preferences.smbMaxRangeExtension = smbMaxRangeExtension
        }
        if let smbDeliveryRatio = try? container.decode(Decimal.self, forKey: .smbDeliveryRatio) {
            preferences.smbDeliveryRatio = smbDeliveryRatio
        }
        if let smbDeliveryRatioBGrange = try? container.decode(Decimal.self, forKey: .smbDeliveryRatioBGrange) {
            preferences.smbDeliveryRatioBGrange = smbDeliveryRatioBGrange
        }
        if let smbDeliveryRatioMin = try? container.decode(Decimal.self, forKey: .smbDeliveryRatioMin) {
            preferences.smbDeliveryRatioMin = smbDeliveryRatioMin
        }
        if let smbDeliveryRatioMax = try? container.decode(Decimal.self, forKey: .smbDeliveryRatioMax) {
            preferences.smbDeliveryRatioMax = smbDeliveryRatioMax
        }
        if let autoISFhourlyChange = try? container.decode(Decimal.self, forKey: .autoISFhourlyChange) {
            preferences.autoISFhourlyChange = autoISFhourlyChange
        }
        if let higherISFrangeWeight = try? container.decode(Decimal.self, forKey: .higherISFrangeWeight) {
            preferences.higherISFrangeWeight = higherISFrangeWeight
        }
        if let lowerISFrangeWeight = try? container.decode(Decimal.self, forKey: .lowerISFrangeWeight) {
            preferences.lowerISFrangeWeight = lowerISFrangeWeight
        }
        if let postMealISFweight = try? container.decode(Decimal.self, forKey: .postMealISFweight) {
            preferences.postMealISFweight = postMealISFweight
        }
        if let enableBGacceleration = try? container.decode(Bool.self, forKey: .enableBGacceleration) {
            preferences.enableBGacceleration = enableBGacceleration
        }
        if let bgAccelISFweight = try? container.decode(Decimal.self, forKey: .bgAccelISFweight) {
            preferences.bgAccelISFweight = bgAccelISFweight
        }
        if let bgBrakeISFweight = try? container.decode(Decimal.self, forKey: .bgBrakeISFweight) {
            preferences.bgBrakeISFweight = bgBrakeISFweight
        }
        if let iobThresholdPercent = try? container.decode(Decimal.self, forKey: .iobThresholdPercent) {
            preferences.iobThresholdPercent = iobThresholdPercent
        }
        if let enableSMBEvenOnOddOffAlways = try? container.decode(Bool.self, forKey: .enableSMBEvenOnOddOffAlways) {
            preferences.enableSMBEvenOnOddOffAlways = enableSMBEvenOnOddOffAlways
        }
        if let autoISFoffSport = try? container.decode(Bool.self, forKey: .autoISFoffSport) {
            preferences.autoISFoffSport = autoISFoffSport
        }
        if let useProfileCSF = try? container.decode(Bool.self, forKey: .useProfileCSF) {
            preferences.useProfileCSF = useProfileCSF
        }

        // B30 config
        if let enableB30 = try? container.decode(Bool.self, forKey: .enableB30) {
            preferences.enableB30 = enableB30
        }
        if let B30iTimeStartBolus = try? container.decode(Decimal.self, forKey: .B30iTimeStartBolus) {
            preferences.B30iTimeStartBolus = B30iTimeStartBolus
        }
        if let B30iTime = try? container.decode(Decimal.self, forKey: .B30iTime) {
            preferences.B30iTime = B30iTime
        }
        if let B30iTimeTarget = try? container.decode(Decimal.self, forKey: .B30iTimeTarget) {
            preferences.B30iTimeTarget = B30iTimeTarget
        }
        if let B30upperLimit = try? container.decode(Decimal.self, forKey: .B30upperLimit) {
            preferences.B30upperLimit = B30upperLimit
        }
        if let B30upperDelta = try? container.decode(Decimal.self, forKey: .B30upperDelta) {
            preferences.B30upperDelta = B30upperDelta
        }
        if let B30basalFactor = try? container.decode(Decimal.self, forKey: .B30basalFactor) {
            preferences.B30basalFactor = B30basalFactor
        }

        // Keto Protect
        if let ketoProtect = try? container.decode(Bool.self, forKey: .ketoProtect) {
            preferences.ketoProtect = ketoProtect
        }
        if let variableKetoProtect = try? container.decode(Bool.self, forKey: .variableKetoProtect) {
            preferences.variableKetoProtect = variableKetoProtect
        }
        if let ketoProtectBasalPercent = try? container.decode(Decimal.self, forKey: .ketoProtectBasalPercent) {
            preferences.ketoProtectBasalPercent = ketoProtectBasalPercent
        }
        if let ketoProtectAbsolut = try? container.decode(Bool.self, forKey: .ketoProtectAbsolut) {
            preferences.ketoProtectAbsolut = ketoProtectAbsolut
        }
        if let ketoProtectBasalAbsolut = try? container.decode(Decimal.self, forKey: .ketoProtectBasalAbsolut) {
            preferences.ketoProtectBasalAbsolut = ketoProtectBasalAbsolut
        }

        self = preferences
    }
}
