import Combine
import Foundation

/// Stages explicit editor actions so observer callbacks and profile activation never change ratios.
final class SmbDeliveryRatioReview: ObservableObject {
    typealias Field = SmbDeliveryRatioSuggestion.Field

    struct Pending: Identifiable {
        let id = UUID()
        let starting: Preferences
        let proposed: Preferences
        let context: String
        let revision: String
        let scopeID: ObjectIdentifier

        var fields: [Field] {
            starting.autoisf && starting.smbDeliveryRatioBGrange > 0 ? Field.allCases : [.fixed]
        }

        func current(_ field: Field) -> Decimal {
            starting[keyPath: field.keyPath]
        }

        func suggestion(_ field: Field) -> SmbDeliveryRatioSuggestion.Result {
            SmbDeliveryRatioSuggestion.suggestion(
                current: current(field), field: field, loopInterval: proposed.sub5MinuteLoopInterval
            )
        }
    }

    enum Resolution: Equatable { case apply, keep, cancel }

    @Published private(set) var preferences: Preferences
    @Published var pending: Pending?
    @Published private(set) var staleReview = false
    private let scope: SettingsScope
    private let context: () -> String
    private let revision: () -> String
    private let defaults: UserDefaults
    private static let draftAcknowledgements = NSMapTable<AnyObject, NSString>.weakToStrongObjects()

    init(
        scope: SettingsScope,
        defaults: UserDefaults = .standard,
        revision: @escaping () -> String = { "" },
        context: @escaping () -> String
    ) {
        self.scope = scope
        self.defaults = defaults
        self.context = context
        self.revision = revision
        preferences = scope.preferences
    }

    private var acknowledgementKey: String { "sub5MinuteRatioReview." + context() }

    var needsReview: Bool {
        let current = scope.preferences
        guard current.enableSub5MinuteGlucose, current.sub5MinuteLoopInterval < 5 else { return false }
        let acknowledged = scope.isDraft
            ? Self.draftAcknowledgements.object(forKey: scope) as String?
            : defaults.string(forKey: acknowledgementKey)
        let fingerprint = current.glucoseObservationFingerprint
        return acknowledged != (scope.isDraft ? context() + fingerprint : fingerprint)
    }

    func refresh() {
        preferences = scope.preferences
    }

    func change<Value>(_ key: WritableKeyPath<Preferences, Value>, to value: Value) {
        guard pending == nil else { return }
        let starting = scope.preferences
        var proposed = starting
        proposed[keyPath: key] = value
        guard proposed != starting else { return }
        let enables = !starting.enableSub5MinuteGlucose && proposed.enableSub5MinuteGlucose
        let shortens = proposed.sub5MinuteLoopInterval < starting.sub5MinuteLoopInterval
        if proposed.enableSub5MinuteGlucose, proposed.sub5MinuteLoopInterval < 5, enables || shortens {
            stage(starting: starting, proposed: proposed)
        } else {
            scope.preferences = proposed
            refresh()
        }
    }

    func reviewCurrent() {
        guard pending == nil else { return }
        let current = scope.preferences
        stage(starting: current, proposed: current)
    }

    private func stage(starting: Preferences, proposed: Preferences) {
        staleReview = false
        pending = Pending(
            starting: starting,
            proposed: proposed,
            context: context(),
            revision: revision(),
            scopeID: ObjectIdentifier(scope)
        )
    }

    func canApply(_ review: Pending, values: [Field: Decimal]) -> Bool {
        guard !values.isEmpty else { return false }
        var result = review.proposed
        for (field, value) in values {
            guard review.fields.contains(field), case .suggestion = review.suggestion(field),
                  !value.isNaN, field.bounds.contains(value), value <= review.current(field),
                  value * 20 == (value * 20).rounded()
            else { return false }
            result[keyPath: field.keyPath] = value
        }
        return !review.fields.contains(.minimum) || SmbDeliveryRatioSuggestion.validEndpoints(
            minimum: result.smbDeliveryRatioMin, maximum: result.smbDeliveryRatioMax
        )
    }

    @discardableResult
    func resolve(_ id: UUID, as resolution: Resolution, values: [Field: Decimal] = [:]) -> Bool {
        guard let review = pending, review.id == id else { return false }
        if resolution == .cancel {
            pending = nil
            refresh()
            return true
        }
        guard review.scopeID == ObjectIdentifier(scope), review.context == context(), review.revision == revision(),
              review.starting == scope.preferences
        else {
            pending = nil
            staleReview = true
            refresh()
            return false
        }
        var result = review.proposed
        if resolution == .apply {
            guard canApply(review, values: values) else { return false }
            for (field, value) in values { result[keyPath: field.keyPath] = value }
        }
        // one scoped write keeps the timing choice and selected ratios in the same revision
        scope.preferences = result
        let fingerprint = result.glucoseObservationFingerprint
        if scope.isDraft {
            Self.draftAcknowledgements.setObject((context() + fingerprint) as NSString, forKey: scope)
        } else {
            defaults.set(fingerprint, forKey: acknowledgementKey)
        }
        pending = nil
        refresh()
        return true
    }
}

extension SmbDeliveryRatioSuggestion.Field {
    var keyPath: WritableKeyPath<Preferences, Decimal> {
        switch self {
        case .fixed: return \.smbDeliveryRatio
        case .minimum: return \.smbDeliveryRatioMin
        case .maximum: return \.smbDeliveryRatioMax
        }
    }
}
