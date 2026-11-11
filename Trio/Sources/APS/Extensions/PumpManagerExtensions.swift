import LoopKit
import LoopKitUI

extension PumpManager {
    typealias RawValue = [String: Any]

    var rawValue: [String: Any] {
        [
            "managerIdentifier": pluginIdentifier, // "managerIdentifier": type(of: self).managerIdentifier,
            "state": rawState
        ]
    }
}

/// The Double a pump driver should round against when the caller only holds a `Double`.
///
/// Decimal-to-Double conversion can place an intended table value just below its binary Double
/// representation. Pump drivers floor against their tables, so that tiny error can lose a full
/// pump step. Five decimal places preserve every supported pump/concentration rate while
/// recovering the intended table value.
extension Double {
    var deliverable: Double {
        Decimal(self).precisionRounded(scale: 5).nearestDouble
    }
}

extension PumpManagerUI {
    @MainActor func settingsViewController(
        bluetoothProvider: BluetoothProvider,
        pumpManagerOnboardingDelegate: PumpManagerOnboardingDelegate?
    ) -> UIViewController & CompletionNotifying {
        var vc = settingsViewController(
            bluetoothProvider: bluetoothProvider,
            colorPalette: .default,
            allowDebugFeatures: true,
            allowedInsulinTypes: [.apidra, .humalog, .novolog, .fiasp, .lyumjev]
        )
        vc.pumpManagerOnboardingDelegate = pumpManagerOnboardingDelegate
        return vc
    }
}

protocol PumpSettingsBuilder {
    func settingsViewController() -> UIViewController & CompletionNotifying
}
