import Foundation

/// Content states of the Home multi-use panel; highest priority wins.
/// The adjustment sub-state is part of the value so that every visible
/// change is a structural change (distinct switch branch) — transitions
/// key off view identity, no stringly `.id` needed.
enum MultiUsePanelState: Equatable {
    enum ActiveAdjustment: Equatable {
        case dual
        case override
        case tempTarget
        case profile
    }

    case bolusProgress
    case notificationsDisabled
    case pumpTimeMismatch
    case cgmStale
    case maxIOBZero
    case tidepoolLoginRequired
    case adjustments(ActiveAdjustment)
    case whatsNew
    case dosingModeLimited(DosingMode)
    case stats

    /// readings older than this offer manual glucose entry
    static let cgmStaleAfter: TimeInterval = 12 * 60

    static func resolve(
        bolusInProgress: Bool,
        notificationsDisabled: Bool,
        pumpTimeMismatch: Bool,
        lastGlucoseDate: Date?,
        maxIOB: Decimal,
        tidepoolLoginRequired: Bool,
        hasOverride: Bool,
        hasTempTarget: Bool,
        hasTempProfile: Bool,
        hasUnacknowledgedReleaseNotes: Bool,
        dosingMode: DosingMode,
        now: Date
    ) -> MultiUsePanelState {
        if bolusInProgress { return .bolusProgress }
        if notificationsDisabled { return .notificationsDisabled }
        if pumpTimeMismatch { return .pumpTimeMismatch }
        if now.timeIntervalSince(lastGlucoseDate ?? .distantPast) > cgmStaleAfter { return .cgmStale }
        // constrained modes clamp Max IOB to 0 without touching the stored value
        if dosingMode.automation == .reductionsOnly || dosingMode.automation == .hypoSuspendOnly {
            return .dosingModeLimited(dosingMode)
        }
        if maxIOB <= 0 { return .maxIOBZero }
        // Uploads only, so it yields to every dosing-related warning above.
        if tidepoolLoginRequired { return .tidepoolLoginRequired }
        if hasOverride, hasTempTarget { return .adjustments(.dual) }
        if hasOverride { return .adjustments(.override) }
        if hasTempTarget { return .adjustments(.tempTarget) }
        // temporary (expiring) profiles always surface; indefinite ones only
        // via the stats-face setting
        if hasTempProfile { return .adjustments(.profile) }
        // Informational, so it yields to every warning and adjustment above but still
        // displaces the stats.
        if hasUnacknowledgedReleaseNotes { return .whatsNew }
        return .stats
    }
}
