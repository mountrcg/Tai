import Foundation

/// Adaptive Unscented Kalman Filter with RTS Smoothing
///
/// Ports the algorithm from AAPS UnscentedKalmanFilterPlugin.kt (Tsunami plugin).
///
/// KEY FEATURES:
/// - FIXED Q (process noise) - tuned for realistic meal/insulin responses
/// - ADAPTIVE R (measurement noise) - adapts to changing sensor quality
/// - Learned R parameter persists across segments until major gap (>60 min)
/// - Chi-squared based outlier detection (99.99% confidence)
/// - Dynamic Q inflation for persistent large deviations
/// - Gap-based reset (>60 min gap resets learned R)
///
/// State vector: x = [G, Ġ]
///   G  — glucose concentration (mg/dL)
///   Ġ  — rate of glucose change (mg/dL/min)
///
/// Process model (per step of dt minutes):
///   G_new  = G  + Ġ * dt
///   Ġ_new  = Ġ  * RATE_DAMPING
///
/// After the forward pass, a Rauch-Tung-Striebel (RTS) backward smoother
/// corrects earlier estimates using information from later readings.

// MARK: - UKF Parameters

private let n = 2 // State dimension: [glucose, rate]
private let alpha: Double = 1.0 // Sigma-point spread
private let beta: Double = 0.0 // Gaussian assumption
private let kappa: Double = 3.0 // Secondary scaling
private let lambda: Double = alpha * alpha * (Double(n) + kappa) - Double(n) // = 2.0
private let gamma: Double = (Double(n) + lambda).squareRoot() // = 2.0

// Sigma-point weights
private let wm0: Double = lambda / (Double(n) + lambda) // = 0.5
private let wc0: Double = lambda / (Double(n) + lambda) + (1 - alpha * alpha + beta) // = 0.5
private let wi: Double = 1.0 / (2.0 * (Double(n) + lambda)) // = 0.125

// Process noise (FIXED, tuned for realistic glucose dynamics)
private let Q00: Double = 1.0 // Glucose process noise (mg/dL)²
private let Q11: Double = 0.40 // Rate process noise (mg/dL/min)²

// Measurement noise (ADAPTIVE)
private let R_INIT: Double = 25.0 // Initial R: ~5 mg/dL std dev
private let R_MIN: Double = 16.0 // Min R: ~4 mg/dL std dev (excellent sensor)
private let R_MAX: Double = 196.0 // Max R: ~14 mg/dL std dev (poor sensor)
private let R_EFF_MAX: Double = 400.0 // Max effective R for outlier handling

// Innovation tracking for adaptive R
private let INNOVATION_WINDOW = 48 // 240 minutes of history

// Rate dynamics
private let RATE_DAMPING: Double = 0.98

// Outlier detection (Mahalanobis)
private let CHI2_THRESHOLD: Double = 15.13 // 99.99% confidence, 1 DOF
private let OUTLIER_ABSOLUTE: Double = 65.0 // mg/dL absolute innovation limit

// Gap / segment thresholds
private let MINOR_GAP_THRESHOLD: Double = 7.0 // Minutes - bridge with prediction
private let MAJOR_GAP_MINUTES: Double = 60.0 // >60 min gap resets learned R
private let RATE_DECAY_TIME_CONSTANT: Double = 30.0 // Minutes - physiological decay
private let RATE_BOUNDS: ClosedRange<Double> = -4.0 ... 4.0

// Covariance initialization
private let P00_INIT: Double = 16.0 // Glucose variance init
private let P11_INIT: Double = 1.0 // Rate variance init

// Covariance limits
private let MAX_GLUCOSE_VARIANCE: Double = 400.0 // Max 20 mg/dL std dev
private let MAX_RATE_VARIANCE: Double = 4.0 // Max 2 mg/dL/min std dev

// MARK: - Forward-pass result storage

private struct FilterStep {
    var x: (Double, Double) // state [G, Ġ]
    var P: (Double, Double, Double, Double) // 2x2 cov row-major [P00,P01,P10,P11]
    var xPred: (Double, Double)
    var PPred: (Double, Double, Double, Double)
    var dt: Double // time step used for prediction
    var index: Int // original array index
}

// MARK: - UnscentedKalmanFilter

struct UnscentedKalmanFilter {
    // MARK: - Adaptive State (mutable, carries across segments within same session)

    /// Learned measurement noise - adapts to sensor quality
    private var learnedR: Double = R_INIT

    /// Innovation tracking for adaptive R estimation
    private var innovations: [Double] = []
    private var rawInnovationVariance: [Double] = []

