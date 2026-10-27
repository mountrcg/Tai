import SwiftUI

extension CarbRatioEditor {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var nightscout: NightscoutManager!
        @Injected() private var tidepoolManager: TidepoolManager!
        @Injected() private var broadcaster: Broadcaster!
        @Published var items: [Item] = []
        @Published var initialItems: [Item] = []
        @Published var therapyItems: [TherapySettingItem] = []
        @Published var shouldDisplaySaving: Bool = false

        let timeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

        let rateValues = stride(from: 10.0, to: 501.0, by: 1.0).map { ($0.decimal ?? .zero) / 10 }

        var units: GlucoseUnits {
            settingsManager.settings.units
        }

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeValues.count - 1
        }

        var hasChanges: Bool {
            if initialItems.count != items.count {
                return true
            }

            for (initialItem, currentItem) in zip(initialItems, items) {
                if initialItem.rateIndex != currentItem.rateIndex || initialItem.timeIndex != currentItem.timeIndex {
                    return true
                }
            }

            return false
        }

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
            items = provider.profile.schedule.map { value in
                let timeIndex = timeValues.firstIndex(of: Double(value.offset * 60)) ?? 0
                let rateIndex = rateValues.firstIndex(of: value.ratio) ?? 0
                return Item(rateIndex: rateIndex, timeIndex: timeIndex)
            }

            initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }
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
        }

        func save() {
            guard hasChanges else { return }
            shouldDisplaySaving = true

            let schedule = items.enumerated().map { _, item -> CarbRatioEntry in
                let fotmatter = DateFormatter()
                fotmatter.timeZone = TimeZone(secondsFromGMT: 0)
                fotmatter.dateFormat = "HH:mm:ss"
                let date = Date(timeIntervalSince1970: self.timeValues[item.timeIndex])
                let minutes = Int(date.timeIntervalSince1970 / 60)
                let rate = self.rateValues[item.rateIndex]
                return CarbRatioEntry(start: fotmatter.string(from: date), offset: minutes, ratio: rate)
            }
            let profile = CarbRatios(units: .grams, schedule: schedule)
            provider.saveProfile(profile)
            info(.settings, "Carb ratio schedule saved with \(schedule.count) entries")
            initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }

            DispatchQueue.main.async {
                self.broadcaster.notify(CarbRatiosObserver.self, on: .main) {
                    $0.carbRatiosDidChange(profile)
                }
            }

            Task.detached(priority: .low) {
                do {
                    try await self.nightscout.uploadProfiles()
                } catch {
                    warning(.nightscout, "Uploading profile after carb ratio change failed", error: error)
                }
            }

            Task.detached(priority: .low) {
                await self.tidepoolManager.uploadSettings()
            }
        }

        func validate() {
            DispatchQueue.main.async {
                let uniq = Array(Set(self.items))
                let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
                sorted.first?.timeIndex = 0
                if self.items != sorted {
                    self.items = sorted
                }
            }
        }

        /// Calculate CR values from ISF and CSF profiles
        /// Formula: CR = ISF / CSF
        /// Note: All calculations are done in mg/dL. CSF values are stored in mg/dL.
        /// This creates CR entries for all time slots where either ISF or CSF changes.
        func calculateCRFromCSF() {
            // Fetch CSF profile (always stored in mg/dL)
            let csfProfile = provider.csfProfile
            guard !csfProfile.sensitivities.isEmpty else { return }

            // Fetch ISF profile (always stored in mg/dL)
            let isfProfile = provider.isfProfile
            guard !isfProfile.sensitivities.isEmpty else { return }

            // Clear existing CR items
            items.removeAll()

            // Create a combined list of all unique time points from both ISF and CSF profiles
            var allTimeOffsets = Set<Int>()

            // Add ISF time points
            for isfEntry in isfProfile.sensitivities {
                allTimeOffsets.insert(isfEntry.offset)
            }

            // Add CSF time points
            for csfEntry in csfProfile.sensitivities {
                allTimeOffsets.insert(csfEntry.offset)
            }

            // Sort all time offsets
            let sortedTimeOffsets = allTimeOffsets.sorted()

            // For each unique time point, calculate CR
            for offsetMinutes in sortedTimeOffsets {
                // Find the active ISF value for this time
                let activeISF = isfProfile.sensitivities
                    .filter { $0.offset <= offsetMinutes }
                    .max(by: { $0.offset < $1.offset })?.sensitivity ?? isfProfile.sensitivities.first!.sensitivity

                // Find the active CSF value for this time (both in mg/dL)
                let activeCSF = csfProfile.sensitivities
                    .filter { $0.offset <= offsetMinutes }
                    .max(by: { $0.offset < $1.offset })?.sensitivity ?? csfProfile.sensitivities.first!.sensitivity

                // Calculate CR using formula: CR = ISF / (CSF * 0.1)
                // CSF is stored as mg/dL per 10g of carbs, so multiply by 0.1 to convert to mg/dL/g
                let calculatedCR = activeISF / (activeCSF * 0.1)

                // Find the closest CR value in rateValues
                guard let rateIndex = rateValues.firstIndex(where: { abs($0 - calculatedCR) < 0.05 })
                    ?? rateValues.enumerated().min(by: { abs($0.element - calculatedCR) < abs($1.element - calculatedCR) })?
                    .offset
                else {
                    continue
                }

                // Find time index
                let timeIndex = timeValues.firstIndex(of: Double(offsetMinutes * 60)) ?? 0

                // Add new item
                let newItem = Item(rateIndex: rateIndex, timeIndex: timeIndex)
                items.append(newItem)
            }

            // Validate and sort
            validate()

            // Update therapy items for UI
            therapyItems = getTherapyItems()
        }
    }
}
