import Foundation
import SwiftDate

enum Config {
    static let treatWarningsAsErrors = true
    static let withSignPosts = false

    /// UserDefaults keys for runtime-tunable loop/glucose settings, written by
    /// `BaseFetchGlucoseManager` and read through the accessors below.
    enum UserDefaultsKey {
        static let loopInterval = "Config_LoopInterval"
        static let filterTime = "Config_FilterTime"
        static let minimumGlucose = "Config_MinimumGlucose"
    }

    /// Production values — also the fallback used when a key was never written.
    static let defaultLoopInterval: TimeInterval = 20.seconds.timeInterval
    static let defaultFilterTime: TimeInterval = 3.5 * 60
    static let defaultMinimumGlucose = 39

    /// Values written while the in-app CGM simulator is active: a fast loop,
    /// minimal glucose filtering, and a lowered floor so sub-39 test values pass through.
    static let simulatorLoopInterval: TimeInterval = 10
    static let simulatorFilterTime: TimeInterval = 10
    static let simulatorMinimumGlucose = 1

    static var loopInterval: TimeInterval {
        let value = UserDefaults.standard.double(forKey: UserDefaultsKey.loopInterval)
        return value > 0 ? value : defaultLoopInterval
    }

    static var filterTime: TimeInterval {
        let value = UserDefaults.standard.double(forKey: UserDefaultsKey.filterTime)
        return value > 0 ? value : defaultFilterTime
    }

    static var minimumGlucose: Int {
        let value = UserDefaults.standard.integer(forKey: UserDefaultsKey.minimumGlucose)
        return value > 0 ? value : defaultMinimumGlucose
    }

    static let expirationInterval = 10.minutes.timeInterval
}
