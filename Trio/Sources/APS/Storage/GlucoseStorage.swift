import AVFAudio
import Combine
import CoreData
import Foundation
import LoopKit
import SwiftDate
import SwiftUI
import Swinject

protocol GlucoseStorage {
    var updatePublisher: AnyPublisher<Void, Never> { get }
    var observationContext: GlucoseObservationContext? { get }
    func observationHistory(sourceIdentifier: String, epochID: UUID) async throws -> [BloodGlucose]
    func setObservationContext(_ context: GlucoseObservationContext?)
    func commitObservationChanges(_ observation: GlucoseObservationContext, context: NSManagedObjectContext) throws -> Bool
    func storeGlucose(_ glucose: [BloodGlucose], observation: GlucoseObservationContext?) async throws
    func backfillGlucose(_ glucose: [BloodGlucose], observation: GlucoseObservationContext?) async throws
    func getGlucoseAlgorithmInput(
        shouldSmoothGlucose: Bool, fetchHours: Decimal, context: GlucoseObservationContext?
    ) async throws -> GlucoseAlgorithmInput

    func storeGlucose(_ glucose: [BloodGlucose]) async throws
    func backfillGlucose(_ glucose: [BloodGlucose]) async throws
    func addManualGlucose(glucose: Int)
    func isGlucoseDataFresh(_ glucoseDate: Date?) -> Bool
    func syncDate() -> Date
    func filterTooFrequentGlucose(_ glucose: [BloodGlucose], at: Date) -> [BloodGlucose]
    func lastGlucoseDate() -> Date?
    func isGlucoseFresh() -> Bool
    func getGlucoseForAlgorithm(shouldSmoothGlucose: Bool, fetchHours: Decimal) async throws -> [BloodGlucose]
    func getGlucoseNotYetUploadedToNightscout() async throws -> [BloodGlucose]
    func getCGMStateNotYetUploadedToNightscout() async throws -> [NightscoutTreatment]
    func getGlucoseNotYetUploadedToHealth() async throws -> [BloodGlucose]
    func getManualGlucoseNotYetUploadedToHealth() async throws -> [BloodGlucose]
    func getCGMGlucoseNotYetUploadedToHealth() async throws -> [BloodGlucose]
    func getGlucoseNotYetUploadedToTidepool() async throws -> [StoredGlucoseSample]
    func getManualGlucoseNotYetUploadedToTidepool() async throws -> [StoredGlucoseSample]
//    func getGlucoseStatus() async throws -> GlucoseStatus? // FIXME: prepared for later use
    var alarm: GlucoseAlarm? { get }
    func deleteGlucose(_ treatmentObjectID: NSManagedObjectID) async
}

extension GlucoseStorage {
    func commitObservationChanges(_: GlucoseObservationContext, context _: NSManagedObjectContext) throws -> Bool { false }

    func observationHistory(sourceIdentifier _: String, epochID _: UUID) async throws -> [BloodGlucose] { [] }

    var observationContext: GlucoseObservationContext? { nil }
    func setObservationContext(_: GlucoseObservationContext?) {}
    func storeGlucose(_ glucose: [BloodGlucose], observation _: GlucoseObservationContext?) async throws {
        try await storeGlucose(glucose)
    }

    func backfillGlucose(_ glucose: [BloodGlucose], observation _: GlucoseObservationContext?) async throws {
        try await backfillGlucose(glucose)
    }

    func getGlucoseAlgorithmInput(
        shouldSmoothGlucose: Bool, fetchHours: Decimal, context _: GlucoseObservationContext?
    ) async throws -> GlucoseAlgorithmInput {
        GlucoseAlgorithmInput(dosingReadings: try await getGlucoseForAlgorithm(
            shouldSmoothGlucose: shouldSmoothGlucose, fetchHours: fetchHours
        ))
    }
}

