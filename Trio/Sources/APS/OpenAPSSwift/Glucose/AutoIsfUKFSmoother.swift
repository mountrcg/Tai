import Foundation

struct AutoIsfUKFGlucoseValue: Equatable {
    enum Trend: String { case none, flat, doubleUp, singleUp, fortyFiveUp, doubleDown, singleDown, fortyFiveDown }
    let timestamp: Int64
    let value: Double
    var calibrated: Double?
    var smoothed: Double?
    var trend: Trend = .none
    var calibratedOrValue: Double { calibrated ?? value }
}

/// Numeric port of AAPS-autoISF UnscentedKalmanFilterPlugin, including dense cadence commit de565d9a97.
final class AutoIsfUKFSmoother {
    private let n = 2
    private let alpha = 0.1
    private let beta = 2.0
    private let kappa = 0.0
    private let lambda: Double
    private let gamma: Double
    private var wm: [Double]
    private var wc: [Double]

    private let q: [Double] = [1.0, 0.0, 0.0, 0.35]

    private let rInit = 25.0
    private let rMin = 16.0
    private let rMax = 225.0
    private let rEffMax = 400.0
    private let innovationWindow = 18

    private let chiSquaredThreshold = 15.13 // χ² 99.99%, 1 DOF
    private let outlierAbsolute = 65.0

    private let maxGlucoseVariance = 400.0
    private let maxRateVariance = 4.0

    private let minorGapThreshold = 7.0
    private let majorGapThreshold = 60.0
    private let rateDecayTimeConstant = 30.0
    private let millisPerMinute = 60000.0

    private func rateDamp(_ dt: Double) -> Double { exp(-dt / rateDecayTimeConstant) }

    private var learnedR: Double
    private var innovations: [Double] = [] // normalized ν² / (P[0] + R)
    private var rawInnovationVariance: [Double] = [] // raw ν²
    private var predVarHistory: [Double] = [] // predicted variance P_pred[0]

    init(state: PersistedState = PersistedState()) {
        lambda = alpha * alpha * (Double(n) + kappa) - Double(n)
        gamma = (Double(n) + lambda).squareRoot()
        var wmArr = [Double](repeating: 0, count: 2 * n + 1)
        var wcArr = [Double](repeating: 0, count: 2 * n + 1)
        wmArr[0] = lambda / (Double(n) + lambda)
        wcArr[0] = lambda / (Double(n) + lambda) + (1 - alpha * alpha + beta)
        let w = 1.0 / (2.0 * (Double(n) + lambda))
        for i in 1 ..< (2 * n + 1) {
            wmArr[i] = w
            wcArr[i] = w
        }
        wm = wmArr
        wc = wcArr
        let restored = state.lastSavedTimestamp > 0 ? state : PersistedState()
        persistedState = restored
        learnedR = (rMin ... rMax).contains(restored.learnedR) ? restored.learnedR : rInit
        persistedState.learnedR = learnedR
    }

    struct PersistedState: Codable, Equatable {
        var learnedR = 25.0
        var sessionID = 0
        var lastSavedTimestamp: Int64 = 0
        var sensorChangeTimestamp: Int64 = 0
        var lastProcessedTimestamp: Int64 = 0
    }

    private(set) var persistedState: PersistedState
    private var sessionMeasurementCount = 0
    private var sessionOutlierCount = 0
    private var consecutiveOutliers = 0
    private var resetRequested = false

    func sensorChanged(at timestamp: Int64) {
        persistedState.sensorChangeTimestamp = timestamp
        resetRequested = true
    }

    private func resetLearning() {
        learnedR = rInit
        innovations.removeAll()
        rawInnovationVariance.removeAll()
        predVarHistory.removeAll()
        persistedState.sessionID += 1
        sessionMeasurementCount = 0
        sessionOutlierCount = 0
        consecutiveOutliers = 0
        saveState()
    }

    private func saveState() {
        persistedState.learnedR = learnedR
        persistedState.lastSavedTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
    }

