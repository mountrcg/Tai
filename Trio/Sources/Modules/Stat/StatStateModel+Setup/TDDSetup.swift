import CoreData
import Foundation

/// Represents statistical data about Total Daily Dose for a specific time period
struct TDDStats: Identifiable {
    let id = UUID()
    /// The date representing this time period
    let date: Date
    /// Total insulin in units
    let amount: Double
    /// different moving average of insulin
    let movingAvgWeek: Double
    let movingAvgMonth: Double
    let movingAvgTotal: Double
}

extension Stat.StateModel {
    /// Sets up TDD statistics by fetching and processing insulin data
    func setupTDDStats(selectedInterval: Stat.StateModel.StatsTimeInterval) {
        Task {
            do {
                let (hourly, daily) = try await fetchTDDStats(selectedInterval: selectedInterval)

                await MainActor.run {
                    self.hourlyTDDStats = hourly
                    self.dailyTDDStats = daily
                }

                // Initially calculate and cache daily averages
                await calculateAndCacheTDDAverages()
            } catch {
                debug(.default, "\(DebuggingIdentifiers.failed) failed fetching TDD stats: \(error)")
            }
        }
    }

    /// Fetches and processes Total Daily Dose (TDD) statistics from CoreData
    /// - Returns: A tuple containing hourly and daily TDD statistics arrays
    /// - Note: Processes both hourly statistics for the last 10 days and complete daily statistics
    private func fetchTDDStats(
        selectedInterval: Stat.StateModel
            .StatsTimeInterval
    ) async throws -> (hourly: [TDDStats], daily: [TDDStats]) {
        let tddTaskContext = CoreDataStack.shared.newTaskContext()
        tddTaskContext.name = "StatStateModel.fetchTDDStats"

        // MARK: - Fetch Required Data

        // Fetch data for daily statistics (TDDStored for week, month, total views)
        let tddResults = try await fetchTDDStoredRecords(on: tddTaskContext)

        // Fetch data for hourly statistics (BolusStored and TempBasalStored for day view)
        let (
            bolusResults,
            tempBasalResults,
            suspendEvents,
            resumeEvents
        ) = try await fetchHourlyInsulinRecords(on: tddTaskContext)

        var hourlyStats: [TDDStats] = []
        var dailyStats: [TDDStats] = []

        await tddTaskContext.perform {
            let calendar = Calendar.current

            // Process daily statistics from TDDStored
            if let fetchedTDDs = tddResults as? [TDDStored] {
                dailyStats = self.processDailyTDDs(fetchedTDDs, calendar: calendar, selectedInterval: selectedInterval)
            }

            // Process hourly statistics from BolusStored and TempBasalStored
            if let fetchedBoluses = bolusResults as? [BolusStored],
               let fetchedTempBasals = tempBasalResults as? [TempBasalStored],
               let fetchedSuspendEvents = suspendEvents as? [PumpEventStored],
               let fetchedResumeEvents = resumeEvents as? [PumpEventStored]
            {
                hourlyStats = self.processHourlyInsulinData(
                    boluses: fetchedBoluses,
                    tempBasals: fetchedTempBasals,
                    suspendEvents: fetchedSuspendEvents,
                    resumeEvents: fetchedResumeEvents,
                    calendar: calendar
                )
            }
        }

        return (hourlyStats, dailyStats)
    }

