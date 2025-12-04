import Observation
import SwiftUI

extension BasalProfileEditor {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() private var nightscout: NightscoutManager!
        @ObservationIgnored @Injected() private var broadcaster: Broadcaster!

        var syncInProgress: Bool = false
        var initialItems: [Item] = []
        var items: [Item] = []
        var therapyItems: [TherapySettingItem] = []
        var total: Decimal = 0.0
        var showAlert: Bool = false
        var chartData: [BasalProfile]? = []
        var concentration: Decimal = 1
        var basalIncrement: Decimal = 0.05
        var pumpIncrement: Decimal = 0.05

        let timeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

        private(set) var rateValues: [Decimal] = []

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeValues.count - 1
        }

        var hasChanges: Bool {
            initialItems != items
        }

        var settings: TrioSettings {
            get { settingsManager.settings }
            set { settingsManager.settings = newValue }
        }

        var preferences: Preferences {
            get { settingsManager.preferences }
            set { settingsManager.preferences = newValue }
        }

        var roundingHint: Bool = false
        var roundedRateIndices: Set<Int> = []
        var originalRates: [Int: Decimal] = [:]

        // Convert items to TherapySettingItem format
        func getTherapyItems() -> [TherapySettingItem] {
            items.map { item in
                TherapySettingItem(
                    time: timeValues[item.timeIndex],
                    value: rateValues[item.rateIndex]
                )
            }
        }

        // Update items from TherapySettingItem format
        func updateFromTherapyItems(_ therapyItems: [TherapySettingItem]) {
            items = therapyItems.map { therapyItem in
                let timeIndex = timeValues.firstIndex(where: { abs($0 - therapyItem.time) < 1 }) ?? 0
                let rateIndex = rateValues.firstIndex(of: therapyItem.value) ?? 0
                return Item(rateIndex: rateIndex, timeIndex: timeIndex)
            }
        }

        override func subscribe() {
            // Previous concentration and increment for comparison
            let previousConcentration = concentration
            let previousBasalIncrement = basalIncrement

            // Get concentration factor from settings
            concentration = settings.insulinConcentration
            basalIncrement = preferences.bolusIncrement
            pumpIncrement = basalIncrement / concentration

            if let supportedRates = provider.supportedBasalRates {
                // If provider has defined rates, adjust them by concentration
                rateValues = supportedRates.map { $0 * concentration }
            } else {
                // Default fallback with concentration adjustment
                let minRate: Decimal = 5.0
                let maxRate: Decimal = 1001.0
                let stepSize: Decimal = 5.0

                // Calculate adjusted rates
                var rates: [Decimal] = []
                var current = minRate * concentration
                let adjustedMax = maxRate * concentration
                let adjustedStep = stepSize * concentration

                while current < adjustedMax {
                    rates.append(current / 100)
                    current += adjustedStep
                }

                rateValues = rates
            }

            // Sort rates to ensure they're in ascending order
            let sortedRates = rateValues.sorted()

            // Track if the profile has been modified due to rounding
            var profileModified = false
            roundingHint = false
            roundedRateIndices.removeAll()
            originalRates.removeAll()

            // Check if concentration or basal increment has increased
            let concentrationIncreased = concentration > previousConcentration
            let basalIncrementIncreased = basalIncrement > previousBasalIncrement

            // Map the previous profile, preserving original order and rounding rates
            items = provider.profile.enumerated().map { index, value in
                let timeIndex = timeValues.firstIndex(of: Double(value.minutes * 60)) ?? 0

                // Find the nearest available rate that is less than or equal to the original rate
                let rateIndex = sortedRates.lastIndex(where: { $0 <= value.rate }) ?? 0

                // Check if the rounded rate is different from the original rate
                let originalRate = value.rate
                let roundedRate = sortedRates[rateIndex]

                // Use a percentage-based difference to detect meaningful rounding
                let rateDifference = abs(originalRate - roundedRate)
                let relativeDifference = rateDifference / max(abs(originalRate), 0.001)

                if relativeDifference > 0.001 { // 0.1% relative difference
                    profileModified = true

                    // Always set rounding hint and indices when rates are different
                    roundingHint = true
                    roundedRateIndices.insert(index)
                    originalRates[index] = originalRate
                }

                return Item(rateIndex: rateIndex, timeIndex: timeIndex)
            }
            initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }

            // If profile was modified due to rounding, force hasChanges to be true
            if profileModified {
                // Artificially modify initialItems to trigger hasChanges
                initialItems = initialItems.map {
                    var modifiedItem = $0
                    modifiedItem.rateIndex = (modifiedItem.rateIndex + 1) % rateValues.count
                    return modifiedItem
                }
            }

            calcTotal()
        }

        func calcTotal() {
            let profile = items.map { item -> BasalProfileEntry in
                let fotmatter = DateFormatter()
                fotmatter.timeZone = TimeZone(secondsFromGMT: 0)
                fotmatter.dateFormat = "HH:mm:ss"
                let date = Date(timeIntervalSince1970: self.timeValues[item.timeIndex])
                let minutes = Int(date.timeIntervalSince1970 / 60)
                let rate = self.rateValues[item.rateIndex]
                return BasalProfileEntry(start: fotmatter.string(from: date), minutes: minutes, rate: rate)
            }

            var profileWith24hours = profile.map(\.minutes)
            profileWith24hours.append(24 * 60)
            let pr2 = zip(profile, profileWith24hours.dropFirst())
            total = pr2.reduce(0) { $0 + (Decimal($1.1 - $1.0.minutes) / 60) * $1.0.rate }
        }

        func add() {
            var time = 0
            var rate = 0
            if let last = items.last {
                time = last.timeIndex + 1
                rate = last.rateIndex
            }

            let newItem = Item(rateIndex: rate, timeIndex: time)

            items.append(newItem)
            calcTotal()
        }

        func save() {
            guard hasChanges else { return }

            syncInProgress = true
            let profile = items.map { item -> BasalProfileEntry in
                let formatter = DateFormatter()
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "HH:mm:ss"
                let date = Date(timeIntervalSince1970: self.timeValues[item.timeIndex])
                let minutes = Int(date.timeIntervalSince1970 / 60)
                let rate = self.rateValues[item.rateIndex]
                return BasalProfileEntry(start: formatter.string(from: date), minutes: minutes, rate: rate)
            }
            provider.saveProfile(profile)
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    self.syncInProgress = false
                    switch completion {
                    case .finished:
                        // Reset all modification-related flags
                        self.roundedRateIndices.removeAll()
                        self.roundingHint = false
                        self.originalRates.removeAll()

                        // Update initial items to current items
                        self.initialItems = self.items.map {
                            Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex)
                        }

                        // Recalculate chart data to reset overwritten status
                        Task { @MainActor in
                            self.calculateChartData()
                        }

                        DispatchQueue.main.async {
                            self.broadcaster.notify(BasalProfileObserver.self, on: .main) {
                                $0.basalProfileDidChange(profile)
                            }
                        }

                        Task.detached(priority: .low) {
                            do {
                                debug(.nightscout, "Attempting to upload basal rates to Nightscout")
                                try await self.nightscout.uploadProfiles()
                            } catch {
                                debug(.default, "Failed to upload basal rates to Nightscout: \(error)")
                            }
                        }
                    case .failure:
                        // Handle the error, show error message
                        self.showAlert = true
                    }
                } receiveValue: {
                    // Handle any successful value if needed
                    print("We were successful")
                }
                .store(in: &lifetime)
        }

        @MainActor func validate() {
            let uniq = Array(Set(items))
            let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
            sorted.first?.timeIndex = 0
            if items != sorted {
                items = sorted
            }
            calcTotal()
        }

        func availableTimeIndices(_ itemIndex: Int) -> [Int] {
            // avoid index out of range issues
            guard itemIndex >= 0, itemIndex < items.count else {
                return []
            }

            let usedIndicesByOtherItems = items
                .enumerated()
                .filter { $0.offset != itemIndex }
                .map(\.element.timeIndex)

            return (0 ..< timeValues.count).filter { !usedIndicesByOtherItems.contains($0) }
        }

        @MainActor func calculateChartData() {
            var basals: [BasalProfile] = []
            let tzOffset = TimeZone.current.secondsFromGMT() * -1

            basals.append(contentsOf: items.enumerated().map { chartIndex, item in
                let startDate = Date(timeIntervalSinceReferenceDate: self.timeValues[item.timeIndex])
                var endDate = Date(timeIntervalSinceReferenceDate: self.timeValues.last!).addingTimeInterval(30 * 60)
                if self.items.count > chartIndex + 1 {
                    let nextItem = self.items[chartIndex + 1]
                    endDate = Date(timeIntervalSinceReferenceDate: self.timeValues[nextItem.timeIndex])
                }

                // Find the corresponding original profile index
                let originalProfileIndex = provider.profile.enumerated().first { _, originalEntry in
                    let originalTimeIndex = timeValues.firstIndex(of: Double(originalEntry.minutes * 60)) ?? -1
                    return originalTimeIndex == item.timeIndex
                }?.offset

                // Check if this rate was rounded
                let isRounded = originalProfileIndex.flatMap { roundedRateIndices.contains($0) } ?? false

                return BasalProfile(
                    amount: Double(self.rateValues[item.rateIndex]),
                    isOverwritten: isRounded,
                    startDate: startDate.addingTimeInterval(TimeInterval(tzOffset)),
                    endDate: endDate.addingTimeInterval(TimeInterval(tzOffset))
                )
            })
            basals.sort(by: { $0.startDate > $1.startDate })

            chartData = basals
        }
    }
}