    func smooth(_ input: [AutoIsfUKFGlucoseValue], learn: Bool = true) -> [AutoIsfUKFGlucoseValue] {
        let saved = (
            learnedR,
            innovations,
            rawInnovationVariance,
            predVarHistory,
            sessionMeasurementCount,
            sessionOutlierCount,
            consecutiveOutliers
        )
        defer {
            if !learn {
                (
                    learnedR,
                    innovations,
                    rawInnovationVariance,
                    predVarHistory,
                    sessionMeasurementCount,
                    sessionOutlierCount,
                    consecutiveOutliers
                ) = saved
            }
        }
        guard let newest = input.first else { return input }
        if learn {
            let elapsed = Double(newest.timestamp - persistedState.lastProcessedTimestamp) / millisPerMinute
            let invalidLearning = innovations.count >= 15 && innovations.reduce(0, +) / Double(innovations.count) > 12
            if resetRequested || persistedState.lastProcessedTimestamp == 0 || elapsed < 0 || elapsed > 1440 || invalidLearning {
                resetRequested = false
                resetLearning()
            }
        }
        var data = input
        let segments = findDataSegments(data)
        let previousTimestamp = learn ? persistedState.lastProcessedTimestamp : Int64.max
        if !segments.isEmpty {
            if learn { persistedState.lastProcessedTimestamp = newest.timestamp }
            for segment in segments {
                processSegment(&data, startIdx: segment.startIdx, endIdx: segment.endIdx, previousTimestamp: previousTimestamp)
            }
            if data.contains(where: { $0.timestamp > previousTimestamp }) { saveState() }
        }
        for i in data.indices {
            if data[i].smoothed == nil || data[i].smoothed == 0 || data[i].smoothed?.isFinite == false {
                data[i].smoothed = max(data[i].calibratedOrValue.isFinite ? data[i].calibratedOrValue : 39, 39)
                data[i].trend = .none
            }
        }
        return data
    }

    static func medianSpacingMinutes(_ data: [AutoIsfUKFGlucoseValue]) -> Double? {
        let intervals = zip(data, data.dropFirst()).lazy.map { Double($0.timestamp - $1.timestamp) / 60000 }
            .filter { $0 > 0 && $0 <= 7 }.prefix(30).sorted()
        guard intervals.count >= 5 else { return nil }
        let mid = intervals.count / 2
        return intervals.count.isMultiple(of: 2) ? (intervals[mid - 1] + intervals[mid]) / 2 : intervals[mid]
    }

    private func denseCadence(_ data: [AutoIsfUKFGlucoseValue]) -> Bool {
        (Self.medianSpacingMinutes(data) ?? .infinity) <= 3.5
    }

    private func findDataSegments(_ data: [AutoIsfUKFGlucoseValue]) -> [(startIdx: Int, endIdx: Int)] {
        if data.count < 2 { return [] }
        var segments: [(Int, Int)] = []
        var segmentStart = 0
        for i in 0 ..< (data.count - 1) {
            let timeDiff = Double(data[i].timestamp - data[i + 1].timestamp) / millisPerMinute
            if !(timeDiff >= (denseCadence(data) ? 0.5 : 2.0) && timeDiff <= majorGapThreshold) || data[i].value == 38.0 {
                if i - segmentStart >= 2 { segments.append((segmentStart, i)) }
                segmentStart = i + 1
            }
        }
        if data.count - segmentStart >= 2 { segments.append((segmentStart, data.count - 1)) }
        return segments
    }

    private struct FilterState {
        let x: [Double]
        let p: [Double]
        let xPred: [Double]
        let pPred: [Double]
        let dt: Double
    }

