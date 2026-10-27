import CoreData
import Observation
import SwiftUI

extension CSFEditor {
    @Observable final class StateModel: BaseStateModel<Provider> {
        @ObservationIgnored @Injected() private var nightscout: NightscoutManager!

        var items: [Item] = []
        var initialItems: [Item] = []
        var therapyItems: [TherapySettingItem] = []
        var shouldDisplaySaving: Bool = false

        let timeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

        var rateValues: [Decimal] {
            let settingsProvider = PickerSettingsProvider.shared
            return settingsProvider.generatePickerValues(from: settingsProvider.settings.carbSensitivity, units: units)
        }

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeValues.count - 1
        }

        var hasChanges: Bool {
            initialItems != items
        }

        private(set) var units: GlucoseUnits = .mgdL

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
            units = settingsManager.settings.units

            let profile = provider.profile

            items = profile.sensitivities.map { value in
                let timeIndex = timeValues.firstIndex(of: Double(value.offset * 60)) ?? 0
                var rateIndex = rateValues.firstIndex(of: value.sensitivity)
                if rateIndex == nil {
                    // try to look up the closest value
                    if let min = rateValues.first, let max = rateValues.last {
                        if value.sensitivity >= (min - 1), value.sensitivity <= (max + 1) {
                            rateIndex = rateValues.findClosestIndex(to: value.sensitivity)
                        }
                    }
                }
                return Item(rateIndex: rateIndex ?? 0, timeIndex: timeIndex)
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
            shouldDisplaySaving.toggle()

            let sensitivities = items.map { item -> CarbSensitivityEntry in
                let formatter = DateFormatter()
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "HH:mm:ss"
                let date = Date(timeIntervalSince1970: self.timeValues[item.timeIndex])
                let minutes = Int(date.timeIntervalSince1970 / 60)
                let rate = self.rateValues[item.rateIndex]
                return CarbSensitivityEntry(sensitivity: rate, offset: minutes, start: formatter.string(from: date))
            }
            let profile = CarbSensitivities(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                sensitivities: sensitivities
            )
            provider.saveProfile(profile)
            initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }

            Task.detached(priority: .low) {
                do {
                    debug(.nightscout, "Uploading CSF profile to Nightscout")
                    try await self.nightscout.uploadProfiles()
                } catch {
                    warning(.nightscout, "Uploading CSF profile to Nightscout failed", error: error)
                }
            }
        }

        func validate() {
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    let uniq = Array(Set(self.items))
                    let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
                    sorted.first?.timeIndex = 0
                    if self.items != sorted {
                        self.items = sorted
                    }
                    if self.items.isEmpty {
                        self.units = self.settingsManager.settings.units
                    }
                }
            }
        }

        func suggestDefaultCSF() {
            // Get ISF and CR values at 1pm (13:00 = 780 minutes from midnight)
            let targetMinutes = 13 * 60 // 1pm

            let isfProfile = provider.isfProfile
            let crProfile = provider.crProfile

            // Find ISF value at 1pm
            let isfAt1pm = isfProfile.sensitivities.last(where: { $0.offset <= targetMinutes })?.sensitivity ?? 100

            // Find CR value at 1pm
            let crAt1pm = crProfile.schedule.last(where: { $0.offset <= targetMinutes })?.ratio ?? 10

            // Calculate CSF = ISF / CR * 10 (stored as mg/dL per 10g of carbs)
            let calculatedCSF = isfAt1pm / crAt1pm * 10

            // Find closest rate index to the calculated CSF
            var rateIndex = rateValues.firstIndex(of: calculatedCSF) ?? 0
            if rateIndex == 0, let closestIndex = rateValues.findClosestIndex(to: calculatedCSF) {
                rateIndex = closestIndex
            }

            // Create a single entry at midnight (time index 0)
            items = [Item(rateIndex: rateIndex, timeIndex: 0)]
        }
    }
}

extension CSFEditor.StateModel: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        units = settingsManager.settings.units
    }
}
