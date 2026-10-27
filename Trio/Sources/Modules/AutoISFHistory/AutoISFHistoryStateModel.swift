import Combine
import CoreData
import SwiftUI

extension Decimal {
    func rounded(to scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .plain)
        return result
    }
}

extension AutoISFHistory {
    @Observable final class StateModel: BaseStateModel<Provider> {
        var selectedEndTime = Date() { didSet { Task { await createEntries() }}}
        var selectedTimeIntervalIndex = 1 { didSet { Task { await createEntries() }}} // Default to 2 hours
        var units: GlucoseUnits = .mgdL
        var autoISFEntries: [AutoISFHistoryEntry] = []
        var timeIntervalOptions = [1, 2, 4, 8] // Hours
        var isPopupPresented: Bool = false
        var iobThresholdPercent: Decimal = 1
        var maxIOB: Decimal = 9

        override func subscribe() {
            units = settingsManager.settings.units
            iobThresholdPercent = settingsManager.preferences.iobThresholdPercent
            maxIOB = settingsManager.preferences.maxIOB

            Task { await createEntries() }
        }

        private func fetchedAutoISF() async throws -> [AutoISFHistoryEntry] {
            let endTime = selectedEndTime
            let intervalHours = timeIntervalOptions[selectedTimeIntervalIndex]
            let startTime = Calendar.current.date(byAdding: .hour, value: -intervalHours, to: endTime)!

            // Per-call context: task contexts no longer auto-merge parent changes, so a
            // long-lived context would serve stale determinations on repeated fetches.
            let context = CoreDataStack.shared.newTaskContext()
            context.name = "fetchedAutoISF"

            do {
                let results = try await CoreDataStack.shared.fetchEntitiesAsync(
                    ofType: OrefDetermination.self,
                    onContext: context,
                    predicate: NSPredicate.determinationPeriod(from: startTime, to: endTime),
                    key: "deliverAt",
                    ascending: false
                )

                return try await context.perform {
                    guard let fetchedResults = results as? [OrefDetermination] else {
                        throw CoreDataError.fetchError(function: #function, file: #file)
                    }
                    return fetchedResults.compactMap { determination in
                        AutoISFHistoryEntry(
                            smb: determination.smbToDeliver as? Decimal,
                            insulin_req: determination.insulinReq as? Decimal,
                            sensitivity_ratio: determination.sensitivityRatio as? Decimal,
                            tbr: determination.rate as? Decimal,
                            timestamp: determination.deliverAt,
                            bg: determination.glucose as? Decimal,
                            isf: determination.insulinSensitivity as? Decimal,
                            smb_ratio: determination.smbRatio as? Decimal,
                            dura_ratio: determination.duraISFratio as? Decimal,
                            bg_ratio: determination.bgISFratio as? Decimal,
                            pp_ratio: determination.ppISFratio as? Decimal,
                            acce_ratio: determination.acceISFratio as? Decimal,
                            autoISF_ratio: determination.autoISFratio as? Decimal,
                            iob_TH: determination.iobTH as? Decimal,
                            iob: (determination.iob as? Decimal)?.rounded(to: 2),
                            parabola_fit_minutes: determination.parabolaFitMinutes as? Decimal,
                            parabola_fit_last_delta: determination.parabolaFitLastDelta as? Decimal,
                            parabola_fit_next_delta: determination.parabolaFitNextDelta as? Decimal,
                            parabola_fit_correlation: determination.parabolaFitCorrelation as? Decimal,
                            parabola_fit_a0: determination.parabolaFitA0 as? Decimal,
                            parabola_fit_a1: determination.parabolaFitA1 as? Decimal,
                            parabola_fit_a2: determination.parabolaFitA2 as? Decimal,
                            dura_min: determination.duraMin as? Decimal,
                            dura_avg: determination.duraAvg as? Decimal,
                            bg_acce: determination.bgAcce as? Decimal
                        )
                    }
                }
            } catch {
                warning(.storage, "Fetching autoISF records failed", error: error)
                return []
            }
        }

        @MainActor func createEntries() async {
            do {
                autoISFEntries = try await fetchedAutoISF()
            } catch {
                warning(.storage, "Loading autoISF history failed", error: error)
                autoISFEntries = []
            }
        }
    }
}