    /// Consecutive large same-sign innovation tracker for dynamic Q inflation
    private var consecutiveLargeSameSign = 0
    private var lastNormInnovSign = 0

    /// Smooth an array of BloodGlucose readings using UKF + RTS.
    ///
    /// - Parameter readings: Array of readings, **must be sorted ascending by dateString**.
    /// - Returns: Copies of the readings with `glucose` and `sgv` replaced by smoothed values.
    mutating func smooth(_ readings: [BloodGlucose]) -> [BloodGlucose] {
        guard readings.count >= 2 else { return readings }

        // CRITICAL: Tsunami expects NEWEST FIRST (descending), but we receive OLDEST FIRST (ascending)
        // Reverse the array to match Tsunami's data order
        let reversed = readings.reversed()
        var result = Array(reversed)
        let segments = segmentIndices(result)

        for segmentIndices in segments {
            guard segmentIndices.count >= 2 else { continue }
            let smoothed = processSegment(readings: result, indices: segmentIndices)
            for (idx, value) in smoothed {
                // Clamp to reasonable glucose range to prevent Int overflow
                let clampedValue = value.clamped(to: 39.0 ... 400.0)
                result[idx].glucose = Int(clampedValue.rounded())
                result[idx].sgv = Int(clampedValue.rounded())
            }
        }

        // Reverse back to original order (oldest first) before returning
        return result.reversed()
    }

    // MARK: - Segmentation

    /// Split reading indices into segments at major gaps (>60 min).
    /// Each major gap resets the learned R parameter.
    private mutating func segmentIndices(_ readings: [BloodGlucose]) -> [[Int]] {
        var segments: [[Int]] = []
        var current: [Int] = [0]
        var isFirstSegment = true

        for i in 1 ..< readings.count {
            let prev = readings[i - 1]
            let curr = readings[i]
            let dtMin = curr.dateString.timeIntervalSince(prev.dateString) / 60.0

            let majorGap = dtMin > MAJOR_GAP_MINUTES

            if majorGap {
                // Close current segment
                if current.count >= 2 { segments.append(current) }

                // Reset learned R on major gap (>60 min)
                if !isFirstSegment {
                    resetLearning()
                }

                // Start new segment
                current = [i]
            } else {
                current.append(i)
            }

            isFirstSegment = false
        }

        if current.count >= 2 { segments.append(current) }
        return segments
    }

    /// Reset learned R and innovation history
    private mutating func resetLearning() {
        learnedR = R_INIT
        innovations.removeAll()
        rawInnovationVariance.removeAll()
        consecutiveLargeSameSign = 0
        lastNormInnovSign = 0
    }

    // MARK: - Segment processing

