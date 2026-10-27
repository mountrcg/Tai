import Foundation

/// Main autoISF glucose status calculation module
/// Ported from JavaScript glucose-get-last.js
///
/// All calculation logic is organized here with proper variable scoping.
/// Calculation phases are separated into distinct structs and functions
/// to improve readability, testability, and maintainability.
enum AutoISFGlucose {
    // MARK: - Constants

    /// Glucose thresholds and filters
    private enum GlucoseConstants {
        static let minimumGlucoseValue = 39 // Ignore readings below this
    }

    /// Flat glucose detection thresholds
    private enum CGMFlatConstants {
        static let bandWidth = 2 // mg/dL maximum spread to be "flat"
        static let maxGapBetweenReadings = 11 * 60 // seconds
        static let maxAge = 60 * 60 // seconds (1 hour)
    }

    /// Duration ISF calculation thresholds
    private enum DuraISFConstants {
        static let bandwidthPercent = Decimal(0.05) // 5% bandwidth
        static let maxGapDuration = 13 // minutes (approximately 2 CGM readings)
    }

    /// Parabola fit calculation constants
    enum ParabolaFitConstants {
        // JS glucose-get-last.js uses scaleTime=1, scaleBg=1 (raw seconds and mg/dL in the matrix).
        // Post-hoc scaling converts raw coefficients: a×90000, b×300, c×1.
        // Decimal arithmetic is precise enough that pre-scaling is not needed.
        static let matrixEpsilon = Decimal(1E-10) // Prevent division by near-zero determinant
        static let defaultRSquared = Decimal(0.64) // Default R² when glucose is perfectly flat
    }

    /// Get autoISF glucose status analysis
    ///
    /// Calculates autoISF-specific metrics from raw glucose data.
    /// Only called when autoISF is enabled.
    /// Ported directly from JavaScript glucose-get-last.js implementation.
    ///
    /// - Parameters:
    ///   - glucoseStatus: The base glucose status (from getGlucoseStatus)
    ///   - glucoseReadings: Raw glucose readings for calculations
    ///   - profile: Profile containing autoISF settings
    /// - Returns: AutoISFGlucoseStatus if autoISF is enabled, nil otherwise
    static func getAutoISFGlucoseStatus(
        glucoseStatus: GlucoseStatus,
        glucoseReadings: [BloodGlucose],
        profile: Profile
    ) -> AutoISFGlucoseStatus? {
        // Check if autoISF is enabled
        guard profile.autoisf else {
            debug(.algorithm, "AutoISF glucose status skipped, autoISF is off")
            return nil
        }

        // Filter and prepare glucose readings (from JS glucose-get-last.js)
        let readings = glucoseReadings.compactMap { reading -> (glucose: Int, date: Date)? in
            guard let glucose = reading.glucose ?? reading.sgv else { return nil }
            return (glucose: glucose, date: reading.dateString)
        }
        debug(.algorithm, "AutoISF glucose status uses \(readings.count) glucose readings")

        guard readings.count > 3 else {
            // Not enough data for calculations
            debug(.algorithm, "AutoISF glucose status skipped, only \(readings.count) glucose readings")
            return nil
        }

        // Sort descending (newest first) like JS implementation
        let sorted = readings.sorted { $0.date > $1.date }
        guard let mostRecentDate = sorted.first?.date else { return nil }

        // Calculate cgmFlatMinutes (minutes where glucose is relatively flat)
        let cgmFlatMinutes = OrefSubTimer.time("autoISFGlucose.calculateCGMFlatMinutes") {
            calculateCGMFlatMinutes(from: sorted, referenceDate: mostRecentDate)
        }

        // Calculate dura_ISF values (moving average window)
        let (dura_ISF_minutes, dura_ISF_average) = OrefSubTimer.time("autoISFGlucose.calculateDuraISF") {
            calculateDuraISF(from: sorted, referenceDate: mostRecentDate)
        }

        // Calculate parabola fit (quadratic regression)
        let parabolaResult = OrefSubTimer.time("autoISFGlucose.calculateParabolaFit") {
            calculateParabolaFit(from: sorted, referenceDate: mostRecentDate)
        }

        // Build debug string matching JavaScript ppDebug format
        let debugInfo = buildDebugString(
            glucoseStatus: glucoseStatus,
            cgmFlatMinutes: cgmFlatMinutes,
            dura_ISF_minutes: dura_ISF_minutes,
            dura_ISF_average: dura_ISF_average,
            parabolaResult: parabolaResult
        )

        return AutoISFGlucoseStatus(
            glucoseStatus: glucoseStatus,
            cgmFlatMinutes: cgmFlatMinutes,
            dura_ISF_minutes: dura_ISF_minutes,
            dura_ISF_average: dura_ISF_average,
            dura_p: parabolaResult.dura_p,
            delta_pl: parabolaResult.delta_pl,
            delta_pn: parabolaResult.delta_pn,
            bg_acceleration: parabolaResult.bg_acceleration,
            r_squ: parabolaResult.r_squ,
            a_0: parabolaResult.a_0,
            a_1: parabolaResult.a_1,
            a_2: parabolaResult.a_2,
            debugInfo: debugInfo
        )
    }

