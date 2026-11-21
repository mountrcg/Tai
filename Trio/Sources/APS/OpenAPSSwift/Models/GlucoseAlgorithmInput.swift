import Foundation

struct GlucoseAlgorithmInput {
    let dosingReadings: [BloodGlucose]
    var denseRawReadings: [BloodGlucose]?
    var denseSmoothedReadings: [BloodGlucose]?
    var cadence: GlucoseCadence = .legacy
    var sourceIdentifier: String?
    var observationEpochID: UUID?
    var generationID: UUID?
    var supportedGridDates: [Date] = []

    var referenceDate: Date? { dosingReadings.first?.dateString }

    var hasAutosensCoverage: Bool {
        guard cadence.isDense else { return dosingReadings.count >= 72 }
        let dates = Set(supportedGridDates).sorted()
        guard dates.count >= 72, let oldest = dates.first, let newest = dates.last else { return false }
        return newest.timeIntervalSince(oldest) >= 355 * 60
    }
}