    private mutating func processSegment(readings: [BloodGlucose], indices: [Int]) -> [(Int, Double)] {
        let segmentSize = indices.count
        guard segmentSize >= 2 else { return [] }

        // Initialize state from OLDEST point in segment (last index) - Tsunami line 580-590
        let oldestIdx = indices[segmentSize - 1]
        guard let initialGlucose = readings[oldestIdx].glucose.map(Double.init), initialGlucose > 38 else { return [] }

        var initialRate = 0.0
        if segmentSize >= 2, oldestIdx > 0 {
            let newerIdx = indices[segmentSize - 2]
            let dt = readings[newerIdx].dateString.timeIntervalSince(readings[oldestIdx].dateString) / 60.0
            if dt >= 3.0, dt <= 7.0 {
                initialRate = (Double(readings[newerIdx].glucose ?? 0) - initialGlucose) / dt
                initialRate = initialRate.clamped(to: RATE_BOUNDS)
            }
        }

        var x = (initialGlucose, initialRate)
        var P = (P00_INIT, 0.0, 0.0, P11_INIT)
        var R = learnedR

        // Storage for forward pass - Tsunami line 597-599
        var forwardStates: [FilterStep] = []
        var forwardResults = Array(repeating: 0.0, count: segmentSize)
        forwardResults[segmentSize - 1] = x.0

        // Forward pass: loop from second-oldest toward newest - Tsunami line 610
        for k in stride(from: segmentSize - 2, through: 0, by: -1) {
            let idx = indices[k]
            let reading = readings[idx]

            // Compute dt to NEXT reading (which is older in time)
            let nextIdx = indices[k + 1]
            let dt = max(reading.dateString.timeIntervalSince(readings[nextIdx].dateString) / 60.0, 0.5)

            // Handle minor gaps within segment (Tsunami line 614-622)
            if dt > MINOR_GAP_THRESHOLD, dt <= MAJOR_GAP_MINUTES {
                let qScale = dt / 5.0
                P.0 = min(P.0 + Q00 * qScale, MAX_GLUCOSE_VARIANCE)
                P.3 = min(P.3 + Q11 * qScale, MAX_RATE_VARIANCE)
                x.1 *= exp(-dt / RATE_DECAY_TIME_CONSTANT)
            }

            // Covariance sanity checks (Tsunami line 625-626)
            P.0 = P.0.clamped(to: 0.1 ... MAX_GLUCOSE_VARIANCE)
            P.3 = P.3.clamped(to: 0.001 ... MAX_RATE_VARIANCE)

            // Clamp dt for predict
            let dtClamped = dt.clamped(to: 3.5 ... 6.5)

            // Predict
            let (xPred, PPred) = predict(x: x, P: P, dt: dtClamped)

            let stateBefore = FilterStep(x: x, P: P, xPred: xPred, PPred: PPred, dt: dtClamped, index: idx)

            let z = reading.glucose.map(Double.init) ?? 0.0

            // Skip error codes (Tsunami line 636-646)
            if z <= 38.0 {
                x = xPred
                P = PPred
                let resultIdx = k
                forwardResults[resultIdx] = x.0
                forwardStates.insert(stateBefore, at: 0) // Add to front
                continue
            }

            // Calculate innovation and Mahalanobis distance
            let innovation = z - xPred.0
            let innovationVariance = PPred.0 + R
            let std = innovationVariance.squareRoot()
            let norm = innovation / std
            let mahalSq = (innovation * innovation) / innovationVariance

            // Update persistence counters for dynamic Q inflation
            let sign: Int
            if norm > 0.0 {
                sign = 1
            } else if norm < 0.0 {
                sign = -1
            } else {
                sign = 0
            }

            if abs(norm) > 3.0, sign != 0, sign == lastNormInnovSign {
                consecutiveLargeSameSign += 1
            } else if abs(norm) > 3.0, sign != 0 {
                consecutiveLargeSameSign = 1
            } else {
                consecutiveLargeSameSign = 0
            }
            lastNormInnovSign = sign

            // Soft-gated robust update with dynamic Q inflation
            let rScale = max(1.0, mahalSq / CHI2_THRESHOLD)
            let R_eff = min(R * rScale, R_EFF_MAX)

            // Dynamic Q inflation for persistent large deviations
            let qInflateAllowed = consecutiveLargeSameSign >= 2
            let zScore = abs(norm).clamped(to: 1.0 ... Double.greatestFiniteMagnitude)
            let qScale = qInflateAllowed ? zScore.clamped(to: 1.0 ... 3.0) : 1.0

            // Build temporary Q with inflation if needed
            let (xPredEff, PPredEff): ((Double, Double), (Double, Double, Double, Double))
            if qScale > 1.0 {
                let Q_temp = (Q00 * min(qScale, 2.0), 0.0, 0.0, Q11 * qScale)
                (xPredEff, PPredEff) = predict(x: x, P: P, Q: Q_temp, dt: dtClamped)
            } else {
                (xPredEff, PPredEff) = (xPred, PPred)
            }

            // Always update with effective R
            update(xPred: xPredEff, PPred: PPredEff, z: z, R: R_eff, xOut: &x, POut: &P)

            // Track innovation for adaptive R (skip if extreme to avoid mislearning)
            let skipRUpdate = abs(norm) > 3.0
            trackInnovation(innovation: innovation, innovationVariance: innovationVariance)
            if !skipRUpdate {
                R = adaptMeasurementNoise(currentR: R)
            }

            // Store forward results - Tsunami line 729-731
            let resultIdx = k
            forwardResults[resultIdx] = x.0
            forwardStates.insert(stateBefore, at: 0) // Add to front
        }

        // Update learned R for next segment
        learnedR = R

        guard !forwardStates.isEmpty else { return [] }

        // --- Backward RTS smoother (Tsunami line 745-761) ---
        var smoothedResults = forwardResults

        if segmentSize >= 3, !forwardStates.isEmpty {
            let maxSmoothSteps = min(segmentSize - 1, forwardStates.count)
            var xSmooth = (forwardResults[0], x.1)

            for i in 1 ..< maxSmoothSteps + 1 {
                guard i - 1 < forwardStates.count else { break }
                let state = forwardStates[i - 1]
                let C = rtsGain(P: state.P, PPred: state.PPred, dt: state.dt)

                let dx0 = xSmooth.0 - state.xPred.0
                let dx1 = xSmooth.1 - state.xPred.1

                xSmooth.0 = forwardResults[i] + C.0 * dx0 + C.1 * dx1
                xSmooth.1 = state.x.1 + C.2 * dx0 + C.3 * dx1

                smoothedResults[i] = xSmooth.0
            }
        }

        // Return results - Tsunami line 764-768
        return indices.enumerated().map { k, idx in
            (idx, max(smoothedResults[k], 39.0))
        }
    }

