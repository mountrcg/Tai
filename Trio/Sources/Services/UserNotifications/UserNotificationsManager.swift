import Combine
import CoreData
import Foundation
import LoopKit
import SwiftUI
import Swinject
import UserNotifications

protocol UserNotificationsManager {
    func getNotificationSettings(completionHandler: @escaping (UNNotificationSettings) -> Void)
    func requestNotificationPermissions(completion: @escaping (Bool) -> Void)
    @MainActor func applySnooze(for duration: TimeInterval) async
}

// MARK: - SnoozeObserver Protocol

protocol SnoozeObserver {
    @MainActor func snoozeDidChange(_ untilDate: Date)
}

final class BaseUserNotificationsManager: NSObject, UserNotificationsManager, Injectable {
    enum Identifier: String {
        case carbsRequiredNotification = "Trio.carbsRequiredNotification"
    }

    @Injected() var alertPermissionsChecker: AlertPermissionsChecker!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var apsManager: APSManager!
    @Injected() private var trioAlertManager: TrioAlertManager!
    @Injected() private var router: Router!

    @Persisted(key: "UserNotificationsManager.snoozeUntilDate") private var snoozeUntilDate: Date = .distantPast

    private let notificationCenter = UNUserNotificationCenter.current()

    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext

    // Queue for handling Core Data change notifications
    private let queue = DispatchQueue(label: "BaseUserNotificationsManager.queue", qos: .userInitiated)
    private var coreDataPublisher: AnyPublisher<Set<NSManagedObjectID>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    /// Retained so schedule-activation notification responses can construct `AdaptProfile.Provider`
    /// on demand without an extra DI round-trip.
    private let resolver: Resolver

    init(resolver: Resolver) {
        self.resolver = resolver
        super.init()
        notificationCenter.delegate = self
        injectServices(resolver)
        broadcaster.register(SettingsObserver.self, observer: self)

        coreDataPublisher =
            CoreDataStack.shared.entityChangePublisher
                .receive(on: queue)
                .share()
                .eraseToAnyPublisher()

        Task { await updateGlucoseBadge() }
        configureNotificationCategories()
        clearLegacyCarbsRequiredNotification()
        clearLegacyLoopNotifications()
        subscribeGlucoseUpdates()
    }

    private func configureNotificationCategories() {
        notificationCenter.getNotificationCategories { [weak self] existingCategories in
            guard let self else { return }

            let glucoseCategory = NotificationCategoryFactory.createGlucoseCategory()
            let scheduleCategory = NotificationCategoryFactory.createScheduleActivationCategory()
            let scheduleActivatedCategory = NotificationCategoryFactory.createScheduleActivatedCategory()
            let profileRevertedCategory = NotificationCategoryFactory.createProfileRevertedCategory()

            var categories = existingCategories
            categories.update(with: glucoseCategory)
            categories.update(with: scheduleCategory)
            categories.update(with: scheduleActivatedCategory)
            categories.update(with: profileRevertedCategory)
            // UNUserNotificationCenter methods should be called on main thread
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.notificationCenter.setNotificationCategories(categories)
            }
        }
    }

    /// Subscribes to the two sources that signal a glucose change so the app
    /// icon badge stays current:
    /// - `coreDataPublisher` filtered to `GlucoseStored` — catches deletions
    ///   (batch inserts don't fire normal Core Data save notifications, so
    ///   inserts come through `updatePublisher` below).
    /// - `glucoseStorage.updatePublisher` — fires on every new reading.
    private func subscribeGlucoseUpdates() {
        coreDataPublisher?.filteredByEntityName("GlucoseStored")
            .sink { [weak self] _ in Task { await self?.updateGlucoseBadge() } }
            .store(in: &subscriptions)
        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in Task { await self?.updateGlucoseBadge() } }
            .store(in: &subscriptions)
    }

    private func addAppBadge(glucose: Int?) {
        guard let glucose = glucose, settingsManager.settings.glucoseBadge else {
            DispatchQueue.main.async {
                self.notificationCenter.setBadgeCount(0) { error in
                    guard let error else {
                        return
                    }
                    warning(.alerts, "Setting app badge failed", error: error)
                }
            }
            return
        }

        let badge: Int
        if settingsManager.settings.units == .mmolL {
            badge = Int(round(Double((glucose * 10).asMmolL)))
        } else {
            badge = glucose
        }

        DispatchQueue.main.async {
            self.notificationCenter.setBadgeCount(badge) { error in
                guard let error else {
                    return
                }
                warning(.alerts, "Setting app badge failed", error: error)
            }
        }
    }

    /// Removes any `Trio.carbsRequiredNotification` UN still sitting in the
    /// system from a pre-pipeline install. Safe no-op when none exist.
    private func clearLegacyCarbsRequiredNotification() {
        let id = Identifier.carbsRequiredNotification.rawValue
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [id])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// Purges the two "Last loop was X min ago" UNs the legacy
    /// `scheduleMissingLoopNotifiactions` path scheduled. Their identifiers
    /// aren't known to `NotLoopingMonitor`, so without this cleanup they'd
    /// fire once each after upgrade — https://github.com/nightscout/Trio/issues/1296
    private func clearLegacyLoopNotifications() {
        let ids = ["Trio.noLoopFirstNotification", "Trio.noLoopSecondNotification"]
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
        notificationCenter.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func fetchGlucoseIDs() async throws -> [NSManagedObjectID] {
        let context = CoreDataStack.shared.newTaskContext()
        context.name = "fetchGlucoseIDs"
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.predicateFor20MinAgo,
            key: "date",
            ascending: false,
            fetchLimit: 3
        )

        return try await context.perform {
            guard let fetchedResults = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedResults.map(\.objectID)
        }
    }

    /// Refreshes the Trio app icon badge from the latest stored glucose
    /// reading. Glucose alarm emission has moved to `GlucoseAlertCoordinator`
    /// (urgent-low / low / forecasted-low / high are issued via
    /// `TrioAlertManager` based on the user-configured `[GlucoseAlert]` list).
    @MainActor private func updateGlucoseBadge() async {
        do {
            addAppBadge(glucose: nil)
            let glucoseIDs = try await fetchGlucoseIDs()
            let latest = try glucoseIDs.compactMap { id in
                try viewContext.existingObject(with: id) as? GlucoseStored
            }.first?.glucose
            addAppBadge(glucose: latest.map { Int($0) })
        } catch {
            warning(.alerts, "Updating glucose app badge failed", error: error)
        }
    }

    func getNotificationSettings(completionHandler: @escaping (UNNotificationSettings) -> Void) {
        notificationCenter.getNotificationSettings { settings in
            DispatchQueue.main.async {
                completionHandler(settings)
            }
        }
    }

    func requestNotificationPermissions(completion: @escaping (Bool) -> Void) {
        debug(.alerts, "Requesting notification permission")
        notificationCenter.requestAuthorization(options: [.badge, .sound, .alert]) { granted, error in
            if granted {
                info(.alerts, "Notification permission granted")
                DispatchQueue.main.async {
                    completion(granted)
                }
            } else {
                warning(.alerts, "Notification permission not granted", error: error)
            }
        }
    }

    /// Forwards to the canonical snooze entry point on `TrioAlertManager`.
    /// All snooze surfaces (this method via UN actions / Watch / Snooze
    /// module / in-app banner) converge there so persistent state, mute
    /// window, and observers stay in sync.
    @MainActor func applySnooze(for duration: TimeInterval) async {
        await trioAlertManager.applySnooze(for: duration)
    }
}