    private func processSegment(
        _ data: inout [AutoIsfUKFGlucoseValue],
        startIdx: Int, endIdx: Int, previousTimestamp: Int64
    ) {
        let segmentSize = endIdx - startIdx + 1
        if segmentSize < 2 {
            data[startIdx].smoothed = max(data[startIdx].calibratedOrValue, 39.0)
            return
        }

        let initialGlucose = data[endIdx].calibratedOrValue
        var initialRate = 0.0
        if endIdx > 0 {
            let dt = Double(data[endIdx - 1].timestamp - data[endIdx].timestamp) / millisPerMinute
            if dt >= (denseCadence(data) ? 0.5 : 3.0), dt <= 7.0 {
                initialRate = (data[endIdx - 1].calibratedOrValue - data[endIdx].calibratedOrValue) / dt
                initialRate = min(max(initialRate, -4.0), 4.0)
            }
        }

        var x = [initialGlucose, initialRate]
        var p = [16.0, 0.0, 0.0, 1.0]
        var r = learnedR

        var forwardStates: [FilterState] = [] // newest-first
        var forwardResults = [Double](repeating: 0, count: segmentSize)
        forwardResults[segmentSize - 1] = x[0]

        var recentSigns: [Int] = [] // newest-first, cap 3

        var i = endIdx - 1
        while i >= startIdx {
            let dt = Double(data[i].timestamp - data[i + 1].timestamp) / millisPerMinute

            if dt > minorGapThreshold, dt <= majorGapThreshold { x[1] *= rateDamp(dt) }

            p[0] = min(max(p[0], 0.1), maxGlucoseVariance)
            p[3] = min(max(p[3], 0.001), maxRateVariance)

            let dtUsed = dt
            let (xPredBase, pPredBase) = predict(x: x, p: p, q: q, dt: dtUsed)

            let z = data[i].calibratedOrValue

            if data[i].value <= 38.0 {
                let stateBefore = FilterState(x: x, p: p, xPred: xPredBase, pPred: pPredBase, dt: dtUsed)
                x[0] = xPredBase[0]
                x[1] = xPredBase[1]
                p = pPredBase
                forwardResults[i - startIdx] = x[0]
                forwardStates.append(stateBefore)
                i -= 1
                continue
            }

            let innovation = z - xPredBase[0]
            let innovationVarianceRaw = pPredBase[0] + r
            let stdRaw = innovationVarianceRaw.squareRoot()
            let normRaw = innovation / stdRaw

            let sign: Int = normRaw > 0.0 ? 1 : (normRaw < 0.0 ? -1 : 0)
            if recentSigns.count == 3 { recentSigns.removeLast() }
            recentSigns.insert(abs(normRaw) > 2.0 ? sign : 0, at: 0)
            let sameSignCount = sign == 0 ? 0 : recentSigns.filter { $0 == sign }.count
            let qInflateAllowed = sameSignCount >= 2
            let absn = abs(normRaw)

            let rScale = 1.0 + max(0.0, absn - 2.0)
            let rEff = min(r * rScale, min(r + 100.0, rEffMax))

            let zScore = max(absn, 1.0)
            let qScale = qInflateAllowed ? min(max(zScore, 1.0), 3.0) : 1.0
            var tempQ = q
            if qScale > 1.0 {
                tempQ[0] = q[0] * min(qScale, 2.0)
                tempQ[3] = q[3] * qScale
            }

            let (xPredEff, pPredEff): ([Double], [Double]) =
                qScale > 1.0 ? predict(x: x, p: p, q: tempQ, dt: dtUsed) : (xPredBase, pPredBase)

            let stateBefore = FilterState(x: x, p: p, xPred: xPredEff, pPred: pPredEff, dt: dtUsed)

            let innovationVarianceEff = pPredEff[0] + rEff

            predVarHistory.insert(pPredEff[0], at: 0)
            if predVarHistory.count > innovationWindow { predVarHistory.removeLast() }

            update(xPred: xPredEff, pPred: pPredEff, z: z, r: rEff, x: &x, p: &p)

            trackInnovation(innovation: innovation, innovationVariance: innovationVarianceEff)

            let skipRUpdate = qInflateAllowed || absn > 3.0
            if !skipRUpdate { r = adaptMeasurementNoise(currentR: r) }

            if data[i].timestamp > previousTimestamp {
                sessionMeasurementCount += 1
                if innovation * innovation / innovationVarianceEff > chiSquaredThreshold || abs(innovation) > outlierAbsolute {
                    sessionOutlierCount += 1
                }
            }
            forwardResults[i - startIdx] = x[0]
            forwardStates.append(stateBefore)
            i -= 1
        }

        learnedR = r

        var smoothedResults = forwardResults
        if segmentSize >= 3, !forwardStates.isEmpty {
            let maxSmoothSteps = min(segmentSize - 1, forwardStates.count)
            var xSmooth = [forwardResults[0], x[1]]
            for step in 1 ... maxSmoothSteps {
                let state = forwardStates[forwardStates.count - step]
                let c = computeSmootherGain(p: state.p, pPred: state.pPred, dt: state.dt)
                let dx0 = xSmooth[0] - state.xPred[0]
                let dx1 = xSmooth[1] - state.xPred[1]
                xSmooth[0] = forwardResults[step] + c[0] * dx0 + c[1] * dx1
                xSmooth[1] = state.x[1] + c[2] * dx0 + c[3] * dx1
                smoothedResults[step] = xSmooth[0]
            }
        }

        for idx in startIdx ... endIdx {
            data[idx].smoothed = max(smoothedResults[idx - startIdx], 39.0)
            data[idx].trend = idx == startIdx ? Self.trend(x[1]) : .none
        }
    }