    /// Fetches TDDStored records from CoreData for daily statistics
    /// - Returns: The results of the fetch request containing TDDStored records
    /// - Note: Fetches records from the last 3 months for week, month, and total views
    private func fetchTDDStoredRecords(on tddTaskContext: NSManagedObjectContext) async throws -> Any {
        // Create a predicate to fetch TDD records from the last 3 months
        let threeMonthsAgo = Date().addingTimeInterval(-3.months.timeInterval)
        let predicate = NSPredicate(format: "date >= %@", threeMonthsAgo as NSDate)

        // Fetch TDD records from CoreData
        return try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TDDStored.self,
            onContext: tddTaskContext,
            predicate: predicate,
            key: "date",
            ascending: true,
            batchSize: 100
        )
    }

    /// Fetches BolusStored and TempBasalStored records from CoreData for hourly statistics
    /// - Returns: A tuple containing the results of both fetch requests
    /// - Note: Fetches records from the last 20 days for detailed hourly view
    private func fetchHourlyInsulinRecords(on tddTaskContext: NSManagedObjectContext) async throws
        -> (bolus: Any, tempBasal: Any, suspendEvents: Any, resumeEvents: Any)
    {
        // Calculate date range for hourly statistics (last 20 days)
        let now = Date()
        let twentyDaysAgo = Calendar.current.date(byAdding: .day, value: -20, to: now) ?? now

        // Create a predicate for the date range
        let datePredicate = NSPredicate(
            format: "pumpEvent.timestamp >= %@ AND pumpEvent.timestamp <= %@",
            twentyDaysAgo as NSDate,
            now as NSDate
        )

        // Fetch bolus records for hourly stats
        let bolusResults = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: BolusStored.self,
            onContext: tddTaskContext,
            predicate: datePredicate,
            key: "pumpEvent.timestamp",
            ascending: true,
            batchSize: 100
        )

        // Fetch temp basal records for hourly stats
        let tempBasalResults = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: TempBasalStored.self,
            onContext: tddTaskContext,
            predicate: datePredicate,
            key: "pumpEvent.timestamp",
            ascending: true,
            batchSize: 100
        )

        // Create a combined predicate for suspension and resume events
        let suspendResumeTypes = [
            PumpEventStored.EventType.pumpSuspend.rawValue,
            PumpEventStored.EventType.pumpResume.rawValue
        ]

        let suspendResumePredicate = NSPredicate(
            format: "timestamp >= %@ AND timestamp <= %@ AND type IN %@",
            twentyDaysAgo as NSDate,
            now as NSDate,
            suspendResumeTypes
        )

        // Fetch both suspension and resume events in a single query
        let suspendResumeResults = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: tddTaskContext,
            predicate: suspendResumePredicate,
            key: "timestamp",
            ascending: true,
            batchSize: 100
        )

        // Filter the results within the context's perform closure to ensure thread safety
        let (suspendEvents, resumeEvents) = await tddTaskContext.perform {
            var suspendEventsArray: [PumpEventStored] = []
            var resumeEventsArray: [PumpEventStored] = []

            if let pumpEvents = suspendResumeResults as? [PumpEventStored] {
                for event in pumpEvents {
                    if event.type == PumpEventStored.EventType.pumpSuspend.rawValue {
                        suspendEventsArray.append(event)
                    } else if event.type == PumpEventStored.EventType.pumpResume.rawValue {
                        resumeEventsArray.append(event)
                    }
                }
            }

            return (suspendEventsArray, resumeEventsArray)
        }

        return (bolusResults, tempBasalResults, suspendEvents, resumeEvents)
    }

    /// Processes bolus and temporary basal data to create hourly insulin statistics
    /// - Parameters:
    ///   - boluses: Array of BolusStored objects containing bolus insulin data
    ///   - tempBasals: Array of TempBasalStored objects containing temporary basal rate data
    ///   - suspendEvents: Array of PumpEventStored objects with type pumpSuspend
    ///   - resumeEvents: Array of PumpEventStored objects with type pumpResume
    ///   - calendar: Calendar instance used for date calculations and grouping
    /// - Returns: Array of TDDStats objects representing hourly insulin amounts
    /// - Note: This method calculates the actual duration of temporary basal rates by using the time
    ///         difference between consecutive events, rather than relying on the planned duration.
    ///         It also properly distributes insulin amounts across hour boundaries for accurate hourly statistics.
    ///         Suspension events are taken into account to prevent counting insulin during pump suspensions.
    private func processHourlyInsulinData(
        boluses: [BolusStored],
        tempBasals: [TempBasalStored],
        suspendEvents: [PumpEventStored],
        resumeEvents: [PumpEventStored],
        calendar: Calendar
    ) -> [TDDStats] {
        // Dictionary to store insulin amounts indexed by hour
        var insulinByHour: [Date: Double] = [:]

        // MARK: - Process Bolus Insulin

        // Iterate through all bolus records and add their amounts to the appropriate hourly totals
        for bolus in boluses {
            guard let timestamp = bolus.pumpEvent?.timestamp,
                  let amount = bolus.amount?.doubleValue
            else {
                continue // Skip entries with missing timestamp or amount
            }

            // Create a date representing the hour of this bolus (truncating minutes/seconds)
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: timestamp)
            guard let hourDate = calendar.date(from: components) else { continue }

            // Add this bolus amount to the running total for this hour
            insulinByHour[hourDate, default: 0] += amount
        }

        // MARK: - Create Suspend-Resume Pairs

        // Create pairs of suspend and resume events
        let suspendResumePairs = createSuspendResumePairs(suspendEvents: suspendEvents, resumeEvents: resumeEvents)

        // MARK: - Process Temporary Basal Insulin

        // Sort temp basals chronologically for accurate duration calculation
        let sortedTempBasals = tempBasals.sorted {
            ($0.pumpEvent?.timestamp ?? Date.distantPast) < ($1.pumpEvent?.timestamp ?? Date.distantPast)
        }

        // Process each temporary basal event
        for (index, tempBasal) in sortedTempBasals.enumerated() {
            guard let timestamp = tempBasal.pumpEvent?.timestamp,
                  let rate = tempBasal.rate?.doubleValue
            else {
                continue // Skip entries with missing timestamp or rate
            }

            // MARK: Calculate Actual Duration

            // Determine the actual duration based on the time until the next temp basal event
            var actualDurationInMinutes: Double

            if index < sortedTempBasals.count - 1 {
                // For all but the last event, calculate duration as time until next event
                if let nextTimestamp = sortedTempBasals[index + 1].pumpEvent?.timestamp {
                    // Calculate time difference in minutes between this event and the next
                    actualDurationInMinutes = nextTimestamp.timeIntervalSince(timestamp) / 60.0
                } else {
                    // Fallback to planned duration if next timestamp is missing (unlikely)
                    actualDurationInMinutes = Double(tempBasal.duration)
                }
            } else {
                // For the last event, use the planned duration as there's no next event
                actualDurationInMinutes = Double(tempBasal.duration)
            }

            // Convert duration from minutes to hours for insulin calculation
            let durationInHours = actualDurationInMinutes / 60.0

            // A finalized row reports what the pump actually delivered (suspensions and
            // pulse quantization included), so spread that total over the unsuspended
            // time; the bars then sum to it instead of to rate x duration.
            let unsuspendedHours = calculateEffectiveDuration(
                from: timestamp,
                to: timestamp.addingTimeInterval(durationInHours * 3600),
                suspendResumePairs: suspendResumePairs
            )
            var effectiveRate = rate
            if let delivered = tempBasal.deliveredUnits?.doubleValue, unsuspendedHours > 0 {
                effectiveRate = delivered / unsuspendedHours
            }

            // MARK: Distribute Insulin Across Hours

            // Handle temp basals that span multiple hours by distributing insulin appropriately
            // taking into account suspension periods
            distributeInsulinAcrossHours(
                startTime: timestamp,
                durationInHours: durationInHours,
                rate: effectiveRate,
                suspendResumePairs: suspendResumePairs,
                insulinByHour: &insulinByHour,
                calendar: calendar
            )
        }

        // MARK: - Convert Results to TDDStats Array

        // Transform the dictionary into a sorted array of TDDStats objects
        return insulinByHour.keys.sorted().map { hourDate in
            TDDStats(
                date: hourDate,
                amount: insulinByHour[hourDate, default: 0],
                movingAvgWeek: 0,
                movingAvgMonth: 0,
                movingAvgTotal: 0
            )
        }
    }

    /// Creates pairs of suspend and resume events
    /// - Parameters:
    ///   - suspendEvents: Array of PumpEventStored objects with type pumpSuspend
    ///   - resumeEvents: Array of PumpEventStored objects with type pumpResume
    /// - Returns: Array of tuples containing suspend and resume event pairs
    /// - Note: This method pairs suspend events with the next resume event chronologically
    private func createSuspendResumePairs(
        suspendEvents: [PumpEventStored],
        resumeEvents: [PumpEventStored]
    ) -> [(suspend: PumpEventStored, resume: PumpEventStored)] {
        // Sort events chronologically
        let sortedSuspendEvents = suspendEvents.sorted { ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) }
        let sortedResumeEvents = resumeEvents.sorted { ($0.timestamp ?? Date.distantPast) < ($1.timestamp ?? Date.distantPast) }

        // Create pairs of suspend + resume events
        var pairs: [(suspend: PumpEventStored, resume: PumpEventStored)] = []

        // Iterate through suspend events and find matching resume events
        for suspendEvent in sortedSuspendEvents {
            guard let suspendTime = suspendEvent.timestamp else { continue }

            // Find the first resume event that occurs after this suspend event
            if let resumeEvent = sortedResumeEvents.first(where: {
                guard let resumeTime = $0.timestamp else { return false }
                return resumeTime > suspendTime
            }) {
                // Create a pair and add it to the array
                pairs.append((suspend: suspendEvent, resume: resumeEvent))
            }
        }

        return pairs
    }

    /// Distributes insulin from a temporary basal rate across multiple hours
    /// - Parameters:
    ///   - startTime: The start time of the temporary basal rate
    ///   - durationInHours: The duration of the temporary basal rate in hours
    ///   - rate: The insulin rate in units per hour (U/h)
    ///   - suspendResumePairs: Array of suspend-resume event pairs to account for suspension periods
    ///   - insulinByHour: Dictionary to store insulin amounts by hour (modified in-place)
    ///   - calendar: Calendar instance used for date calculations
    /// - Note: This method handles the case where a temporary basal spans multiple hours by
    ///         calculating the exact amount of insulin delivered in each hour. It accounts for
    ///         partial hours at the beginning and end of the temporary basal period, as well as
    ///         suspension periods where no insulin is delivered.
    private func distributeInsulinAcrossHours(
        startTime: Date,
        durationInHours: Double,
        rate: Double,
        suspendResumePairs: [(suspend: PumpEventStored, resume: PumpEventStored)],
        insulinByHour: inout [Date: Double],
        calendar: Calendar
    ) {
        // Extract time components to calculate partial hours
        let startComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: startTime)

        // Create a date representing just the hour of the start time (truncating minutes/seconds)
        guard let startHourDate = calendar
            .date(from: Calendar.current.dateComponents([.year, .month, .day, .hour], from: startTime))
        else {
            return // Exit if we can't create a valid hour date
        }

        // Calculate end time of the temp basal
        let endTime = startTime.addingTimeInterval(durationInHours * 3600)

        // MARK: - Handle First Hour (Partial)

        // Calculate how many minutes remain in the first hour after the start time
        let minutesInFirstHour = 60.0 - Double(startComponents.minute ?? 0) - (Double(startComponents.second ?? 0) / 60.0)

        // Calculate how many hours of the temp basal occur in the first hour (capped at remaining time)
        let hoursInFirstHour = min(durationInHours, minutesInFirstHour / 60.0)

        // Add insulin for the first partial hour, accounting for any suspensions
        if hoursInFirstHour > 0 {
            // Calculate the end time of the first hour segment
            let firstHourEndTime = startTime.addingTimeInterval(hoursInFirstHour * 3600)

            // Calculate effective duration excluding suspension periods
            let effectiveDuration = calculateEffectiveDuration(
                from: startTime,
                to: firstHourEndTime,
                suspendResumePairs: suspendResumePairs
            )

            // Insulin = rate (U/h) * effective duration (h)
            insulinByHour[startHourDate, default: 0] += rate * effectiveDuration
        }

        // MARK: - Handle Subsequent Hours

        // Calculate remaining duration after the first hour
        var remainingDuration = durationInHours - hoursInFirstHour

        // Start with the next hour
        var currentHourDate = calendar.date(byAdding: .hour, value: 1, to: startHourDate) ?? startHourDate

        // Distribute remaining insulin across subsequent hours
        while remainingDuration > 0 {
            // Calculate how much of this hour is covered (max 1 hour)
            let hoursToAdd = min(remainingDuration, 1.0)

            // Calculate the start and end times for this hour segment
            let hourStartTime = calendar
                .date(from: calendar.dateComponents([.year, .month, .day, .hour], from: currentHourDate)) ?? currentHourDate
            let hourEndTime = hourStartTime.addingTimeInterval(hoursToAdd * 3600)

            // Calculate effective duration excluding suspension periods
            let effectiveDuration = calculateEffectiveDuration(
                from: hourStartTime,
                to: hourEndTime,
                suspendResumePairs: suspendResumePairs
            )

            // Add insulin for this hour: rate (U/h) * effective duration (h)
            insulinByHour[currentHourDate, default: 0] += rate * effectiveDuration

            // Reduce remaining duration and move to next hour
            remainingDuration -= hoursToAdd
            currentHourDate = calendar.date(byAdding: .hour, value: 1, to: currentHourDate) ?? currentHourDate
        }
    }

    /// Calculates the effective duration of insulin delivery, excluding suspension periods
    /// - Parameters:
    ///   - startTime: The start time of the period
    ///   - endTime: The end time of the period
    ///   - suspendResumePairs: Array of suspend-resume event pairs
    /// - Returns: The effective duration in hours, excluding suspension periods
    /// - Note: This method calculates how much of a time period was not affected by pump suspensions
    private func calculateEffectiveDuration(
        from startTime: Date,
        to endTime: Date,
        suspendResumePairs: [(suspend: PumpEventStored, resume: PumpEventStored)]
    ) -> Double {
        // Total duration in hours
        let totalDuration = endTime.timeIntervalSince(startTime) / 3600.0

        // Calculate total suspended time within this period
        var suspendedDuration = 0.0

        for pair in suspendResumePairs {
            guard let suspendTime = pair.suspend.timestamp,
                  let resumeTime = pair.resume.timestamp
            else {
                continue
            }

            // Check if this suspension overlaps with our period
            if suspendTime < endTime, resumeTime > startTime {
                // Calculate overlap start and end
                let overlapStart = max(startTime, suspendTime)
                let overlapEnd = min(endTime, resumeTime)

                // Add the overlapping duration to our suspended time
                suspendedDuration += overlapEnd.timeIntervalSince(overlapStart) / 3600.0
            }
        }

        // Return effective duration (total minus suspended)
        return max(0.0, totalDuration - suspendedDuration)
    }

    /// Processes TDDStored records to create daily Total Daily Dose statistics
    /// - Parameters:
    ///   - tdds: Array of TDDStored objects containing daily insulin data
    ///   - calendar: Calendar instance used for date calculations and grouping
    /// - Returns: Array of TDDStats objects representing daily insulin amounts
    /// - Note: This method groups TDD records by day and uses only the last (most recent) entry
    ///         for each day, as this represents the complete TDD value for that day. This approach
    ///         is appropriate for week, month, and total views where we want the final daily totals.
    private func processDailyTDDs(
        _ tdds: [TDDStored],
        calendar: Calendar,
        selectedInterval _: Stat.StateModel.StatsTimeInterval
    ) -> [TDDStats] {
        // MARK: - Group TDDs by Calendar Day

        // Create a dictionary where keys are start-of-day dates and values are arrays of TDD entries for that day
        let dailyGrouped = Dictionary(grouping: tdds) { tdd in
            guard let timestamp = tdd.date else { return Date() }
            return calendar.startOfDay(for: timestamp) // Grouping by start of day
        }

        // MARK: - Select Most Recent Entry Per Day

        // Dictionary to store daily total values
        var dailyTotals: [Date: Double] = [:]

        for (dayDate, entries) in dailyGrouped {
            // Sort entries chronologically and take the last one (most recent)
            let sortedEntries = entries.sorted { ($0.date ?? Date.distantPast) < ($1.date ?? Date.distantPast) }

            if let lastEntry = sortedEntries.last, let total = lastEntry.total?.doubleValue {
                dailyTotals[dayDate] = total
            } else {
                dailyTotals[dayDate] = 0.0 // Default to zero if no valid entry
            }
        }

        // MARK: - Compute Moving Averages

        // Create an ordered list of sorted days (from oldest to newest)
        let sortedDays = dailyTotals.keys.sorted()

        var stats: [TDDStats] = []

        for dayDate in sortedDays {
            let amount = dailyTotals[dayDate, default: 0.0]

            let movingAvgWeek = calculateMovingAverage(
                for: dayDate, selectedInterval: .week, sortedDays: sortedDays, dailyTotals: dailyTotals
            )
            let movingAvgMonth = calculateMovingAverage(
                for: dayDate, selectedInterval: .month, sortedDays: sortedDays, dailyTotals: dailyTotals
            )
            let movingAvgTotal = calculateMovingAverage(
                for: dayDate, selectedInterval: .total, sortedDays: sortedDays, dailyTotals: dailyTotals
            )

            stats.append(
                TDDStats(
                    date: dayDate,
                    amount: amount,
                    movingAvgWeek: movingAvgWeek,
                    movingAvgMonth: movingAvgMonth,
                    movingAvgTotal: movingAvgTotal
                )
            )
        }

        return stats
    }

    /// Calculates and caches the daily averages of Total Daily Dose (TDD) insulin values
    /// - Note: This function runs asynchronously and updates the tddAveragesCache on the main actor
    private func calculateAndCacheTDDAverages() async {
        let tddTaskContext = CoreDataStack.shared.newTaskContext()
        tddTaskContext.name = "StatStateModel.calculateAndCacheTDDAverages"

        // Get calendar for date calculations
        let calendar = Calendar.current

        // Calculate daily averages on background context
        let dailyAverages = await tddTaskContext.perform { [dailyTDDStats] in
            // Group TDD stats by calendar day
            let groupedByDay = Dictionary(grouping: dailyTDDStats) { stat in
                calendar.startOfDay(for: stat.date)
            }

            // Calculate average TDD for each day
            var averages: [Date: Double] = [:]
            for (day, stats) in groupedByDay {
                // Sum up all TDD values for the day
                let total = stats.reduce(0.0) { $0 + $1.amount }
                let count = Double(stats.count)
                // Store average in dictionary
                averages[day] = total / count
            }
            return averages
        }

        // Update cache on main actor
        await MainActor.run {
            self.tddAveragesCache = dailyAverages
        }
    }

    /// Gets the cached average Total Daily Dose (TDD) of insulin for a specified date range
    /// - Parameter range: A tuple containing the start and end dates to get averages for
    /// - Returns: The average TDD in units for the specified date range
    func getCachedTDDAverages(for range: (start: Date, end: Date)) -> Double {
        // Calculate and return the TDD averages for the given date range using cached values
        calculateTDDAveragesForDateRange(from: range.start, to: range.end)
    }

    /// Calculates the average Total Daily Dose (TDD) of insulin for a specified date range
    /// - Parameters:
    ///   - startDate: The start date of the range to calculate averages for
    ///   - endDate: The end date of the range to calculate averages for
    /// - Returns: The average TDD in units for the specified date range. Returns 0.0 if no data exists.
    private func calculateTDDAveragesForDateRange(from startDate: Date, to endDate: Date) -> Double {
        // Filter cached TDD values to only include those within the date range
        // Use the same day boundary logic as the chart
        let calendar = Calendar.current
        let alignedStartDate = calendar.startOfDay(for: startDate)
        let alignedEndDate = calendar.startOfDay(for: endDate)

        let relevantStats = tddAveragesCache.filter { date, _ in
            date >= alignedStartDate && date <= alignedEndDate
        }

        // Return 0 if no data exists for the specified range
        guard !relevantStats.isEmpty else { return 0.0 }

        // Calculate total TDD by summing all values
        let total = relevantStats.values.reduce(0.0, +)
        // Convert count to Double for floating point division
        let count = Double(relevantStats.count)

        // Return average TDD
        return total / count
    }

    /// Calculates the moving average for a given date over a specified number of days.
    /// - Parameters:
    ///   - date: The date for which to calculate the moving average.
    ///   - days: Number of days to include in the average (including the current day).
    ///   - sortedDays: Ordered list of available dates.
    ///   - dailyTotals: Dictionary of daily insulin totals.
    /// - Returns: The calculated moving average, or the previous day's moving average if the current day's TDD is 0.
    private func calculateMovingAverage(
        for date: Date,
        selectedInterval: StatsTimeInterval,
        sortedDays: [Date],
        dailyTotals: [Date: Double]
    ) -> Double {
        let windowSize = Stat.StateModel.windowSizeAverages(for: selectedInterval)

        guard let index = sortedDays.firstIndex(of: date) else { return 0.0 }

        let startIndex = max(0, index - (windowSize - 1))
        let validValues = sortedDays[startIndex ... index]
            .compactMap { dailyTotals[$0] }
            .filter { $0 > 0 } // Ensure we skip zero values

        return validValues.isEmpty ? 0.0 : validValues.reduce(0.0, +) / Double(validValues.count)
    }

    /// Determines the window size for moving averages based on the selected interval.
    static func windowSizeAverages(for selectedInterval: StatsTimeInterval) -> Int {
        switch selectedInterval {
        case .day:
            return 1
        case .week:
            return 3
        case .month:
            return 7
        case .total:
            return 21
        }
    }}
