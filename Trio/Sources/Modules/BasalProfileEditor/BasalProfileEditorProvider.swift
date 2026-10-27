import Combine
import Foundation
import LoopKit

extension BasalProfileEditor {
    final class Provider: BaseProvider, BasalProfileEditorProvider {
        @Injected() var settingsManager: SettingsManager!

        private let processQueue = DispatchQueue(label: "BasalProfileEditorProvider.processQueue")

        var profile: [BasalProfileEntry] {
            scope.basalProfile
        }

        var supportedBasalRates: [Decimal]? {
            // Drops 0 even where the pump accepts it: oref rejects a schedule containing a 0 rate, so a scheduled
            // basal of 0 would be saved and then refused. Zero temp basals are unaffected — they do not come
            // from this list.
            deviceManager.pumpManager?.supportedBasalRates
                .filter { $0 > 0 }
                .map { Decimal($0).rounded(scale: 3) }
        }

        func saveProfile(_ profile: [BasalProfileEntry]) -> AnyPublisher<Void, Error> {
            guard let pump = deviceManager?.pumpManager else {
                warning(.settings, "Basal profile not saved, no pump connected")
                return Fail(error: NSError()).eraseToAnyPublisher()
            }

            let syncValues = profile.map {
                RepeatingScheduleValue(
                    startTime: TimeInterval($0.minutes * 60),
                    value: Double($0.rate) / Double(settingsManager.settings.insulinConcentration)
                )
            }

            return Future { promise in
                pump.syncBasalRateSchedule(items: syncValues) { result in
                    switch result {
                    case .success:
                        self.scope.basalProfile = profile
                        promise(.success(()))
                    case let .failure(error):
                        promise(.failure(error))
                    }
                }
            }.eraseToAnyPublisher()
        }
    }
}