extension BaseUserNotificationsManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        if userInfo[AlertUserInfoKey.managerIdentifier.rawValue] is String {
            completionHandler([.badge, .list])
            return
        }
        completionHandler([.banner, .badge, .sound, .list])
    }

    /// UNUserNotificationCenterDelegate method called when user interacts with a notification.
    /// This can be called off the main thread, so we ensure all work happens on @MainActor.
    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        debug(
            .alerts,
            "Notification response \(response.actionIdentifier) for category \(response.notification.request.content.categoryIdentifier)"
        )

        let userInfo = response.notification.request.content.userInfo
        if userInfo[AlertUserInfoKey.managerIdentifier.rawValue] is String {
            trioAlertManager.handleNotificationResponse(response)
            return
        }

        // Handle quick snooze actions (from notification action buttons).
        if let quickAction = NotificationResponseAction(rawValue: response.actionIdentifier) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.applySnooze(for: quickAction.duration)
            }
            return
        }

        // Handle schedule-activation actions (indefinite schedule fires via PR 5 Flow B).
        if response.notification.request.content.categoryIdentifier
            == NotificationCategoryIdentifier.scheduleActivation.rawValue
        {
            if let scheduleAction = ScheduleNotificationAction(rawValue: response.actionIdentifier) {
                handleScheduleActivationResponse(action: scheduleAction, notification: response.notification)
            } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                // User tapped the notification body — open an in-app dialog so they can pick
                // Save to pump / Skip without having to long-press the notification.
                handleScheduleActivationDefaultTap(notification: response.notification)
            }
            return
        }
    }

    /// Responds to user interaction on a scheduled-activation notification.
    /// - `.confirm` → navigates to AdaptProfile and broadcasts `didConfirmScheduleActivation` so
    ///   the root view can present the pump-save confirmation pre-filled for the target profile.
    /// - `.skip` → marks the occurrence as fired on `ProfileScheduleStored` without activation,
    ///   so the firer's next sweep doesn't re-post the notification.
    private func handleScheduleActivationResponse(
        action: ScheduleNotificationAction,
        notification: UNNotification
    ) {
        let userInfo = notification.request.content.userInfo
        guard
            let scheduleRaw = userInfo[ScheduleNotificationUserInfoKey.scheduleID] as? String,
            let scheduleID = UUID(uuidString: scheduleRaw),
            let profileRaw = userInfo[ScheduleNotificationUserInfoKey.profileID] as? String,
            let profileID = UUID(uuidString: profileRaw),
            let occurrenceEpoch = userInfo[ScheduleNotificationUserInfoKey.occurrenceEpoch] as? Double
        else {
            warning(.alerts, "Profile schedule notification payload is malformed, ignoring it")
            return
        }
        let occurrence = Date(timeIntervalSince1970: occurrenceEpoch)

        info(.settings, "Profile schedule notification answered with \(action.rawValue)")
        switch action {
        case .confirm:
            runScheduledActivation(
                scheduleID: scheduleID,
                profileID: profileID,
                occurrence: occurrence
            )
        case .skip:
            markScheduleOccurrenceSkipped(scheduleID: scheduleID, occurrence: occurrence)
        }
    }

    /// Default-tap on the notification body (no explicit action button chosen). Navigates to
    /// AdaptProfile and broadcasts the request so RootView can present a Save-to-pump / Skip
    /// dialog. This is distinct from the explicit `.confirm` / `.skip` action buttons, which run
    /// directly without an in-app prompt.
    private func handleScheduleActivationDefaultTap(notification: UNNotification) {
        let userInfo = notification.request.content.userInfo
        guard
            let scheduleRaw = userInfo[ScheduleNotificationUserInfoKey.scheduleID] as? String,
            let scheduleID = UUID(uuidString: scheduleRaw),
            let profileRaw = userInfo[ScheduleNotificationUserInfoKey.profileID] as? String,
            let profileID = UUID(uuidString: profileRaw),
            let occurrenceEpoch = userInfo[ScheduleNotificationUserInfoKey.occurrenceEpoch] as? Double
        else {
            warning(.alerts, "Profile schedule notification payload is malformed, ignoring tap")
            return
        }
        let occurrence = Date(timeIntervalSince1970: occurrenceEpoch)
        debug(.settings, "Profile schedule notification tapped, opening profiles")
        // Stash the request first so AdaptProfile.StateModel picks it up regardless of whether
        // it's already alive (Foundation notification path) or about to spin up (drain on
        // subscribe). Navigate afterwards so the new RootView sees the mailbox populated.
        ScheduledActivationMailbox.enqueue(
            scheduleID: scheduleID,
            profileID: profileID,
            occurrence: occurrence
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.router.mainModalScreen.send(.adaptProfile)
            Foundation.NotificationCenter.default.post(
                name: .didTapScheduleNotification,
                object: nil,
                userInfo: [
                    ScheduleNotificationUserInfoKey.scheduleID: scheduleID,
                    ScheduleNotificationUserInfoKey.profileID: profileID,
                    ScheduleNotificationUserInfoKey.occurrenceEpoch: occurrenceEpoch
                ]
            )
        }
    }

    /// Performs the indefinite activation directly from the notification-action tap. The
    /// notification body already explained what "Save to pump" does, so we don't need a second
    /// in-app confirmation — tapping the action IS the confirmation. Clears the schedule's
    /// `pendingOccurrence` either way so the firer moves on.
    private func runScheduledActivation(scheduleID: UUID, profileID: UUID, occurrence: Date) {
        info(.settings, "Scheduled profile activation confirmed")
        Task { @MainActor [weak self] in
            guard let self else { return }
            let provider = AdaptProfile.Provider(resolver: self.resolver)
            await provider.markScheduleActivated(scheduleID: scheduleID, occurrence: occurrence)
            let outcome = await provider.activate(
                id: profileID,
                durationMinutes: nil,
                confirmedPumpSync: true
            )
            info(.settings, "Scheduled profile activation finished with \(String(describing: outcome))")
            Foundation.NotificationCenter.default.post(
                name: .didUpdateProfileSchedules,
                object: nil
            )
        }
    }

    /// Stamps `lastFiredAt = occurrence` and clears `pendingOccurrence` so the firer's next sweep
    /// treats the occurrence as handled and moves on to the next one. Runs on a background context;
    /// the `didUpdateProfileSchedules` broadcast refreshes open schedule lists.
    private func markScheduleOccurrenceSkipped(scheduleID: UUID, occurrence: Date) {
        let context = CoreDataStack.shared.newTaskContext()
        context.perform {
            let request = ProfileScheduleStored.fetch(.scheduleByID(scheduleID), fetchLimit: 1)
            guard let row = (try? context.fetch(request))?.first else { return }
            row.lastFiredAt = occurrence
            row.pendingOccurrence = nil
            try? context.save()
            Task { @MainActor in
                Foundation.NotificationCenter.default.post(
                    name: .didUpdateProfileSchedules,
                    object: nil
                )
            }
        }
    }
}

extension BaseUserNotificationsManager: SettingsObserver {
    func settingsDidChange(_: TrioSettings) {
        Task { await updateGlucoseBadge() }
    }
}
