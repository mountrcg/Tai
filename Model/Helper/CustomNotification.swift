import Combine
import Foundation

extension Notification.Name {
    static let willUpdateOverrideConfiguration = Notification.Name("willUpdateOverrideConfiguration")
    static let didUpdateOverrideConfiguration = Notification.Name("didUpdateOverrideConfiguration")
    static let willUpdateTempTargetConfiguration = Notification.Name("willUpdateTempTargetConfiguration")
    static let didUpdateTempTargetConfiguration = Notification.Name("didUpdateTempTargetConfiguration")
    static let didUpdateProfileSchedules = Notification.Name("didUpdateProfileSchedules")
    /// Posted from `UserNotificationsManager` when the user taps the body of a
    /// schedule-activation notification (i.e. without choosing a specific action). Drives the
    /// in-app confirmation dialog on `AdaptProfile.RootView`.
    static let didTapScheduleNotification = Notification.Name("didTapScheduleNotification")
    static let liveActivityOrderDidChange = Notification.Name("liveActivityOrderDidChange")
    static let openFromGarminConnect = Notification.Name("Notification.Name.openFromGarminConnect")
}

func awaitNotification(_ name: Notification.Name) async {
    await withCheckedContinuation { continuation in
        var cancellable: AnyCancellable?

        cancellable = Foundation.NotificationCenter.default
            .publisher(for: name)
            .sink { _ in
                continuation.resume()
                cancellable?.cancel()
            }
    }
}