    private func trackInnovation(innovation: Double, innovationVariance: Double) {
        let normalizedSq = (innovation * innovation) / innovationVariance
        let rawSq = innovation * innovation
        innovations.insert(normalizedSq, at: 0)
        rawInnovationVariance.insert(rawSq, at: 0)
        if innovations.count > innovationWindow { innovations.removeLast() }
        if rawInnovationVariance.count > innovationWindow { rawInnovationVariance.removeLast() }
    }

    private func adaptMeasurementNoise(currentR: Double) -> Double {
        if innovations.count < 12 || predVarHistory.isEmpty { return currentR }

        func trimmedMean(_ v: [Double], trim: Double = 0.20) -> Double {
            if v.isEmpty { return 0.0 }
            let s = v.sorted()
            let k = min(Int(Double(s.count) * trim), (s.count - 1) / 2)
            let core = s[k ..< (s.count - k)]
            return core.reduce(0, +) / Double(core.count)
        }

        let nSize = innovations.count
        let mRaw = trimmedMean(Array(rawInnovationVariance.prefix(nSize)))
        let pyyMed = trimmedMean(Array(predVarHistory.prefix(nSize)))

        let rHatRaw = max(mRaw - pyyMed, rMin)
        let rHat = min(max(rHatRaw, rMin), rMax)

        let goingUp = rHat > currentR
        let k = goingUp ? 0.18 : 0.12
        let step = currentR + k * (rHat - currentR)

        let upCap = goingUp ? 1.20 : 1.00
        let dnCap = goingUp ? 1.00 : 0.90
        let clamped = min(max(min(max(step, currentR * dnCap), currentR * upCap), rMin), rMax)

        let eta = 0.25
        return (1.0 - eta) * currentR + eta * clamped
    }

    private static func trend(_ rate: Double) -> AutoIsfUKFGlucoseValue.Trend {
        if rate > 2 { return .doubleUp }
        if rate > 1 { return .singleUp }
        if rate > 0.5 { return .fortyFiveUp }
        if rate < -2 { return .doubleDown }
        if rate < -1 { return .singleDown }
        if rate < -0.5 { return .fortyFiveDown }
        return .flat
    }

    private func computeSmootherGain(p: [Double], pPred: [Double], dt: Double) -> [Double] {
        let damp = rateDamp(dt)
        let pfT00 = p[0] + p[1] * dt
        let pfT01 = p[1] * damp
        let pfT10 = p[2] + p[3] * dt
        let pfT11 = p[3] * damp
        let det = pPred[0] * pPred[3] - pPred[1] * pPred[2]
        if abs(det) < 1E-10 { return [0, 0, 0, 0] }
        let inv00 = pPred[3] / det
        let inv01 = -pPred[1] / det
        let inv10 = -pPred[2] / det
        let inv11 = pPred[0] / det
        return [
            pfT00 * inv00 + pfT01 * inv10,
            pfT00 * inv01 + pfT01 * inv11,
            pfT10 * inv00 + pfT11 * inv10,
            pfT10 * inv01 + pfT11 * inv11
        ]
    }

