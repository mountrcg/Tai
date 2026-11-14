import Foundation
import LoopKit

extension UserDefaults {
    private enum Key: String {
        case legacyPumpManagerRawValue = "com.rileylink.PumpManagerRawValue"
        case legacyPumpManagerState = "com.loopkit.Loop.PumpManagerState"
        case legacyCGMManagerState = "com.loopkit.Loop.CGMManagerState"
    }

    var legacyPumpManagerRawValue: PumpManager.RawValue? {
        dictionary(forKey: Key.legacyPumpManagerRawValue.rawValue)
    }

    func clearLegacyPumpManagerRawValue() {
        set(nil, forKey: Key.legacyPumpManagerRawValue.rawValue)
    }

    var legacyCGMManagerRawValue: CGMManager.RawValue? {
        dictionary(forKey: Key.legacyCGMManagerState.rawValue)
    }

    func clearLegacyCGMManagerRawValue() {
        set(nil, forKey: Key.legacyCGMManagerState.rawValue)
    }
}