    // MARK: - Private Calculation Functions

    // Ported from JavaScript glucose-get-last.js

    /// Calculate minutes where glucose is relatively flat
    /// From JS: Lines ~760-773
    /// Stops when glucose band > 2 mg/dL, gap > 11 minutes, or > 1 hour old
    private static func calculateCGMFlatMinutes(
        from readings: [(glucose: Int, date: Date)],
        referenceDate: Date
    ) -> Decimal {
        var minBG = readings[0].glucose
        var maxBG = minBG
        var cgmFlatMinutes: Decimal = 0
        var oldDate = readings[0].date

        for i in 1 ..< readings.count {
            let then = readings[i]
            minBG = min(minBG, then.glucose)
            maxBG = max(maxBG, then.glucose)

            let timeSinceLastReading = oldDate.timeIntervalSince(then.date)
            let timeSinceMostRecent = referenceDate.timeIntervalSince(then.date)

            // Break if: band too wide, gap > 11 min, or older than 1 hour
            if (maxBG - minBG) > CGMFlatConstants.bandWidth ||
                timeSinceLastReading > TimeInterval(CGMFlatConstants.maxGapBetweenReadings) ||
                timeSinceMostRecent > TimeInterval(CGMFlatConstants.maxAge)
            {
                break
            } else {
                oldDate = then.date
            }
            cgmFlatMinutes = Decimal(referenceDate.timeIntervalSince(oldDate) / 60.0)
        }

        return cgmFlatMinutes.rounded(toPlaces: 4)
    }

    /// Calculate dura_ISF window duration and average
    /// From JS: Lines ~775-792
    /// Looks back through readings within 5% bandwidth
    private static func calculateDuraISF(
        from readings: [(glucose: Int, date: Date)],
        referenceDate: Date
    ) -> (minutes: Decimal, average: Decimal) {
        var sumBG = Decimal(readings[0].glucose)
        var oldavg = sumBG
        var minutesdur: Decimal = 0
        var n = 1

        for i in 1 ..< readings.count {
            n += 1
            let then = readings[i]
            let minutesAgo = Decimal(Int((referenceDate.timeIntervalSince(then.date) / 60).rounded()))

            // Stop if gap > 13 minutes (2 regular CGM readings)
            if minutesAgo - minutesdur > Decimal(DuraISFConstants.maxGapDuration) {
                break
            }

            let glucoseDecimal = Decimal(then.glucose)
            // Check if reading within bandwidth of running average
            if glucoseDecimal > oldavg * (1 - DuraISFConstants.bandwidthPercent),
               glucoseDecimal < oldavg * (1 + DuraISFConstants.bandwidthPercent)
            {
                sumBG += glucoseDecimal
                oldavg = sumBG / Decimal(n)
                minutesdur = minutesAgo
            } else {
                break
            }
        }

        return (minutesdur.rounded(), oldavg.rounded(toPlaces: 4))
    }

