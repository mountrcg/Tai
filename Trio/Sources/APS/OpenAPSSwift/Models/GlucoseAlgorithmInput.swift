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

struct GlucoseObservationContext {
    let sourceIdentifier: String
    let epochID: UUID
    let epochStart: Date
    let generationID: UUID
    let cadence: GlucoseCadence
    let preferencesJSON: String
    let smoothingEnabled: Bool
    let smoothingAlgorithm: String
    var settingsRevision: UUID?
}

extension Preferences {
    var glucoseObservationFingerprint: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