    private func predict(x: [Double], p: [Double], q: [Double], dt: Double) -> ([Double], [Double]) {
        let sigmaPoints = generateSigmaPoints(x: x, p: p)
        let damp = rateDamp(dt)
        var sigmaPointsPred = [[Double]](repeating: [0, 0], count: 2 * n + 1)
        for i in 0 ..< (2 * n + 1) {
            sigmaPointsPred[i][0] = sigmaPoints[i][0] + sigmaPoints[i][1] * dt
            sigmaPointsPred[i][1] = sigmaPoints[i][1] * damp
        }
        var xPred = [0.0, 0.0]
        for i in 0 ..< (2 * n + 1) {
            xPred[0] += wm[i] * sigmaPointsPred[i][0]
            xPred[1] += wm[i] * sigmaPointsPred[i][1]
        }
        var pPred = [0.0, 0.0, 0.0, 0.0]
        for i in 0 ..< (2 * n + 1) {
            let dx0 = sigmaPointsPred[i][0] - xPred[0]
            let dx1 = sigmaPointsPred[i][1] - xPred[1]
            pPred[0] += wc[i] * dx0 * dx0
            pPred[1] += wc[i] * dx0 * dx1
            pPred[2] += wc[i] * dx1 * dx0
            pPred[3] += wc[i] * dx1 * dx1
        }
        let qScale = dt / 5.0
        pPred[0] += q[0] * qScale
        pPred[3] += q[3] * qScale
        pPred[0] = max(pPred[0], 0.1)
        pPred[3] = max(pPred[3], 0.001)
        return (xPred, pPred)
    }

    private func update(xPred: [Double], pPred: [Double], z: Double, r: Double, x: inout [Double], p: inout [Double]) {
        let sigmaPoints = generateSigmaPoints(x: xPred, p: pPred)
        var zSigma = [Double](repeating: 0, count: 2 * n + 1)
        for i in 0 ..< (2 * n + 1) { zSigma[i] = sigmaPoints[i][0] }

        var zPred = 0.0
        for i in 0 ..< (2 * n + 1) { zPred += wm[i] * zSigma[i] }

        var pzz = 0.0
        for i in 0 ..< (2 * n + 1) {
            let dz = zSigma[i] - zPred
            pzz += wc[i] * dz * dz
        }
        pzz += r

        if pzz < 1E-6 {
            x[0] = xPred[0]
            x[1] = xPred[1]
            p = pPred
            return
        }

        var pxz = [0.0, 0.0]
        for i in 0 ..< (2 * n + 1) {
            let dx0 = sigmaPoints[i][0] - xPred[0]
            let dx1 = sigmaPoints[i][1] - xPred[1]
            let dz = zSigma[i] - zPred
            pxz[0] += wc[i] * dx0 * dz
            pxz[1] += wc[i] * dx1 * dz
        }

        let k = [pxz[0] / pzz, pxz[1] / pzz]
        let innovation = z - zPred
        x[0] = xPred[0] + k[0] * innovation
        x[1] = xPred[1] + k[1] * innovation
        x[1] = min(max(x[1], -4.0), 4.0)

        p[0] = pPred[0] - k[0] * pzz * k[0]
        p[1] = pPred[1] - k[0] * pzz * k[1]
        p[2] = pPred[2] - k[1] * pzz * k[0]
        p[3] = pPred[3] - k[1] * pzz * k[1]
        p[0] = max(p[0], 0.1)
        p[3] = max(p[3], 0.001)
    }

    private func generateSigmaPoints(x: [Double], p: [Double]) -> [[Double]] {
        var sigmaPoints = [[Double]](repeating: [0, 0], count: 2 * n + 1)
        let sqrtP = matrixSqrt2x2(p)
        sigmaPoints[0][0] = x[0]
        sigmaPoints[0][1] = x[1]
        for i in 0 ..< n {
            sigmaPoints[i + 1][0] = x[0] + gamma * sqrtP[i * 2 + 0]
            sigmaPoints[i + 1][1] = x[1] + gamma * sqrtP[i * 2 + 1]
            sigmaPoints[i + 1 + n][0] = x[0] - gamma * sqrtP[i * 2 + 0]
            sigmaPoints[i + 1 + n][1] = x[1] - gamma * sqrtP[i * 2 + 1]
        }
        return sigmaPoints
    }

    private func matrixSqrt2x2(_ p: [Double]) -> [Double] {
        let a = p[0]
        let b = (p[1] + p[2]) / 2.0
        let d = p[3]
        let l11 = max(a, 1E-9).squareRoot()
        let l21 = b / l11
        let discriminant = d - l21 * l21
        if discriminant < -1E-9 {
            return [max(a, 0.1).squareRoot(), 0.0, 0.0, max(d, 0.01).squareRoot()]
        }
        let l22 = max(discriminant, 1E-9).squareRoot()
        return [l11, l21, 0.0, l22]
    }
}