final class BaseGlucoseStorage: GlucoseStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseGlucoseStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!

    private var activeObservation: GlucoseObservationContext?
    @Persisted(key: "autoIsfUKFLearnedState") private var denseUKFState = AutoIsfUKFSmoother.PersistedState()
    @Persisted(key: "autoIsfUKFEpochID") private var denseUKFEpochID: UUID? = nil
    private var denseEngine: AutoIsfUKFSmoother?
    private var denseCacheInput: [AutoIsfUKFGlucoseValue] = []
    private var denseCacheOutput: [AutoIsfUKFGlucoseValue] = []
    private var denseCacheGeneration: UUID?

    private func smoothDense(
        _ input: [AutoIsfUKFGlucoseValue],
        observation: GlucoseObservationContext
    ) -> [AutoIsfUKFGlucoseValue] {
        if denseEngine == nil { denseEngine = AutoIsfUKFSmoother(state: denseUKFState) }
        if denseUKFEpochID != observation.epochID {
            denseEngine?.sensorChanged(at: Int64(observation.epochStart.timeIntervalSince1970 * 1000))
            denseUKFEpochID = observation.epochID
            denseCacheInput = []
        }
        if input != denseCacheInput || denseCacheGeneration != observation.generationID {
            denseCacheOutput = denseEngine!.smooth(input)
            denseUKFState = denseEngine!.persistedState
            denseCacheInput = input
            denseCacheGeneration = observation.generationID
        }
        return denseCacheOutput
    }

    var observationContext: GlucoseObservationContext? {
        processQueue.sync { activeObservation.flatMap { isCurrent($0) ? $0 : nil } }
    }

    func setObservationContext(_ context: GlucoseObservationContext?) {
        processQueue.sync { activeObservation = context }
    }

    func observationHistory(sourceIdentifier: String, epochID: UUID) async throws -> [BloodGlucose] {
        let context = makeContext()
        return try await context.perform {
            let request = GlucoseStored.fetchRequest()
            request.predicate = NSPredicate(
                format: "sourceIdentifier == %@ AND observationEpochID == %@ AND isManual == NO AND date >= %@",
                sourceIdentifier, epochID as NSUUID, Date().addingTimeInterval(-4 * 3600) as NSDate
            )
            request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            request.fetchLimit = 64
            return try context.fetch(request).compactMap { row in
                guard let date = row.date else { return nil }
                return BloodGlucose(
                    sgv: Int(row.glucose),
                    date: Decimal(date.timeIntervalSince1970 * 1000),
                    dateString: date,
                    glucose: Int(row.glucose)
                )
            }
        }
    }

    func commitObservationChanges(_ observation: GlucoseObservationContext, context: NSManagedObjectContext) throws -> Bool {
        try processQueue.sync {
            guard isCurrent(observation) else { return false }
            return try settingsManager.withGlucoseInputRevision(observation.settingsRevision) {
                if context.hasChanges { try context.save() }
            }
        }
    }

    private func isCurrent(_ observation: GlucoseObservationContext) -> Bool {
        activeObservation?.generationID == observation.generationID &&
            settingsManager.glucoseInputRevision == observation.settingsRevision &&
            settingsManager.preferences.glucoseObservationFingerprint == observation.preferencesJSON &&
            settingsManager.settings.smoothGlucose == observation.smoothingEnabled &&
            settingsManager.settings.smoothingAlgorithm.rawValue == observation.smoothingAlgorithm &&
            settingsManager.settings.cgm == .plugin &&
            settingsManager.settings.cgmPluginIdentifier == observation.sourceIdentifier
    }

    private let updateSubject = PassthroughSubject<Void, Never>()

    var updatePublisher: AnyPublisher<Void, Never> {
        updateSubject.eraseToAnyPublisher()
    }

    // NOTE: no private Config enum here — this fork uses the global, runtime-tunable
    // `Config` (Trio/Sources/Config/Config.swift) for filterTime/minimumGlucose so the
    // CGM simulator can adjust them. A private enum would shadow it.
    private let makeContext: () -> NSManagedObjectContext

    init(resolver: Resolver, contextProvider: (() -> NSManagedObjectContext)? = nil) {
        makeContext = contextProvider ?? { CoreDataStack.shared.newTaskContext() }
        injectServices(resolver)
    }

    /// Backfills glucose values and stores in CoreData
    ///
    /// CGM managers will sometimes backfill glucose readings. To handle these backfilled values
    /// correctly, we need some logic to handle a few cases:
    ///  - _Not_ adding back previously deleted glucose
    ///  - Avoiding duplicate values for the same reading
    ///  - Avoiding overlapping glucose readings when switching sources
    ///  Of these corner cases, overlapping glucose readings when switching sources is both
    ///  the most challenging and most rare since it would happen if wearing two devices and
    ///  switching or moving from direct glucose handling to xdrip. It's not worth the complexity
    ///  to deal with source switching perfectly, so instead we will backfill glucose if and only if
    ///  it isn't within 3.5 minutes of an existing glucose reading, which is simple but not perfect.
    ///  But since this is a corner case that really shouldn't happen often, it's good enough.
    func backfillGlucose(_ glucose: [BloodGlucose]) async throws {
        let context = makeContext()
        context.name = "backfillGlucose"
        let clamped = clampToMinimum(glucose)

        try await context.perform {
            // remove already deleted glucose values
            let withoutDeletedGlucose = self.filterGlucoseValues(
                clamped,
                fetchRequest: DeletedGlucoseStored.fetchRequest(),
                timeBuffer: 1,
                context: context
            )

            // check for a 3.5 minute difference between existing values
            let filteredGlucose = self.filterGlucoseValues(
                withoutDeletedGlucose,
                fetchRequest: GlucoseStored.fetchRequest(),
                timeBuffer: 3.5 * 60,
                // Manual entries must not shadow CGM readings
                predicate: .cgmGlucose,
                context: context
            )

            guard !filteredGlucose.isEmpty else { return }

            do {
                // Store glucose values in Core Data
                try self.storeGlucoseInCoreData(filteredGlucose, context: context)
            } catch {
                throw CoreDataError.creationError(
                    function: #function,
                    file: #fileID
                )
            }
        }
    }

    func storeGlucose(_ glucose: [BloodGlucose]) async throws {
        let context = makeContext()
        context.name = "storeGlucose"
        let clamped = clampToMinimum(glucose)

        try await context.perform {
            // Get new glucose values that don't exist yet
            let newGlucose = self.filterGlucoseValues(
                clamped,
                fetchRequest: GlucoseStored.fetchRequest(),
                timeBuffer: 1,
                context: context
            )
            guard !newGlucose.isEmpty else { return }

            do {
                // Store glucose values in Core Data
                try self.storeGlucoseInCoreData(newGlucose, context: context)
            } catch {
                throw CoreDataError.creationError(
                    function: #function,
                    file: #fileID
                )
            }

            // Store CGM state if needed
            self.storeCGMState(clamped)
        }
    }

    func storeGlucose(_ glucose: [BloodGlucose], observation: GlucoseObservationContext?) async throws {
        guard let observation else { return try await storeGlucose(glucose) }
        try await storeObservedGlucose(glucose, observation: observation, backfill: false)
    }

    func backfillGlucose(_ glucose: [BloodGlucose], observation: GlucoseObservationContext?) async throws {
        guard let observation else { return try await backfillGlucose(glucose) }
        try await storeObservedGlucose(glucose, observation: observation, backfill: true)
    }

    private func storeObservedGlucose(
        _ glucose: [BloodGlucose], observation: GlucoseObservationContext, backfill: Bool
    ) async throws {
        let context = makeContext()
        context.name = "storeObservedGlucose"
        try await context.perform {
            try self.processQueue.sync {
                guard self.isCurrent(observation) else { return }
                var lastDate: Date?
                let unique = glucose.sorted { $0.dateString < $1.dateString }.filter { reading in
                    guard reading.mbg == nil, reading.dateString <= Date() else { return false }
                    if let lastDate, reading.dateString.timeIntervalSince(lastDate) <= 1 { return false }
                    lastDate = reading.dateString
                    return true
                }
                let undeleted = self.filterGlucoseValues(
                    unique, fetchRequest: DeletedGlucoseStored.fetchRequest(), timeBuffer: 1, context: context
                )
                for reading in undeleted {
                    let inEpoch = reading.dateString >= observation.epochStart
                    let dense = observation.cadence.isDense && inEpoch
                    let buffer: TimeInterval = backfill && !dense ? 3.5 * 60 : 1
                    let nonoverlapping = self.filterGlucoseValues(
                        [reading], fetchRequest: GlucoseStored.fetchRequest(), timeBuffer: buffer,
                        predicate: .cgmGlucose, context: context
                    )
                    guard !nonoverlapping.isEmpty else { continue }
                    if dense {
                        let otherEpoch = NSPredicate(
                            format: "isManual == NO AND (observationEpochID == nil OR observationEpochID != %@)",
                            observation.epochID as NSUUID
                        )
                        guard !self.filterGlucoseValues(
                            [reading], fetchRequest: GlucoseStored.fetchRequest(), timeBuffer: 3.5 * 60,
                            predicate: otherEpoch, context: context
                        ).isEmpty else { continue }
                    }
                    let stored = GlucoseStored(context: context)
                    var storedReading = dense ? reading : self.clampToMinimum([reading])[0]
                    storedReading.glucose = storedReading.glucose ?? storedReading.sgv
                    self.configureGlucoseEntry(stored, with: storedReading)
                    if inEpoch {
                        stored.sourceIdentifier = observation.sourceIdentifier
                        stored.observationEpochID = observation.epochID
                    }
                }
                if context.hasChanges {
                    let committed = try self.settingsManager.withGlucoseInputRevision(observation.settingsRevision) {
                        try context.save()
                    }
                    if !committed { context.rollback() }
                }
            }
        }
        updateSubject.send()
    }

    private func legacySmoothedReadings(_ rows: [GlucoseStored], context: NSManagedObjectContext) -> [GlucoseStored] {
        let copies = rows.filter { !$0.isManual }.map { row in
            let copy = GlucoseStored(entity: row.entity, insertInto: nil)
            copy.glucose = row.glucose
            copy.date = row.date
            return copy
        }
        switch settingsManager.settings.smoothingAlgorithm {
        case .exponential:
            BaseFetchGlucoseManager.applyExponentialSmoothingAndStore(
                glucoseReadings: copies, minimumWindowSize: 4, maximumAllowedGapMinutes: 12,
                xDripErrorGlucose: 38, minimumSmoothedGlucose: 39, firstOrderWeight: 0.4,
                firstOrderAlpha: 0.5, secondOrderAlpha: 0.4, secondOrderBeta: 1
            )
        case .ukf:
            var engine = UnscentedKalmanFilter()
            let raw = copies.reversed().compactMap { row -> BloodGlucose? in
                guard let date = row.date else { return nil }
                return BloodGlucose(
                    sgv: Int(row.glucose),
                    date: Decimal(date.timeIntervalSince1970 * 1000),
                    dateString: date,
                    glucose: Int(row.glucose)
                )
            }
            let smoothed = Dictionary(
                engine.smooth(raw).map { ($0.dateString, $0.glucose ?? $0.sgv ?? 39) },
                uniquingKeysWith: { first, _ in first }
            )
            for row in copies {
                if let date = row.date, let value = smoothed[date] { row.smoothedGlucose = NSDecimalNumber(value: value) }
            }
        case .adaptiveUkf:
            let request = OrefDetermination.fetchRequest()
            request.predicate = NSPredicate(
                format: "deliverAt >= %@",
                (rows.last?.date ?? Date()).addingTimeInterval(-1800) as NSDate
            )
            request.sortDescriptors = [NSSortDescriptor(key: "deliverAt", ascending: true)]
            let timeline = ((try? context.fetch(request)) ?? []).compactMap { row -> (timestamp: Int64, iob: Double)? in
                guard let date = row.deliverAt, let iob = row.iob else { return nil }
                return (Int64(date.timeIntervalSince1970 * 1000), iob.doubleValue)
            }
            let engine = AdaptiveUKFSmoother(iobAt: { BaseFetchGlucoseManager.iobAt($0, in: timeline) })
            let raw = copies.compactMap { row -> AdaptiveUKFGlucoseValue? in
                guard let date = row.date else { return nil }
                return AdaptiveUKFGlucoseValue(timestamp: Int64(date.timeIntervalSince1970 * 1000), value: Double(row.glucose))
            }
            let grid = engine.smooth(GlucoseBucketing.bucketed(raw))
            for row in copies {
                guard let date = row.date else { continue }
                if let value = GlucoseBucketing.interpolatedSmoothed(at: Int64(date.timeIntervalSince1970 * 1000), grid: grid),
                   value.isFinite { row.smoothedGlucose = NSDecimalNumber(value: max(39, value).rounded()) }
            }
        }
        return copies
    }

    private func clampToMinimum(_ glucose: [BloodGlucose]) -> [BloodGlucose] {
        glucose.map { entry in
            var clamped = entry
            if let raw = entry.glucose, raw < Config.minimumGlucose {
                debug(.cgm, "Clamped BG \(raw) mg/dL at \(entry.dateString) to \(Config.minimumGlucose) mg/dL")
                clamped.glucose = Config.minimumGlucose
            }
            if let raw = entry.sgv, raw < Config.minimumGlucose {
                clamped.sgv = Config.minimumGlucose
            }
            return clamped
        }
    }

    /// filter out duplicate CGM readings using matching timestamps
    ///
    /// This function will fetch dates from the `fetchRequest` and remove any glucose
    /// values that are within `timeBuffer` of the fetched dates. This logic is useful for
    /// deduplication checks or removing deleted CGM values from a list of backfilled readings.
    private func filterGlucoseValues(
        _ glucose: [BloodGlucose],
        fetchRequest: NSFetchRequest<NSFetchRequestResult>,
        timeBuffer: TimeInterval,
        predicate: NSPredicate? = nil,
        context: NSManagedObjectContext
    ) -> [BloodGlucose] {
        let datesToCheck = glucose.map(\.dateString).sorted()
        guard let firstDate = datesToCheck.first.map({ $0.addingTimeInterval(-timeBuffer) }),
              let lastDate = datesToCheck.last.map({ $0.addingTimeInterval(timeBuffer) })
        else {
            return glucose
        }
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "date >= %@", firstDate as NSDate),
            NSPredicate(format: "date <= %@", lastDate as NSDate)
        ] + [predicate].compactMap { $0 })
        fetchRequest.propertiesToFetch = ["date"]
        fetchRequest.resultType = .dictionaryResultType

        var existingDates = [Date]()
        do {
            let results = try context.fetch(fetchRequest) as? [NSDictionary]
            existingDates = results?.compactMap({ $0["date"] as? Date }) ?? []
        } catch {
            warning(.storage, "Fetching existing glucose dates failed", error: error)
        }

        // This is an inefficient filtering algorithm, but I'm assuming that the
        // time spans are short and that duplicates are rare, so in the common
        // case there won't be any existing dates.
        return glucose.filter { glucose in
            for existingDate in existingDates {
                let difference = abs(existingDate.timeIntervalSince(glucose.dateString))
                if difference <= timeBuffer {
                    return false
                }
            }
            return true
        }
    }

    private func storeGlucoseInCoreData(_ glucose: [BloodGlucose], context: NSManagedObjectContext) throws {
        if glucose.count > 1 {
            try storeGlucoseBatch(glucose, context: context)
        } else {
            try storeGlucoseRegular(glucose, context: context)
        }
    }

    private func storeGlucoseRegular(_ glucose: [BloodGlucose], context: NSManagedObjectContext) throws {
        for entry in glucose {
            let glucoseEntry = GlucoseStored(context: context)
            configureGlucoseEntry(glucoseEntry, with: entry)
        }

        guard context.hasChanges else { return }
        try context.save()
        updateSubject.send()
    }

    private func storeGlucoseBatch(_ glucose: [BloodGlucose], context: NSManagedObjectContext) throws {
        var remainingGlucose = glucose
        let batchInsert = NSBatchInsertRequest(
            entity: GlucoseStored.entity(),
            managedObjectHandler: { (managedObject: NSManagedObject) -> Bool in
                guard let glucoseEntry = managedObject as? GlucoseStored,
                      !remainingGlucose.isEmpty
                else {
                    return true
                }
                let entry = remainingGlucose.removeFirst()
                self.configureGlucoseEntry(glucoseEntry, with: entry)
                return false
            }
        )
        try context.execute(batchInsert)
        updateSubject.send()
    }

    private func configureGlucoseEntry(_ entry: GlucoseStored, with glucose: BloodGlucose) {
        entry.id = UUID()
        entry.glucose = Int16(glucose.glucose ?? 0)
        entry.date = glucose.dateString
        entry.direction = glucose.direction?.rawValue
        entry.isManual = glucose.mbg != nil
        entry.isUploadedToNS = false
        entry.isUploadedToHealth = false
        entry.isUploadedToTidepool = false
    }

    private func storeCGMState(_ glucose: [BloodGlucose]) {
        storage.transaction { storage in
            let file = OpenAPS.Monitor.cgmState
            var treatments = storage.retrieve(file, as: [NightscoutTreatment].self) ?? []
            var updated = false

            for x in glucose {
                guard let sessionStartDate = x.sessionStartDate else { continue }

                // Skip if we already have a recent treatment
                if let lastTreatment = treatments.last,
                   let createdAt = lastTreatment.createdAt,
                   abs(createdAt.timeIntervalSince(sessionStartDate)) < TimeInterval(60)
                {
                    continue
                }

                let notes = createCGMStateNotes(transmitterID: x.transmitterID, activationDate: x.activationDate)
                let treatment = createCGMStateTreatment(sessionStartDate: sessionStartDate, notes: notes)

                info(.cgm, "Recorded CGM sensor change at \(sessionStartDate)")
                treatments.append(treatment)
                updated = true
            }

            if updated {
                storage.save(
                    treatments.filter { $0.createdAt?.addingTimeInterval(30.days.timeInterval) ?? .distantPast > Date() },
                    as: file
                )
            }
        }
    }

    private func createCGMStateNotes(transmitterID: String?, activationDate: Date?) -> String {
        var notes = ""
        if let t = transmitterID {
            notes = t
        }
        if let a = activationDate {
            notes = "\(notes) activated on \(a)"
        }
        return notes
    }

    private func createCGMStateTreatment(sessionStartDate: Date, notes: String) -> NightscoutTreatment {
        NightscoutTreatment(
            duration: nil,
            rawDuration: nil,
            rawRate: nil,
            absolute: nil,
            rate: nil,
            eventType: .nsSensorChange,
            createdAt: sessionStartDate,
            enteredBy: NightscoutTreatment.local,
            bolus: nil,
            insulin: nil,
            notes: notes,
            carbs: nil,
            fat: nil,
            protein: nil,
            targetTop: nil,
            targetBottom: nil
        )
    }

    func addManualGlucose(glucose: Int) {
        let context = makeContext()
        context.name = "addManualGlucose"

        context.perform {
            let newItem = GlucoseStored(context: context)
            newItem.id = UUID()
            newItem.date = Date()
            newItem.glucose = Int16(glucose)
            newItem.isManual = true
            newItem.isUploadedToNS = false
            newItem.isUploadedToHealth = false
            newItem.isUploadedToTidepool = false

            do {
                guard context.hasChanges else { return }
                try context.save()

                // Glucose subscribers already listen to the update publisher, so call here to update glucose-related data.
                self.updateSubject.send()
            } catch let error as NSError {
                warning(.storage, "Saving manual glucose failed", error: error)
            }
        }
    }

    func isGlucoseDataFresh(_ glucoseDate: Date?) -> Bool {
        guard let glucoseDate = glucoseDate else { return false }
        return glucoseDate > Date().addingTimeInterval(-6 * 60)
    }

    func syncDate() -> Date {
        let context = makeContext()
        context.name = "syncDate"

        // Optimize fetch request to only get the date
        let fr = NSFetchRequest<NSDictionary>(entityName: "GlucoseStored")
        // Only CGM readings; a manual entry would filter out the next CGM reading
        fr.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate.predicateForOneDayAgo,
            NSPredicate.cgmGlucose
        ])
        fr.propertiesToFetch = ["date"]
        fr.fetchLimit = 1
        fr.resultType = .dictionaryResultType
        fr.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]

        var fetchedDate: Date = .distantPast

        context.performAndWait {
            do {
                if let result = try context.fetch(fr).first,
                   let date = result["date"] as? Date
                {
                    fetchedDate = date
                }
            } catch {
                warning(.storage, "Fetching latest glucose date failed", error: error)
            }
        }

        return fetchedDate
    }

    func lastGlucoseDate() -> Date? {
        let context = makeContext()
        context.name = "lastGlucoseDate"

        let fetchRequest = GlucoseStored.fetchRequest()
        // CGM plugins drop readings older than this, so manual entries must not count
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate.predicateForOneDayAgo,
            NSPredicate.cgmGlucose
        ])
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \GlucoseStored.date, ascending: false)]
        fetchRequest.fetchLimit = 1

        var date: Date?
        context.performAndWait {
            do {
                let results = try context.fetch(fetchRequest)
                date = results.first?.date
            } catch let error as NSError {
                warning(.storage, "Fetching last glucose date failed", error: error)
            }
        }

        return date
    }

    func isGlucoseFresh() -> Bool {
        Date().timeIntervalSince(lastGlucoseDate() ?? .distantPast) <= Config.filterTime
    }

    func filterTooFrequentGlucose(_ glucose: [BloodGlucose], at date: Date) -> [BloodGlucose] {
        var lastDate = date
        var filtered: [BloodGlucose] = []
        let sorted = glucose.sorted { $0.date < $1.date }

        for entry in sorted {
            guard entry.dateString.addingTimeInterval(-Config.filterTime) > lastDate else {
                continue
            }
            filtered.append(entry)
            lastDate = entry.dateString
        }

        return filtered
    }

    func fetchLatestGlucose(context: NSManagedObjectContext) throws -> GlucoseStored? {
        let predicate = NSPredicate.predicateFor20MinAgo
        return (try CoreDataStack.shared.fetchEntities(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: predicate,
            key: "date",
            ascending: false,
            fetchLimit: 1
        ) as? [GlucoseStored] ?? []).first
    }

    /// Fetches recent glucose and converts it into the `BloodGlucose` values the oref algorithm consumes.
    ///
    /// The fetch window is bounded by `fetchHours`: determineBasal feeds `maxMealAbsorptionTime + 0.5h`
    /// (just enough glucose to cover the longest tracked meal absorption plus a small lead-in); Autosens
    /// uses the default 24h because its sensitivity algorithm needs that full window.
    func getGlucoseForAlgorithm(shouldSmoothGlucose: Bool, fetchHours: Decimal) async throws -> [BloodGlucose] {
        try await getGlucoseAlgorithmInput(
            shouldSmoothGlucose: shouldSmoothGlucose, fetchHours: fetchHours, context: observationContext
        ).dosingReadings
    }

    func getGlucoseAlgorithmInput(
        shouldSmoothGlucose: Bool, fetchHours: Decimal, context observation: GlucoseObservationContext?
    ) async throws -> GlucoseAlgorithmInput {
        let context = makeContext()
        // a fixed dense history prevents callers with different horizons from learning twice
        let hours = observation?.cadence.isDense == true ? max(fetchHours, 72) : fetchHours
        let cutoff = Date().addingTimeInterval(-(Double(truncating: hours as NSNumber) * 3600))

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate(format: "date >= %@", cutoff as NSDate),
            key: "date",
            ascending: false,
            batchSize: 48
        )

        return try await context.perform {
            guard let glucoseResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            // extracting handler to only create it 1x
            let roundingBehavior = NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 0,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            )

            return self.processQueue.sync {
                let current = observation.flatMap { self.isCurrent($0) ? $0 : nil }
                if let current, current.cadence.isDense {
                    let rows = Array(glucoseResults.prefix { row in
                        !row.isManual && row.date != nil && row.sourceIdentifier == current.sourceIdentifier &&
                            row.observationEpochID == current.epochID
                    })
                    let raw = rows.map {
                        Self.mapToBloodGlucose($0, shouldSmoothGlucose: false, roundingBehavior: roundingBehavior)
                    }
                    let cadence = GlucoseCadence.detect(raw, trusted: true, enabled: true, now: Date())
                    if cadence.isDense {
                        let values = rows.map {
                            AdaptiveUKFGlucoseValue(
                                timestamp: Int64($0.date!.timeIntervalSince1970 * 1000),
                                value: Double($0.glucose)
                            )
                        }
                        let projection = GlucoseBucketing.denseProjection(values)
                        let adaptive = shouldSmoothGlucose && current.smoothingEnabled
                        let engineInput = values.map { AutoIsfUKFGlucoseValue(timestamp: $0.timestamp, value: $0.value) }
                        let smoothed = adaptive ? self.smoothDense(engineInput, observation: current) : engineInput
                        let denseSmoothed = adaptive ? zip(raw, smoothed).map { reading, value in
                            var result = reading
                            let filtered = value.smoothed.flatMap { $0.isFinite ? $0 : nil } ?? value.value
                            result.sgv = Int(max(filtered, 39).rounded())
                            result.glucose = nil
                            return result
                        } : nil
                        let dosing = projection.map { point in
                            let original = (denseSmoothed ?? raw)[point.sourceIndex]
                            let date = Date(timeIntervalSince1970: Double(point.timestamp) / 1000)
                            return BloodGlucose(
                                id: original.id, sgv: original.sgv, direction: original.direction,
                                date: Decimal(point.timestamp), dateString: date, noise: original.noise,
                                glucose: original.glucose, type: original.type
                            )
                        }
                        return GlucoseAlgorithmInput(
                            dosingReadings: dosing, denseRawReadings: raw, denseSmoothedReadings: denseSmoothed,
                            cadence: cadence, sourceIdentifier: current.sourceIdentifier,
                            observationEpochID: current.epochID, generationID: current.generationID,
                            supportedGridDates: dosing.map(\.dateString)
                        )
                    }
                }
                let hasDenseHistory = zip(glucoseResults, glucoseResults.dropFirst()).contains { newer, older in
                    guard let epoch = newer.observationEpochID, epoch == older.observationEpochID,
                          let newerDate = newer.date, let olderDate = older.date else { return false }
                    return newerDate.timeIntervalSince(olderDate) <= Config.filterTime
                }
                var lastDate: Date?
                // tagged dense history remains stored, but off mode admits it at the legacy cadence
                let admitted = glucoseResults.reversed().filter { row in
                    if hasDenseHistory, row.observationEpochID != nil, let date = row.date, let lastDate,
                       date.timeIntervalSince(lastDate) <= Config.filterTime { return false }
                    if !row.isManual { lastDate = row.date }
                    return true
                }.reversed()
                let legacySmoothed = hasDenseHistory && shouldSmoothGlucose
                    ? self.legacySmoothedReadings(Array(admitted), context: context) : []
                let smoothedByDate = Dictionary(legacySmoothed.compactMap { row -> (Date, NSDecimalNumber)? in
                    guard let date = row.date, let value = row.smoothedGlucose else { return nil }
                    return (date, value)
                }, uniquingKeysWith: { first, _ in first })
                return GlucoseAlgorithmInput(dosingReadings: admitted.map { row in
                    if hasDenseHistory, row.observationEpochID != nil, let date = row.date, let value = smoothedByDate[date] {
                        var reading = Self.mapToBloodGlucose(row, shouldSmoothGlucose: false, roundingBehavior: roundingBehavior)
                        reading.sgv = value.rounding(accordingToBehavior: roundingBehavior).intValue
                        return reading
                    }
                    return
                        Self.mapToBloodGlucose(
                            row, shouldSmoothGlucose: shouldSmoothGlucose && (!hasDenseHistory || row.observationEpochID == nil),
                            roundingBehavior: roundingBehavior
                        )
                })
            }
        }
    }

    /// The glucose value the algorithm consumes for a stored reading: the smoothed value when
    /// smoothing is on and a valid non-zero smoothed CGM value exists, otherwise the raw value
    /// (finger pricks/manual entries always use the raw value — cf.
    /// https://github.com/nightscout/Trio/issues/1054).
    static func algorithmGlucoseValue(
        for glucose: GlucoseStored,
        shouldSmoothGlucose: Bool,
        roundingBehavior: NSDecimalNumberHandler
    ) -> Int16 {
        if shouldSmoothGlucose {
            if !glucose.isManual, let smoothedGlucose = glucose.smoothedGlucose, smoothedGlucose != 0 {
                return smoothedGlucose.rounding(accordingToBehavior: roundingBehavior).int16Value
            } else {
                return glucose.glucose
            }
        } else {
            return glucose.glucose
        }
    }

    /// Maps a `GlucoseStored` to the `BloodGlucose` the algorithm consumes, reproducing exactly
    /// the coercions the old `AlgorithmGlucose` → JSON → `JSONBridge.glucose` round-trip applied:
    /// - CGM readings populate `sgv`, manual readings populate `glucose` (driven by `isManual`).
    /// - `dateString` is the stored reading date. The old path round-tripped it through an ISO8601
    ///   fractional-seconds string, truncating it to millisecond precision; we keep the full-precision
    ///   `Date` instead, since the extra sub-millisecond precision is harmless to the algorithm and
    ///   the JSON representation is unaffected (`dateString` still encodes to 3-digit-ms ISO8601).
    /// - `date` is the unix-millisecond timestamp as a `Decimal`.
    /// - `type` is always "sgv" (matching the old hardcoded encode).
    static func mapToBloodGlucose(
        _ glucose: GlucoseStored,
        shouldSmoothGlucose: Bool,
        roundingBehavior: NSDecimalNumberHandler
    ) -> BloodGlucose {
        let glucoseValue = algorithmGlucoseValue(
            for: glucose,
            shouldSmoothGlucose: shouldSmoothGlucose,
            roundingBehavior: roundingBehavior
        )
        let isManual = glucose.isManual
        // The ?? Date() is problematic, but this is how it worked previously
        // so we'll retain it
        let dateString = glucose.date ?? Date()
        let dateMilliseconds = Decimal(Int64(dateString.timeIntervalSince1970 * 1000))

        return BloodGlucose(
            id: glucose.id?.uuidString ?? UUID().uuidString,
            sgv: isManual ? nil : Int(glucoseValue),
            direction: glucose.direction.flatMap { BloodGlucose.Direction(rawValue: $0) },
            date: dateMilliseconds,
            dateString: dateString,
            glucose: isManual ? Int(glucoseValue) : nil,
            type: "sgv"
        )
    }

    // Fetch glucose that is not uploaded to Nightscout yet
    /// - Returns: Array of BloodGlucose to ensure the correct format for the NS Upload
    func getGlucoseNotYetUploadedToNightscout() async throws -> [BloodGlucose] {
        let context = makeContext()
        context.name = "getGlucoseNotYetUploadedToNightscout"

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.glucoseNotYetUploadedToNightscout,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map { result in
                let dateString = result.date ?? Date()
                let dateMilliseconds = Decimal(dateString.timeIntervalSince1970 * 1000).rounded()
                if result.isManual {
                    return BloodGlucose(
                        id: result.id?.uuidString ?? UUID().uuidString,
                        mbg: Int(result.glucose),
                        date: dateMilliseconds,
                        dateString: dateString,
                        type: "mbg"
                    )
                } else {
                    return BloodGlucose(
                        id: result.id?.uuidString ?? UUID().uuidString,
                        sgv: Int(result.glucose),
                        direction: BloodGlucose.Direction(from: result.direction ?? ""),
                        date: dateMilliseconds,
                        dateString: dateString,
                        unfiltered: Decimal(result.glucose),
                        filtered: Decimal(result.glucose),
                        noise: nil,
                        glucose: Int(result.glucose),
                        type: "sgv"
                    )
                }
            }
        }
    }

    func getCGMStateNotYetUploadedToNightscout() async -> [NightscoutTreatment] {
        async let alreadyUploaded: [NightscoutTreatment] = storage
            .retrieveAsync(OpenAPS.Nightscout.uploadedCGMState, as: [NightscoutTreatment].self) ?? []
        async let allValues: [NightscoutTreatment] = storage
            .retrieveAsync(OpenAPS.Monitor.cgmState, as: [NightscoutTreatment].self) ?? []

        let (alreadyUploadedValues, allValuesSet) = await (alreadyUploaded, allValues)
        return Array(Set(allValuesSet).subtracting(Set(alreadyUploadedValues)))
    }

    // Fetch glucose that is not uploaded to Nightscout yet
    /// - Returns: Array of BloodGlucose to ensure the correct format for the NS Upload
    func getGlucoseNotYetUploadedToHealth() async throws -> [BloodGlucose] {
        let context = makeContext()
        context.name = "getGlucoseNotYetUploadedToHealth"

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.glucoseNotYetUploadedToHealth,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map { result in
                BloodGlucose(
                    id: result.id?.uuidString ?? UUID().uuidString,
                    sgv: Int(result.glucose),
                    direction: BloodGlucose.Direction(from: result.direction ?? ""),
                    date: Decimal(result.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000,
                    dateString: result.date ?? Date(),
                    unfiltered: Decimal(result.glucose),
                    filtered: Decimal(result.glucose),
                    noise: nil,
                    glucose: Int(result.glucose)
                )
            }
        }
    }

    // Fetch manual glucose that is not uploaded to Nightscout yet
    /// - Returns: Array of NightscoutTreatment to ensure the correct format for the NS Upload
    func getManualGlucoseNotYetUploadedToHealth() async throws -> [BloodGlucose] {
        let context = makeContext()
        context.name = "getManualGlucoseNotYetUploadedToHealth"

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.manualGlucoseNotYetUploadedToHealth,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map { result in
                BloodGlucose(
                    id: result.id?.uuidString ?? UUID().uuidString,
                    sgv: Int(result.glucose),
                    direction: BloodGlucose.Direction(from: result.direction ?? ""),
                    date: Decimal(result.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000,
                    dateString: result.date ?? Date(),
                    unfiltered: Decimal(result.glucose),
                    filtered: Decimal(result.glucose),
                    noise: nil,
                    glucose: Int(result.glucose)
                )
            }
        }
    }

    /// CGM-only counterpart of `getGlucoseNotYetUploadedToHealth()`; manual rows are left for the manual fetch.
    func getCGMGlucoseNotYetUploadedToHealth() async throws -> [BloodGlucose] {
        let context = makeContext()
        context.name = "getCGMGlucoseNotYetUploadedToHealth"

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.cgmGlucoseNotYetUploadedToHealth,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map { result in
                BloodGlucose(
                    id: result.id?.uuidString ?? UUID().uuidString,
                    sgv: Int(result.glucose),
                    direction: BloodGlucose.Direction(from: result.direction ?? ""),
                    date: Decimal(result.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000,
                    dateString: result.date ?? Date(),
                    unfiltered: Decimal(result.glucose),
                    filtered: Decimal(result.glucose),
                    noise: nil,
                    glucose: Int(result.glucose)
                )
            }
        }
    }

    // Fetch glucose that is not uploaded to Tidepool yet
    /// - Returns: Array of StoredGlucoseSample to ensure the correct format for Tidepool upload
    func getGlucoseNotYetUploadedToTidepool() async throws -> [StoredGlucoseSample] {
        let context = makeContext()
        context.name = "getGlucoseNotYetUploadedToTidepool"

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.glucoseNotYetUploadedToTidepool,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map { result in
                BloodGlucose(
                    id: result.id?.uuidString ?? UUID().uuidString,
                    sgv: Int(result.glucose),
                    direction: BloodGlucose.Direction(from: result.direction ?? ""),
                    date: Decimal(result.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000,
                    dateString: result.date ?? Date(),
                    unfiltered: Decimal(result.glucose),
                    filtered: Decimal(result.glucose),
                    noise: nil,
                    glucose: Int(result.glucose)
                )
            }
            .map { $0.convertStoredGlucoseSample(isManualGlucose: false) }
        }
    }

    // Fetch manual glucose that is not uploaded to Tidepool yet
    /// - Returns: Array of StoredGlucoseSample to ensure the correct format for the Tidepool upload
    func getManualGlucoseNotYetUploadedToTidepool() async throws -> [StoredGlucoseSample] {
        let context = makeContext()
        context.name = "getManualGlucoseNotYetUploadedToTidepool"

        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.manualGlucoseNotYetUploadedToTidepool,
            key: "date",
            ascending: false
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map { result in
                BloodGlucose(
                    id: result.id?.uuidString ?? UUID().uuidString,
                    sgv: Int(result.glucose),
                    direction: BloodGlucose.Direction(from: result.direction ?? ""),
                    date: Decimal(result.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000,
                    dateString: result.date ?? Date(),
                    unfiltered: Decimal(result.glucose),
                    filtered: Decimal(result.glucose),
                    noise: nil,
                    glucose: Int(result.glucose)
                )
            }.map { $0.convertStoredGlucoseSample(isManualGlucose: true) }
        }
    }

    // FIXME: use this after we know oref-swift is good
