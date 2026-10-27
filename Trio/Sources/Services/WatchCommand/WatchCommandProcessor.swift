import Foundation
import Swinject

/// Validates and executes watch commands through `WatchCommandPipeline`, independent of the transport.
protocol WatchCommandProcessor {
    /// Runs `request` at most once per app and request ID and returns its terminal result.
    func process(_ request: WatchCommandRequest) async -> WatchCommandResult

    /// Read at call time, so a switch turned off is reported off in the very next reply.
    func capabilities() -> WatchCommandCapabilities
}

extension WatchCommandAuthorization {
    /// Call before `new` is stored. Turning either Garmin command switch off always revokes, even
    /// when it is switched back on right after; turning one on never does.
    func settingsWillChange(from old: TrioSettings, to new: TrioSettings) {
        let masterTurnedOff = old.isGarminCommandControlEnabled && !new.isGarminCommandControlEnabled
        let bolusTurnedOff = old.isGarminBolusCommandEnabled && !new.isGarminBolusCommandEnabled
        guard masterTurnedOff || bolusTurnedOff else { return }
        revoke()
        info(.watch, "Garmin command setting turned off, pending watch commands revoked")
    }
}

/// Admits one watch insulin command at a time, so each validation sees the previous command's delivery.
/// Waiters suspend on a continuation and never hold the actor.
///
/// Stricter than the shared 20% recent-bolus check: after a watch bolus reached `APSManager`, the next
/// one is refused for `BolusSafetyEvaluator.recentBolusWindowMinutes`, since pump history may lag and a
/// refusal can still mean partial delivery.
actor WatchCommandInsulinLane {
    private var isOccupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    /// Last pump request issued through the lane; pump history may not show it yet.
    private(set) var lastEnactment: Date?

    var waitingCount: Int { waiters.count }

    func enter() async {
        guard isOccupied else {
            isOccupied = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Hands the lane straight to the next waiter, so no newcomer can slip in between.
    func leave() {
        if waiters.isEmpty {
            isOccupied = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    func recordEnactment(at date: Date) {
        lastEnactment = date
    }

    /// Puts back what `recordEnactment` replaced when the request never reached the pump.
    func restoreEnactment(_ date: Date?) {
        lastEnactment = date
    }
}

/// Garmin is the only transport sending commands, so the gates read the Garmin settings.
final class BaseWatchCommandProcessor: WatchCommandProcessor, Injectable {
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var bolusSafetyValidator: BolusSafetyValidator!
    @Injected() private var pipeline: WatchCommandPipeline!

    private let actions: WatchCommandActions
    private let insulinLane: WatchCommandInsulinLane
    private let now: () -> Date
    private let log: WatchCommandLogger

    init(
        resolver: Resolver,
        actions: WatchCommandActions? = nil,
        insulinLane: WatchCommandInsulinLane = WatchCommandInsulinLane(),
        now: @escaping () -> Date = Date.init,
        log: WatchCommandLogger = .app
    ) {
        self.actions = actions ?? BaseWatchCommandActions(resolver: resolver)
        self.insulinLane = insulinLane
        self.now = now
        self.log = log
        injectServices(resolver)
    }

    func process(_ request: WatchCommandRequest) async -> WatchCommandResult {
        await pipeline.run(
            requestID: request.requestID,
            appUUID: request.appUUID,
            issuedAt: request.date,
            command: request.command,
            name: request.command.name,
            gate: { [self] in gateRejection(for: request.command) }
        ) { context in
            await execute(request.command, context: context)
        }
    }

    func capabilities() -> WatchCommandCapabilities {
        let settings = settingsManager.settings
        return WatchCommandCapabilities(
            isCommandControlEnabled: settings.isGarminCommandControlEnabled,
            isBolusCommandEnabled: settings.isGarminBolusCommandEnabled,
            maxBolus: settingsManager.pumpSettings.maxBolus,
            maxCarbs: settings.maxCarbs,
            bolusIncrement: settingsManager.preferences.bolusIncrement
        )
    }

    // MARK: - Validation

    private func execute(_ command: WatchCommand, context: WatchCommandContext) async -> WatchCommandResult {
        if let rejection = amountRejection(for: command) {
            return rejection
        }

        switch command {
        case let .bolus(units):
            return await bolus(units, context: context)
        case let .carbs(grams):
            return await carbs(grams, context: context)
        case let .mealBolus(grams, units):
            return await mealBolus(carbs: grams, bolus: units, context: context)
        }
    }

    /// Re-read at every check: settings can change while a command is suspended.
    private func gateRejection(for command: WatchCommand) -> WatchCommandResult? {
        let garminSettings = settingsManager.settings.garminSettings
        guard garminSettings.isCommandControlEnabled else {
            log.info("Garmin \(command.name) command refused, watch commands are off")
            return .failure(String(localized: "Watch commands are disabled.", comment: "Watch command ack"))
        }
        guard !command.isInsulin || garminSettings.isBolusCommandEnabled else {
            log.info("Garmin \(command.name) command refused, bolus commands are off")
            return .failure(String(localized: "Bolus from watch is disabled.", comment: "Watch command ack"))
        }
        return nil
    }

    private func amountRejection(for command: WatchCommand) -> WatchCommandResult? {
        if let units = command.bolusAmount, units <= 0 {
            return .failure(String(localized: "Invalid bolus amount.", comment: "Watch command ack"))
        }
        if let grams = command.carbsAmount {
            guard grams > 0 else {
                return .failure(String(localized: "Invalid carbs amount.", comment: "Watch command ack"))
            }
            guard Decimal(grams) <= settingsManager.settings.maxCarbs else {
                log.info("Garmin \(command.name) command refused, carbs above max carbs")
                return .failure(String(localized: "Carbs exceed the maximum allowed.", comment: "Watch command ack"))
            }
        }
        return nil
    }

    // MARK: - Treatments

    private enum BolusOutcome {
        case delivered
        /// Nothing was sent to the pump.
        case rejected(String)
        /// The pump refused or errored; part of the bolus may still have been delivered.
        case failed
    }

    private func bolus(_ units: Decimal, context: WatchCommandContext) async -> WatchCommandResult {
        switch await deliverBolus(units, context: context) {
        case .delivered:
            return .success(.genericSuccess, String(localized: "Bolus started.", comment: "Watch command ack"))
        case let .rejected(message):
            return .failure(message)
        case .failed:
            return .failure(String(localized: "Bolus failed. Check pump history before repeating.", comment: "Watch command ack"))
        }
    }

    private func carbs(_ grams: Int, context: WatchCommandContext) async -> WatchCommandResult {
        if let rejection = context.rejection() {
            return rejection
        }
        do {
            try await actions.storeCarbs(grams, date: context.issuedAt, authorize: context.finalCheck())
            return .success(.carbsLogged, String(localized: "Carbs logged.", comment: "Watch command ack"))
        } catch let rejection as WatchCommandRejection {
            return rejection.result
        } catch {
            log.warning("Storing carbs from Garmin failed (\(WatchCommandErrorCategory.name(for: error)))")
            return .failure(String(localized: "Could not log carbs.", comment: "Watch command ack"))
        }
    }

    private func mealBolus(carbs grams: Int, bolus units: Decimal, context: WatchCommandContext) async -> WatchCommandResult {
        if let rejection = context.rejection() {
            return rejection
        }
        do {
            // a meal command is insulin, so its carbs also re-check the freshness window
            try await actions.storeCarbs(grams, date: context.issuedAt, authorize: context.finalCheck(checkingExpiry: true))
        } catch let rejection as WatchCommandRejection {
            return rejection.result
        } catch {
            log
                .warning(
                    "Storing meal carbs from Garmin failed, no bolus delivered (\(WatchCommandErrorCategory.name(for: error)))"
                )
            return .failure(String(localized: "Could not log carbs. No bolus was delivered.", comment: "Watch command ack"))
        }

        switch await deliverBolus(units, context: context) {
        case .delivered:
            return .success(.genericSuccess, String(localized: "Carbs logged and bolus started.", comment: "Watch command ack"))
        case .rejected:
            return WatchCommandResult(
                acknowledged: false,
                ackCode: .partialFailure,
                message: String(localized: "Carbs logged. No bolus was delivered.", comment: "Watch command ack")
            )
        case .failed:
            return WatchCommandResult(
                acknowledged: false,
                ackCode: .partialFailure,
                message: String(
                    localized: "Carbs logged. Bolus failed, check pump history before repeating.",
                    comment: "Watch command ack"
                )
            )
        }
    }

    private func deliverBolus(_ units: Decimal, context: WatchCommandContext) async -> BolusOutcome {
        await insulinLane.enter()
        let outcome = await deliverBolusInLane(units, context: context)
        await insulinLane.leave()
        return outcome
    }

    /// Everything is re-checked: the wait for the lane can last as long as another command's
    /// validation and pump request.
    private func deliverBolusInLane(_ units: Decimal, context: WatchCommandContext) async -> BolusOutcome {
        if let rejection = context.rejection(checkingExpiry: true) {
            return .rejected(rejection.message)
        }

        let recentWindow = Double(BolusSafetyEvaluator.recentBolusWindowMinutes * 60)
        let previousEnactment = await insulinLane.lastEnactment
        if let previousEnactment, now().timeIntervalSince(previousEnactment) < recentWindow {
            log.info("Garmin bolus refused, previous watch bolus may not be in pump history yet")
            return .rejected(BolusSafetyRejection.recentBolusWithinWindow(totalRecent: 0).watchMessage)
        }

        // cover every bolus since the watch sent the command, and never less than the standard window
        let lookbackStart = min(context.issuedAt, now().addingTimeInterval(-recentWindow))

        do {
            switch try await bolusSafetyValidator.validate(bolusAmount: units, lookbackStart: lookbackStart) {
            case .allowed:
                break
            case let .rejected(reason):
                log.info("Garmin bolus refused by safety check (\(reason.logName))")
                return .rejected(reason.watchMessage)
            }
        } catch {
            log.warning("Garmin bolus safety check failed, no bolus delivered (\(WatchCommandErrorCategory.name(for: error)))")
            return .rejected(String(localized: "Could not verify bolus safety.", comment: "Watch command ack"))
        }

        // validation awaited, so the request may have expired or been revoked meanwhile
        if let rejection = context.rejection(checkingExpiry: true) {
            return .rejected(rejection.message)
        }
        // recorded before the request, since a pump error can still mean partial delivery
        await insulinLane.recordEnactment(at: now())
        do {
            return try await actions.enactBolus(units, authorize: context.finalCheck(checkingExpiry: true)) ? .delivered : .failed
        } catch {
            // the final check stopped it before `APSManager`, so nothing reached the pump
            await insulinLane.restoreEnactment(previousEnactment)
            let message = (error as? WatchCommandRejection)?.result.message
            return .rejected(message ?? String(localized: "Could not verify bolus safety.", comment: "Watch command ack"))
        }
    }
}

private extension BolusSafetyRejection {
    /// Case name only; the associated values are insulin amounts, which stay out of the log.
    var logName: String {
        switch self {
        case .exceedsMaxBolus: return "exceedsMaxBolus"
        case .iobUnavailable: return "iobUnavailable"
        case .exceedsMaxIOB: return "exceedsMaxIOB"
        case .recentBolusWithinWindow: return "recentBolusWithinWindow"
        }
    }

    var watchMessage: String {
        switch self {
        case .exceedsMaxBolus:
            return String(localized: "Bolus exceeds max bolus.", comment: "Watch command ack")
        case .iobUnavailable:
            return String(localized: "IOB unavailable. Bolus not delivered.", comment: "Watch command ack")
        case .exceedsMaxIOB:
            return String(localized: "Bolus would exceed max IOB.", comment: "Watch command ack")
        case .recentBolusWithinWindow:
            return String(localized: "A bolus was given in the last 6 minutes.", comment: "Watch command ack")
        }
    }
}
