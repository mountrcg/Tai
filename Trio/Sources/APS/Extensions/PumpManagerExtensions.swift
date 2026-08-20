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

/// The Double a pump driver should round against.
///
/// `Double(truncating:)` renders a Decimal an ulp low - 0.07 arrives as 0.06999999999999999 - and
/// every kit floors against its table, so an exact rate misses its own entry and drops a whole
/// step, 0.06 on a Dana. Reading the value's own digits back is correctly rounded. 5 dp is well
/// past what any pump holds, in pump units and at any concentration.
extension Double {
    var deliverable: Double {
        Double(Decimal(self).precisionRounded(scale: 5).description) ?? self
    }
}

extension PumpManagerUI {
    func settingsViewController(
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