    private func reading(readings: [BloodGlucose], step: FilterStep) -> BloodGlucose {
        readings[step.index]
    }

    // MARK: - Adaptive R Estimation

    /// Track innovation for adaptive R estimation
    private mutating func trackInnovation(innovation: Double, innovationVariance: Double) {
        let normalizedSq = (innovation * innovation) / innovationVariance
        let rawSq = innovation * innovation

        innovations.append(normalizedSq)
        rawInnovationVariance.append(rawSq)

        if innovations.count > INNOVATION_WINDOW {
            innovations.removeFirst()
        }
        if rawInnovationVariance.count > INNOVATION_WINDOW {
            rawInnovationVariance.removeFirst()
        }
    }

    /// Adapt measurement noise based on innovation statistics (Tsunami approach)
    private func adaptMeasurementNoise(currentR: Double) -> Double {
        guard innovations.count >= 8 else { return currentR }

        let avgInnovSq = median(innovations)

        // Skip adaptation if recent innovations are extreme
        let hasExtreme = innovations.contains { $0 > 9.0 } // |ν|/σ > 3 → squared > 9
        if hasExtreme {
            return currentR.clamped(to: R_MIN ... R_MAX)
        }

        var newR = currentR

        // Median-based gentle correction toward raw innovation variance
        if avgInnovSq >= 1.1 || avgInnovSq <= 0.9 {
            let medianRaw = median(rawInnovationVariance)
            newR = currentR + 0.06 * (medianRaw - currentR)
        }

        return newR.clamped(to: R_MIN ... R_MAX)
    }

    /// Calculate median of array
    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let count = sorted.count