    /// Calculate parabola fit (quadratic regression)
    /// Ported from JS glucose-get-last.js lines ~200-303
    /// Fits y = a*x^2 + b*x + c through glucose history using Cramer's rule.
    ///
    /// JS uses scaleTime=1, scaleBg=1 (raw seconds and mg/dL in the matrix),
    /// then applies post-hoc scaling: a×90000, b×300, c×1.
    private static func calculateParabolaFit(
        from readings: [(glucose: Int, date: Date)],
        referenceDate _: Date
    ) -> ParabolaFitResult {
        guard readings.count > 3 else {
            return ParabolaFitResult.default()
        }

        // Detect 1-min CGM data (Libre): 3 consecutive readings within 3 minutes
        let use1MinuteRaw = readings.count > 2 &&
            readings[0].date.timeIntervalSince(readings[2].date) < 3 * 60
        let minFitSeconds = Decimal(use1MinuteRaw ? 20 * 60 : 15 * 60) // JS: minFitDur * 60

        let time_0 = readings[0].date
        var bestFit = ParabolaFitResult.default()
        var corrMax: Decimal = 0
        var tiLast: Decimal = 0

        // Running accumulators — raw seconds and mg/dL, matching JS scaleTime=1, scaleBg=1
        var sy: Decimal = 0
        var sx: Decimal = 0
        var sx2: Decimal = 0
        var sx3: Decimal = 0
        var sx4: Decimal = 0
        var sxy: Decimal = 0
        var sx2y: Decimal = 0
        var n = 0

        for i in 0 ..< readings.count {
            let glucose = readings[i].glucose
            guard glucose > GlucoseConstants.minimumGlucoseValue else { continue }
            n += 1

            let then_date = readings[i].date
            // JS: ti = (then_date - time_0) / 1000 / scaleTime  (negative seconds for past readings)
            // Swift: timeIntervalSince already returns seconds, no /1000 needed
            let ti = Decimal(then_date.timeIntervalSince(time_0)) // negative for past

            // Skip records older than 47 minutes (JS: -ti * scaleTime > 47 * 60)
            if -ti > 47 * 60 {
                break
            }
            // Stop on CGM gap > 11 minutes (JS: ti < tiLast - 11*60/scaleTime)
            else if ti < tiLast - 11 * 60 {
                // History too short for fit — dura_p set but other fields stay 0 (matches JS)
                if i < 3 || -ti < minFitSeconds {
                    bestFit.dura_p = (-tiLast / 60).rounded(toPlaces: 4)
                }
                break
            }

            tiLast = ti
            let bg = Decimal(glucose)

            // Incremental accumulation (JS accumulates in single pass)
            sx += ti
            sx2 += ti * ti
            sx3 += ti * ti * ti
            sx4 += ti * ti * ti * ti
            sy += bg
            sxy += ti * bg
            sx2y += ti * ti * bg

            // JS: if (n > 3 && -ti * scaleTime > minFitDur * 60)
            guard n > 3, -ti > minFitSeconds else { continue }

            let nD = Decimal(n)

            // Cramer's rule determinants (JS lines 263-266)
            let detH = sx4 * (sx2 * nD - sx * sx) -
                sx3 * (sx3 * nD - sx * sx2) +
                sx2 * (sx3 * sx - sx2 * sx2)

            guard abs(detH) > ParabolaFitConstants.matrixEpsilon else { continue }

            let detA = sx2y * (sx2 * nD - sx * sx) -
                sxy * (sx3 * nD - sx * sx2) +
                sy * (sx3 * sx - sx2 * sx2)
            let detB = sx4 * (sxy * nD - sy * sx) -
                sx3 * (sx2y * nD - sy * sx2) +
                sx2 * (sx2y * sx - sxy * sx2)
            let detC = sx4 * (sx2 * sy - sx * sxy) -
                sx3 * (sx3 * sy - sx * sx2y) +
                sx2 * (sx3 * sxy - sx2 * sx2y)

            // Post-hoc scaling: convert raw (seconds, mg/dL) coefficients to (5-min, mg/dL)
            // JS: a = detA/detH * scaleBg * (300/scaleTime)^2 = detA/detH * 1 * 300^2
            let a = detA / detH * 90000
            let b = detB / detH * 300
            let c = detC / detH

            // R² — JS: deltaT = (before_date - time_0) / 1000 / 300  (5-min units, negative)
            let yMean = sy / nD
            var sSquares: Decimal = 0
            var sResidualSquares: Decimal = 0
            for j in 0 ... i {
                let bgj = Decimal(readings[j].glucose)
                let deltaT = Decimal(readings[j].date.timeIntervalSince(time_0)) / 300
                let bgPred = a * deltaT * deltaT + b * deltaT + c
                sSquares += (bgj - yMean) * (bgj - yMean)
                sResidualSquares += (bgj - bgPred) * (bgj - bgPred)
            }

            let rSqu: Decimal = sSquares != 0
                ? (1 - sResidualSquares / sSquares).rounded(toPlaces: 4)
                : ParabolaFitConstants.defaultRSquared

            if rSqu >= corrMax {
                corrMax = rSqu
                // delta5Min = 1 (JS hardcodes var delta5Min = 1)
                // deltaPl = -(a*(-1)^2 - b*1) = b - a  (JS line 291)
                // deltaPn =   a*(1)^2  + b*1   = a + b  (JS line 292)
                bestFit = ParabolaFitResult(
                    dura_p: (-ti / 60).rounded(toPlaces: 4),
                    delta_pl: (b - a).rounded(toPlaces: 4),
                    delta_pn: (a + b).rounded(toPlaces: 4),
                    bg_acceleration: (2 * a).rounded(toPlaces: 4),
                    r_squ: rSqu,
                    a_0: c.rounded(toPlaces: 4),
                    a_1: b.rounded(toPlaces: 4),
                    a_2: a.rounded(toPlaces: 4)
                )
            }
        }

        return bestFit
    }

