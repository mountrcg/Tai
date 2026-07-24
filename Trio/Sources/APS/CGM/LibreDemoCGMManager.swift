import Foundation
import HealthKit
import LibreTransmitter
import LibreTransmitterUI
import LoopKit
import LoopKitUI
import LoopTestingKit
import os

final class LibreDemoCGMManager: LibreTransmitterManagerV3 {
    var timer: Timer?

    private let log = Logger(subsystem: "Trio", category: "LibreDemoCGMManager")

    /// Distinct identifier so this demo is selected/persisted independently of
    /// the real "FreeStyle Libre 1 / 2 / 2+" (LibreTransmitterManagerV3) entry.
    /// Trio drives selection and rehydration off the descriptor identifier in
    /// BasePluginManager.cgms + settings.cgmPluginIdentifier, not off the
    /// (inherited, non-overridable) static pluginIdentifier.
    static let demoPluginIdentifier = "LibreDemoCGMManager"

    override var localizedTitle: String { "FreeStyle Libre Demo" }

    override var pairingService: SensorPairingProtocol {
        MockSensorPairingService()
    }

    override var bluetoothSearcher: BluetoothSearcher {
        MockBluetoothSearcher()
    }

    override func establishProxy() {
        // do nothing
    }

    private static let secondsPerDay: TimeInterval = 24 * 60 * 60
    private var sensorStartDate = Date().addingTimeInterval(-LibreDemoCGMManager.secondsPerDay)

    public required init() {
        super.init()

        lastConnected = Date()

        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(5 * 60), repeats: true) { [weak self] _ in
            self?.reportMockSample()
        }

        // Also trigger a sample immediately, for dev convenience.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.reportMockSample()
        }
    }

    private func reportMockSample() {
        let date = Date()
        let value = 110.0 + sin(
            date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 3600 * 5) / (3600 * 5) * Double.pi * 2
        ) * 60
        let quantity = HKQuantity(unit: .milligramsPerDeciliter, doubleValue: value)
        let newSample = NewGlucoseSample(
            date: date,
            quantity: quantity,
            condition: nil,
            trend: nil,
            trendRate: nil,
            isDisplayOnly: false,
            wasUserEntered: false,
            syncIdentifier: "mock-libre + \(date)",
            device: testingDevice
        )
        log.debug("Reporting mock value of \(String(describing: value), privacy: .public)")

        // must be inside this handler as setobservables "depend" on latestbackfill
        let sensorData = MockSensorData(
            minutesSinceStart: Int(date.timeIntervalSince(sensorStartDate) / 60),
            maxMinutesWearTime: Int(14 * Self.secondsPerDay / 60),
            state: .ready,
            serialNumber: "12345",
            footerCrc: 0xABCD,
            date: date
        )

        latestBackfill = LibreGlucose(unsmoothedGlucose: value, glucoseDouble: value, timestamp: date)

        setObservables(sensorData: sensorData, bleData: nil, metaData: nil)

        delegateQueue.async {
            self.cgmManagerDelegate?.cgmManager(self, hasNew: CGMReadingResult.newData([newSample]))
        }
    }
}

extension LibreDemoCGMManager: TestingCGMManager {
    func injectGlucoseSamples(_: [LoopKit.NewGlucoseSample], futureSamples _: [LoopKit.NewGlucoseSample]) {
        // TODO: Support scenarios
    }

    var testingDevice: HKDevice {
        HKDevice(
            name: "LibreDemoCGM",
            manufacturer: "LoopKit",
            model: nil,
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
    }

    func acceptDefaultsAndSkipOnboarding() {}

    func trigger(action _: LoopTestingKit.DeviceAction) {
        // TODO: Support scenario actions
    }
}