        if count == 0 {
            return 0.0
        } else if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        } else {
            return sorted[count / 2]
        }
    }

    // MARK: - Sigma points

    private func sigmaPoints(x: (Double, Double), P: (Double, Double, Double, Double)) -> [(Double, Double)] {
        let sqP = choleskySqrt2x2(P)
        let x0 = x
        let x1 = x
        let x2 = x
        let x3 = x
        let x4 = x

        // Center
        let pts = [
            x0,
            (x1.0 + gamma * sqP.0, x1.1 + gamma * sqP.1), // +col0
            (x2.0 + gamma * sqP.2, x2.1 + gamma * sqP.3), // +col1
            (x3.0 - gamma * sqP.0, x3.1 - gamma * sqP.1), // -col0
            (x4.0 - gamma * sqP.2, x4.1 - gamma * sqP.3)
        ] // -col1
        return pts
    }

    // MARK: - Cholesky square root (2×2, column-major output)

    /// Returns lower-triangular L such that L*L^T = P.
    /// Output columns: (col0_row0, col0_row1, col1_row0, col1_row1)
    private func choleskySqrt2x2(_ P: (Double, Double, Double, Double))
        -> (Double, Double, Double, Double)
    {
        let a = P.0
        let b = (P.1 + P.2) / 2.0 // enforce symmetry
        let d = P.3

        let l11 = max(a, 1E-9).squareRoot()
        let l21 = b / l11
        let disc = d - l21 * l21

        if disc < -1E-9 {
            // Numerical fallback
            return (max(a, 0.1).squareRoot(), 0.0, 0.0, max(d, 0.01).squareRoot())
        }
        let l22 = max(disc, 1E-9).squareRoot()

        // Columns: col0=(l11,l21), col1=(0,l22)
        return (l11, l21, 0.0, l22)
    }

    // MARK: - Predict

    private func predict(
        x: (Double, Double),
        P: (Double, Double, Double, Double),
        dt: Double
    ) -> ((Double, Double), (Double, Double, Double, Double)) {
        let Q = (Q00, 0.0, 0.0, Q11)
        return predict(x: x, P: P, Q: Q, dt: dt)
    }

    private func predict(
        x: (Double, Double),
        P: (Double, Double, Double, Double),
        Q: (Double, Double, Double, Double),
        dt: Double
    ) -> ((Double, Double), (Double, Double, Double, Double)) {
        let pts = sigmaPoints(x: x, P: P)

        // Propagate through process model
        let pPred = pts.map { p -> (Double, Double) in
            (p.0 + p.1 * dt, p.1 * RATE_DAMPING)
        }

        // Predicted mean
        var xPred = (0.0, 0.0)
        xPred.0 = wm0 * pPred[0].0 + wi * (pPred[1].0 + pPred[2].0 + pPred[3].0 + pPred[4].0)
        xPred.1 = wm0 * pPred[0].1 + wi * (pPred[1].1 + pPred[2].1 + pPred[3].1 + pPred[4].1)

        // Predicted covariance
        var PPred = (0.0, 0.0, 0.0, 0.0)
        let allWc = [wc0, wi, wi, wi, wi]
        for (i, p) in pPred.enumerated() {
            let dx0 = p.0 - xPred.0
            let dx1 = p.1 - xPred.1
            PPred.0 += allWc[i] * dx0 * dx0
            PPred.1 += allWc[i] * dx0 * dx1
            PPred.2 += allWc[i] * dx1 * dx0
            PPred.3 += allWc[i] * dx1 * dx1
        }

        // Add process noise (scale with dt)
        let qScale = dt / 5.0
        PPred.0 += Q.0 * qScale
        PPred.3 += Q.3 * qScale

        // Enforce positive definiteness only (Tsunami line 1020-1021)
        PPred.0 = max(PPred.0, 0.1)
        PPred.3 = max(PPred.3, 0.001)

        return (xPred, PPred)
    }

    // MARK: - Update

    private func update(
        xPred: (Double, Double),
        PPred: (Double, Double, Double, Double),
        z: Double,
        R: Double,
        xOut: inout (Double, Double),
        POut: inout (Double, Double, Double, Double)
    ) {
        let pts = sigmaPoints(x: xPred, P: PPred)

        // Measurement model: h(x) = glucose = x.0
        let zSigma = pts.map(\.0)
        let zPredMean = wm0 * zSigma[0] + wi * (zSigma[1] + zSigma[2] + zSigma[3] + zSigma[4])

        let allWc = [wc0, wi, wi, wi, wi]

        // Innovation covariance
        var Pzz = 0.0
        for (i, zs) in zSigma.enumerated() {
            let dz = zs - zPredMean
            Pzz += allWc[i] * dz * dz
        }
        Pzz += R

        // Cross covariance (Pxz)
        var Pxz0 = 0.0, Pxz1 = 0.0
        for (i, (pt, zs)) in zip(pts, zSigma).enumerated() {
            let dx0 = pt.0 - xPred.0
            let dx1 = pt.1 - xPred.1
            let dz = zs - zPredMean
            Pxz0 += allWc[i] * dx0 * dz
            Pxz1 += allWc[i] * dx1 * dz
        }

        // Kalman gain
        let K0 = Pxz0 / Pzz
        let K1 = Pxz1 / Pzz

        // State update
        let innov = z - zPredMean
        xOut.0 = xPred.0 + K0 * innov
        xOut.1 = (xPred.1 + K1 * innov).clamped(to: RATE_BOUNDS)

        // Covariance update  P = PPred - K * Pzz * K^T (enforce positive definiteness)
        POut.0 = max(PPred.0 - K0 * Pzz * K0, 0.1)
        POut.1 = PPred.1 - K0 * Pzz * K1
        POut.2 = PPred.2 - K1 * Pzz * K0
        POut.3 = max(PPred.3 - K1 * Pzz * K1, 0.001)
    }

    // MARK: - RTS Smoother gain

    /// Compute Rauch-Tung-Striebel (RTS) smoother gain (Tsunami line 942-968)
    /// Returns the full 2×2 gain matrix C = P * F^T * PPred^-1
    private func rtsGain(
        P: (Double, Double, Double, Double),
        PPred: (Double, Double, Double, Double),
        dt: Double
    ) -> (Double, Double, Double, Double) {
        // Compute P * F^T where F = [[1, dt], [0, damping]]
        let PFt00 = P.0 + P.1 * dt
        let PFt01 = P.1 * RATE_DAMPING
        let PFt10 = P.2 + P.3 * dt
        let PFt11 = P.3 * RATE_DAMPING

        // Invert PPred (2x2 matrix inversion)
        let det = PPred.0 * PPred.3 - PPred.1 * PPred.2
        if abs(det) < 1E-10 {
            // Singular matrix - return zero gain
            return (0.0, 0.0, 0.0, 0.0)
        }

        let PPredInv00 = PPred.3 / det
        let PPredInv01 = -PPred.1 / det
        let PPredInv10 = -PPred.2 / det
        let PPredInv11 = PPred.0 / det

        // C = P * F^T * PPred^-1
        return (
            PFt00 * PPredInv00 + PFt01 * PPredInv10,
            PFt00 * PPredInv01 + PFt01 * PPredInv11,
            PFt10 * PPredInv00 + PFt11 * PPredInv10,
            PFt10 * PPredInv01 + PFt11 * PPredInv11
        )
    }
}

// MARK: - Helpers

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