    // MARK: - Debug Output

    /// Build debug string matching JavaScript `ppDebug` format
    ///
    /// Used to compare Swift calculations against JavaScript original.
    /// Includes all intermediate and final values for validation.
    private static func buildDebugString(
        glucoseStatus: GlucoseStatus,
        cgmFlatMinutes: Decimal,
        dura_ISF_minutes: Decimal,
        dura_ISF_average: Decimal,
        parabolaResult: ParabolaFitResult
    ) -> String {
        // Format: key: value, key: value, ...
        // Matches JavaScript ppDebug string format from glucose-get-last.js
        // For easy comparison and validation during integration testing

        let debugParts = [
            "glucose: \(glucoseStatus.glucose.rounded(toPlaces: 0))",
            "noise: 0",
            "delta: \(glucoseStatus.delta.rounded(toPlaces: 0))",
            "short_avgdelta: \(glucoseStatus.shortAvgDelta.rounded(toPlaces: 2))",
            "long_avgdelta: \(glucoseStatus.longAvgDelta.rounded(toPlaces: 2))",
            "cgmFlatMinutes: \(cgmFlatMinutes.rounded(toPlaces: 0))",
            "date: \(glucoseStatus.date)",
            "dura_minutes: \(dura_ISF_minutes.rounded(toPlaces: 0))",
            "dura_average: \(dura_ISF_average.rounded(toPlaces: 2))",
            "fit_correlation: \(parabolaResult.r_squ.rounded(toPlaces: 4))",
            "fit_minutes: \(parabolaResult.dura_p.rounded(toPlaces: 2))",
            "fit_last_delta: \(parabolaResult.delta_pl.rounded(toPlaces: 2))",
            "fit_next_delta: \(parabolaResult.delta_pn.rounded(toPlaces: 2))",
            "fit_a0: \(parabolaResult.a_0.rounded(toPlaces: 2))",
            "fit_a1: \(parabolaResult.a_1.rounded(toPlaces: 2))",
            "fit_a2: \(parabolaResult.a_2.rounded(toPlaces: 2))",
            "bg_acce: \(parabolaResult.bg_acceleration.rounded(toPlaces: 2))"
        ]

        return debugParts.joined(separator: ", ")
    }
}

/// Final parabola fit result
/// Contains all the computed values to return to the glucose status
private struct ParabolaFitResult {
    var dura_p: Decimal // duration in minutes
    var delta_pl: Decimal // past 5-min delta
    var delta_pn: Decimal // future 5-min delta
    var bg_acceleration: Decimal // 2*a*scaleBg (acceleration)
    var r_squ: Decimal // R² quality metric
    var a_0: Decimal // constant coefficient (scaled)
    var a_1: Decimal // linear coefficient (scaled)
    var a_2: Decimal // quadratic coefficient (scaled)

    /// Default (empty) result when not enough data
    static func `default`() -> Self {
        ParabolaFitResult(
            dura_p: 0,
            delta_pl: 0,
            delta_pn: 0,
            bg_acceleration: 0,
            r_squ: 0,
            a_0: 0,
            a_1: 0,
            a_2: 0
        )
    }
}

extension GlucoseStatus {
    /// Convenience method to get AutoISF glucose status
    /// Wraps the static AutoISFGlucose.getAutoISFGlucoseStatus function
    func getAutoISFGlucoseStatus(
        glucoseReadings: [BloodGlucose],
        _ profile: Profile
    ) -> AutoISFGlucoseStatus? {
        AutoISFGlucose.getAutoISFGlucoseStatus(
            glucoseStatus: self,
            glucoseReadings: glucoseReadings,
            profile: profile
        )
    }
}