//    /// Fetches the most recent glucose readings from Core Data, filters and smooths them,
//    /// and computes rolling delta statistics (last, short-term, and long-term).
//    ///
//    /// Mirrors JavaScript oref `glucose-get-last.js` logic.
//    ///
//    /// - Returns: A `GlucoseStatus` containing:
//    ///   - `glucose`: the most recent glucose value (mg/dL),
//    ///   - `delta`: the 5-minute delta (mg/dL per 5m),
//    ///   - `shortAvgDelta`: the average delta over ~5–15 minutes,
//    ///   - `longAvgDelta`: the average delta over ~20–40 minutes,
//    ///   - `noise`: the CGM noise level (if any),
//    ///   - `date`: the timestamp of the “now” reading,
//    ///   - `lastCalIndex`: index of the last calibration record (always `nil` here),
//    ///   - `device`: the source device string.
//    ///
//    /// - Throws: Any `CoreDataError` or other error encountered during fetch or context work.
//    /// - Returns: `nil` if no valid glucose readings are found in the past day.
//    public func getGlucoseStatus() async throws -> GlucoseStatus? {
//        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
//            ofType: GlucoseStored.self,
//            onContext: context,
//            predicate: NSPredicate(
//                format: "date >= %@ AND isManual == %@",
//                Date.oneDayAgoInMinutes as NSDate,
//                false as NSNumber
//            ),
//            key: "date",
//            ascending: false
//        )
//
//        guard let stored = results as? [GlucoseStored], !stored.isEmpty else {
//            return nil
//        }
//
//        let validReadings: [BloodGlucose] = await context.perform {
//            stored.compactMap { entry in
//                BloodGlucose(
//                    id: entry.id?.uuidString ?? UUID().uuidString,
//                    sgv: Int(entry.glucose),
//                    direction: BloodGlucose.Direction(from: entry.direction ?? ""),
//                    date: Decimal(entry.date?.timeIntervalSince1970 ?? Date().timeIntervalSince1970) * 1000,
//                    dateString: entry.date ?? Date(),
//                    unfiltered: Decimal(entry.glucose),
//                    filtered: Decimal(entry.glucose),
//                    noise: nil,
//                    glucose: Int(entry.glucose),
//                    type: "sgv"
//                )
//            }
//        }
//
//        guard !validReadings.isEmpty else {
//            return nil
//        }
//
//        // Sort descending (newest first)
//        let sorted = validReadings.sorted { $0.date > $1.date }
//
//        let mostRecentGlucose = sorted[0]
//        var mostRecentGlucoseReading: Int = mostRecentGlucose.glucose!
//        var mostRecentGlucoseDate: Date = mostRecentGlucose.dateString
//
//        var lastDeltas: [Decimal] = []
//        var shortDeltas: [Decimal] = []
//        var longDeltas: [Decimal] = []
//
//        // Walk older entries to compute deltas
//        for entry in sorted.dropFirst() {
//            // JS oref has logic here around skipping calibration readings.
//            // We never calibration record (never happens here, since type=="sgv")
//            // so we omit this check
//
//            // only use readings >38 mg/dL (to skip code values, <39)
//            guard let glucose = entry.glucose, glucose > 38 else { continue }
//
//            let minutesAgo = mostRecentGlucoseDate.timeIntervalSince(entry.dateString) / 60
//            guard minutesAgo != 0 else { continue }
//            // compute mg/dL per 5 m as a Decimal:
//            let change = Decimal(mostRecentGlucoseReading - glucose)
//            let avgDelta = (change / Decimal(minutesAgo)) * Decimal(5)
//
//            // very-recent (<2.5 m) smooths "now"
//            if minutesAgo > -2, minutesAgo <= 2.5 {
//                mostRecentGlucoseReading = (mostRecentGlucoseReading + glucose) / 2
//                mostRecentGlucoseDate = Date(
//                    timeIntervalSince1970: (
//                        mostRecentGlucoseDate.timeIntervalSince1970 + entry.dateString
//                            .timeIntervalSince1970
//                    ) / 2
//                )
//            }
//            // short window (~5–15 m)
//            else if minutesAgo > 2.5, minutesAgo <= 17.5 {
//                shortDeltas.append(avgDelta)
//                if minutesAgo < 7.5 {
//                    lastDeltas.append(avgDelta)
//                }
//            }
//            // long window (~20–40 m)
//            else if minutesAgo > 17.5, minutesAgo < 42.5 {
//                longDeltas.append(avgDelta)
//            }
//        }
//
//        // compute means (or zero)
//        let lastDelta: Decimal = lastDeltas.mean
//        let shortAvg: Decimal = shortDeltas.mean
//        let longAvg: Decimal = longDeltas.mean
//
//        return GlucoseStatus(
//            delta: lastDelta.rounded(toPlaces: 2),
//            glucose: Decimal(mostRecentGlucoseReading),
//            noise: Int(sorted[0].noise ?? 0),
//            shortAvgDelta: shortAvg.rounded(toPlaces: 2),
//            longAvgDelta: longAvg.rounded(toPlaces: 2),
//            date: mostRecentGlucoseDate,
//            lastCalIndex: nil,
//            device: settingsManager.settings.cgm.rawValue
//        )
//    }

    func deleteGlucose(_ treatmentObjectID: NSManagedObjectID) async {
        let context = makeContext()
        context.name = "deleteGlucose"
        context.transactionAuthor = "deleteGlucose"

        await context.perform {
            do {
                let result = try context.existingObject(with: treatmentObjectID) as? GlucoseStored

                guard let glucoseToDelete = result else {
                    warning(.storage, "Glucose entry to delete not found")
                    return
                }

                // Create a new DeletedGlucoseStored object and copy the properties
                if let date = glucoseToDelete.date {
                    let deletedEntry = DeletedGlucoseStored(context: context)
                    deletedEntry.date = date
                    deletedEntry.glucose = glucoseToDelete.glucose
                    deletedEntry.isManualGlucoseEntry = glucoseToDelete.isManual
                }

                context.delete(glucoseToDelete)

                guard context.hasChanges else { return }
                try context.save()
                debug(.storage, "Deleted glucose entry")
            } catch {
                warning(.storage, "Deleting glucose entry failed", error: error)
            }
        }
    }

    var alarm: GlucoseAlarm? {
        let context = makeContext()
        context.name = "alarm"

        /// glucose can not be older than 20 minutes due to the predicate in the fetch request
        return context.performAndWait {
            do {
                guard let glucose = try fetchLatestGlucose(context: context) else { return nil }

                let glucoseValue = glucose.glucose

                if Decimal(glucoseValue) <= settingsManager.settings.low {
                    return .low
                }

                if Decimal(glucoseValue) >= settingsManager.settings.high {
                    return .high
                }

                return nil
            } catch {
                warning(.storage, "Fetching latest glucose for alarm failed", error: error)
                return nil
            }
        }
    }
}

protocol GlucoseObserver {
    func glucoseDidUpdate(_ glucose: [BloodGlucose])
}

enum GlucoseAlarm {
    case high
    case low

    var displayName: String {
        switch self {
        case .high:
            return String(localized: "LOWALERT!", comment: "LOWALERT!")
        case .low:
            return String(localized: "HIGHALERT!", comment: "HIGHALERT!")
        }
    }
}
