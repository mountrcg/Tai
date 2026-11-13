import CoreData
import SwiftUI

// MARK: - Zone E: bottom controls (adjustment panel / bolus progress / stats + info buttons)

extension Home.RootView {
    var bolusProgressFormatter: NumberFormatter {
        Formatter.bolusProgressFormatter(for: state.bolusIncrement)
    }

    var overrideString: (text: String, spoken: String)? {
        guard let latestOverride = latestOverride.first else {
            return nil
        }

        guard let settingsManager = state.settingsManager else {
            return nil
        }

        let percent = latestOverride.percentage
        let percentString = percent == 100 ? "" : (percent / 100).formatted(.wholePercent)

        let unit = state.units
        let target = (latestOverride.target ?? 0) as Decimal

        var targetString = target == 0 ? "" : target.formatted(withUnits: unit)
        if tempTargetString != nil {
            targetString = ""
        }

        let date = latestOverride.date ?? Date()
        let remaining = Duration(minutes: (latestOverride.duration ?? 0) as Decimal) + .seconds(date.timeIntervalSinceNow)
        let indefinite = latestOverride.indefinite
        var durationLabel = (text: "", spoken: "")

        if !indefinite {
            if remaining > .zero {
                durationLabel = (
                    remaining.formattedTimeSpan(.largestTwoUnits),
                    remaining.formattedSpokenTimeSpan(.largestTwoUnits)
                )
            } else {
                /// Do not show the Override anymore
                Task {
                    guard let objectID = self.latestOverride.first?.objectID else { return }
                    await state.cancelOverride(withID: objectID)
                }
            }
        }

        let smbScheduleString = latestOverride
            .smbIsScheduledOff && ((latestOverride.start?.stringValue ?? "") != (latestOverride.end?.stringValue ?? ""))
            ? " \(formatTimeRange(start: latestOverride.start?.stringValue, end: latestOverride.end?.stringValue))"
            : ""

        let smbToggleString = latestOverride.smbIsOff || latestOverride
            .smbIsScheduledOff ? String(
                localized: "SMBs Off\(smbScheduleString)",
                comment: "Override subtitle fragment on Home showing that SMBs are disabled — interpolated value is an optional time-range like ' 08:00-10:00'"
            ) : ""

        var smbMinuteLabel = (text: "", spoken: "")
        var uamMinuteLabel = (text: "", spoken: "")

        if !latestOverride.smbIsOff, latestOverride.advancedSettings {
            if let smbMinutes = latestOverride.smbMinutes?.decimalValue,
               smbMinutes != settingsManager.preferences.maxSMBBasalMinutes
            {
                let span = Duration(minutes: smbMinutes)
                smbMinuteLabel = (
                    "SMB\u{00A0}" + span.formattedTimeSpan(.minutes),
                    "SMB\u{00A0}" + span.formattedSpokenTimeSpan(.minutes)
                )
            }

            if let uamMinutes = latestOverride.uamMinutes?.decimalValue,
               uamMinutes != settingsManager.preferences.maxUAMSMBBasalMinutes
            {
                let span = Duration(minutes: uamMinutes)
                uamMinuteLabel = (
                    "UAM\u{00A0}" + span.formattedTimeSpan(.minutes),
                    "UAM\u{00A0}" + span.formattedSpokenTimeSpan(.minutes)
                )
            }
        }

        let otherComponents = [percentString, targetString, smbToggleString]
        let components = ([durationLabel.text] + otherComponents + [smbMinuteLabel.text, uamMinuteLabel.text])
            .filter { !$0.isEmpty }
        let spokenComponents = ([durationLabel.spoken] + otherComponents + [smbMinuteLabel.spoken, uamMinuteLabel.spoken])
            .filter { !$0.isEmpty }

        guard !components.isEmpty else { return nil }
        return (components.joined(separator: ", "), spokenComponents.joined(separator: ", "))
    }

    var tempTargetString: (text: String, spoken: String)? {
        guard let latestTempTarget = latestTempTarget.first else {
            return nil
        }
        let date = latestTempTarget.date ?? Date()
        let remaining = Duration(minutes: (latestTempTarget.duration ?? 0) as Decimal) + .seconds(date.timeIntervalSinceNow)
        var durationString = ""
        var spokenDurationString = ""
        var percentageString = ""
        let target = (latestTempTarget.target ?? 100) as Decimal
        // Use TempTargetCalculations to get effective HBT (handles both custom and auto-adjusted standard TT)
        let effectiveHBT = TempTargetCalculations.computeEffectiveHBT(
            tempTargetHalfBasalTarget: latestTempTarget.halfBasalTarget?.decimalValue,
            settingHalfBasalTarget: state.settingHalfBasalTarget,
            target: target,
            autosensMax: state.autosensMax
        ) ?? state.settingHalfBasalTarget
        var showPercentage = false
        if target > 100, state.highTTraisesSens { showPercentage = true }
        if target < 100, state.lowTTlowersSens, state.autosensMax > 1 { showPercentage = true }
        if showPercentage {
            let percentage = TempTargetCalculations.computeAdjustedPercentage(
                halfBasalTarget: effectiveHBT,
                target: target,
                autosensMax: state.autosensMax
            )
            percentageString = " " + (percentage / 100).formatted(.wholePercent)
        }
        let targetString = target == 0 ? "" : target.formatted(withUnits: state.units) + percentageString

        if remaining > .zero {
            durationString = remaining.formattedTimeSpan(.largestTwoUnits)
            spokenDurationString = remaining.formattedSpokenTimeSpan(.largestTwoUnits)
        } else {
            /// Do not show the Temp Target anymore
            Task {
                guard let objectID = self.latestTempTarget.first?.objectID else { return }
                await state.cancelTempTarget(withID: objectID)
            }
        }

        let components = [targetString, durationString].filter { !$0.isEmpty }
        let spokenComponents = [targetString, spokenDurationString].filter { !$0.isEmpty }

        guard !components.isEmpty else { return nil }
        return (components.joined(separator: ", "), spokenComponents.joined(separator: ", "))
    }

    /// Zone E: one fixed slot. The multi-use panel shows the highest-priority
    /// content — bolus progress, warnings, active adjustment, stats face —
    /// with the alarms pill at the trailing edge.
    @ViewBuilder func bottomControls() -> some View {
        HStack(spacing: 8) {
            multiUsePanel()
                .frame(maxWidth: .infinity)

            alarmsPill
        }
        .frame(height: HomeLayout.bottomPanelHeight)
        .padding(.horizontal, HomeLayout.bottomPanelHorizontalPadding)
        .padding(.top, HomeLayout.bottomZoneTopPadding)
        .padding(.bottom, HomeLayout.bottomZoneBottomPadding)
    }

    /// Bell button; the remaining snooze minutes replace the plain icon while snoozed.
    @ViewBuilder var alarmsPill: some View {
        // timerDate keeps the countdown ticking
        // measure from now, so calculation is not based off stale tick date
        // cf. https://github.com/nightscout/Trio/issues/1381
        let isSnoozed = state.alarmsSnoozeUntil > state.timerDate
        let remainingMinutes = max(Int(ceil(state.alarmsSnoozeUntil.timeIntervalSince(max(state.timerDate, Date())) / 60)), 0)

        Button {
            showSnoozeSheet = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSnoozed ? "bell.slash.fill" : "bell.fill")
                    .font(.system(size: 19))
                if isSnoozed {
                    Text("\(remainingMinutes) m")
                        .font(.footnote).fontWeight(.bold).fontDesign(.rounded)
                }
            }
            .foregroundStyle(isSnoozed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .frame(minWidth: HomeLayout.bottomPanelHeight)
            // full slot height, congruent with the multi-use panel beside it
            .frame(height: HomeLayout.bottomPanelHeight)
            .padding(.horizontal, isSnoozed ? 8 : 0)
            .glassPanel(strokeOpacity: 0.15)
            // glassEffect does not extend the hit area; make the whole pill tappable
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Alarms"))
        .accessibilityValue(Text(
            isSnoozed
                ? String(
                    format: String(localized: "snoozed, %d minutes remaining", comment: "Accessibility: alarm snooze"),
                    remainingMinutes
                )
                : String(localized: "active", comment: "Accessibility: alarms active")
        ))
        .accessibilityHint(Text(String(localized: "Opens snooze options", comment: "Accessibility hint")))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Multi-use panel (stats banner / prioritized warnings)

    /// Active adjustment worth surfacing: override, temp target, or — only
    /// when the user actually maintains several — the active profile.
    var hasActiveAdjustment: Bool {
        overrideString != nil || tempTargetString != nil
            || activeProfile.first?.expiresAt != nil
    }

    var multiUsePanelState: MultiUsePanelState {
        MultiUsePanelState.resolve(
            bolusInProgress: state.bolusProgress != nil,
            notificationsDisabled: notificationsDisabled,
            pumpTimeMismatch: state.pumpStatusBadgeImage != nil,
            lastGlucoseDate: state.glucoseFromPersistence.last?.date,
            maxIOB: state.maxIOB,
            hasOverride: overrideString != nil,
            hasTempTarget: tempTargetString != nil,
            hasTempProfile: activeProfile.first?.expiresAt != nil,
            hasUnacknowledgedReleaseNotes: releaseNotesService.hasUnacknowledgedNotes,
            dosingMode: state.dosingMode,
            now: state.timerDate
        )
    }

    /// One icon for the displaced adjustment while a warning owns the panel:
    /// override wins over temp target, temp target over profile.
    @ViewBuilder var adjustmentIndicator: some View {
        if hasActiveAdjustment {
            Button {
                // land on the sub-tab matching the shown icon
                let tab: Adjustments.Tab = overrideString != nil ? .overrides
                    : tempTargetString != nil ? .tempTargets : .profiles
                UserDefaults.standard.set(tab.rawValue, forKey: Adjustments.pendingTabKey)
                selectedTab = 3
            } label: {
                if overrideString != nil {
                    Image(systemName: "clock.arrow.2.circlepath")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.primary, Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569))
                } else if tempTargetString != nil {
                    Image(systemName: "arrow.up.circle.badge.clock")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.primary, Color.loopGreen)
                } else {
                    // Tai's boxed profile badge, miniature
                    Image(systemName: "person.2", variableValue: 0.58)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.blue, Color.white, Color.white)
                        .font(.system(size: 12, weight: .regular))
                        .frame(width: 21, height: 21)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.blue, lineWidth: 1.5)
                        )
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(Text("Active adjustment"))
        }
    }

    @ViewBuilder func adjustmentIcon(_ systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(Circle().fill(tint.opacity(0.18)))
            .accessibilityHidden(true)
    }

    /// Shared chrome for the non-stats panel states.
    @ViewBuilder func panelBanner(
        systemImage: String,
        title: String,
        subtitle: String,
        tint: Color,
        isCritical: Bool = false,
        tintOpacity: Double? = nil,
        strokeOpacity: Double? = nil,
        strokeWidth: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 12) {
                    adjustmentIcon(systemImage, tint: tint)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.callout).fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    adjustmentIndicator

                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: HomeLayout.bottomPanelHeight)
            .glassPanel(
                tint: tint,
                tintOpacity: tintOpacity ?? (isCritical ? 0.30 : 0.12),
                strokeOpacity: strokeOpacity ?? (isCritical ? 0.8 : 0.35),
                strokeWidth: strokeWidth ?? (isCritical ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One slot, highest-priority state wins; stats is the default face.
    @ViewBuilder func multiUsePanel() -> some View {
        Group {
            switch multiUsePanelState {
            case .bolusProgress:
                if let progress = state.bolusProgress {
                    bolusProgressView(progress)
                        .transition(.blurReplace)
                }
            case .adjustments(.profile):
                adjustmentView()
                    .transition(.blurReplace)
            case .adjustments(.dual):
                adjustmentView()
                    .transition(.blurReplace)
            case .adjustments(.override):
                adjustmentView()
                    .transition(.blurReplace)
            case .adjustments(.tempTarget):
                adjustmentView()
                    .transition(.blurReplace)
            case .notificationsDisabled:
                panelBanner(
                    systemImage: "bell.slash.fill",
                    title: String(localized: "Notifications Disabled"),
                    subtitle: String(localized: "Alarms cannot alert you. Tap to fix."),
                    tint: .red,
                    isCritical: true
                ) {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                }
                .transition(.blurReplace)
            case .pumpTimeMismatch:
                panelBanner(
                    systemImage: "clock.badge.exclamationmark.fill",
                    title: String(localized: "Time Change Detected"),
                    subtitle: String(localized: "Pump clock differs from phone. Tap to review."),
                    tint: .orange
                ) {
                    if state.pumpDisplayState != nil {
                        state.shouldDisplayPumpSetupSheet.toggle()
                    }
                }
                .transition(.blurReplace)
            case .cgmStale:
                panelBanner(
                    systemImage: "drop.fill",
                    title: String(localized: "No Recent Glucose"),
                    subtitle: String(localized: "Tap to add a fingerstick reading."),
                    tint: .orange
                ) {
                    showManualGlucose = true
                }
                .transition(.blurReplace)
            case .maxIOBZero:
                panelBanner(
                    systemImage: "exclamationmark.triangle.fill",
                    title: String(localized: "Max IOB is 0 U"),
                    subtitle: String(localized: "Automated dosing is limited. Tap to review."),
                    tint: .orange
                ) {
                    openMaxIOBSetting()
                }
                .transition(.blurReplace)
            case .whatsNew:
                panelBanner(
                    systemImage: "sparkles",
                    title: String(
                        localized: "New Release v\(releaseNotesService.notes?.version ?? "")",
                        comment: "Home panel title offering the release notes; the placeholder is a version number"
                    ),
                    subtitle: String(localized: "See what's new in this version."),
                    tint: .insulin,
                    tintOpacity: 0.24,
                    strokeOpacity: 0.7,
                    strokeWidth: 1.5
                ) {
                    showReleaseNotes = true
                }
                .transition(.blurReplace)
            case let .dosingModeLimited(mode):
                panelBanner(
                    systemImage: mode.icon,
                    title: mode.displayName,
                    subtitle: mode.miniHint,
                    tint: .orange
                ) {
                    openDosingModeSetting()
                }
                .transition(.blurReplace)
            case .stats:
                // The face setting can put the (indefinite) profile card here.
                if state.settingsManager?.settings.homeStatsPanelFace == .profile, activeProfile.first != nil {
                    adjustmentView()
                        .transition(.blurReplace)
                } else {
                    statsBanner()
                        .transition(.blurReplace)
                }
            }
        }
        // Branch changes ARE identity changes here (each case is a distinct
        // view type/position), so transitions fire without a stringly .id —
        // which corrupted SwiftUI's trait storage and crashed.
        .animation(
            .easeInOut(duration: multiUsePanelState == .bolusProgress ? 0.25 : 0.7),
            value: multiUsePanelState
        )
    }

    /// The mode picker sits on the Settings root, so there is no sub-screen target to push.
    func openDosingModeSetting() {
        selectedTab = 3
    }

    func openMaxIOBSetting() {
        // same target search results push, so scroll + highlight wiggle match
        selectedTab = 4
        settingsPath.append(SearchResultTarget(
            screen: .unitsAndLimits,
            scrollLabel: "Maximum Insulin on Board (IOB)".localized
        ))
    }

    func statsDistributionBar(_ segments: [(color: Color, fraction: CGFloat)]) -> some View {
        GeometryReader { g in
            let spacing: CGFloat = 2
            let shown = segments.filter { $0.fraction > 0.005 }
            let available = max(g.size.width - spacing * CGFloat(max(shown.count - 1, 0)), 0)
            HStack(spacing: spacing) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, segment in
                    Capsule()
                        .fill(segment.color)
                        .frame(width: available * segment.fraction)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func gmiString(_ meanGlucose: Double?) -> String {
        guard let mean = meanGlucose else { return "--" }
        let gmiPercentage = 3.31 + 0.02392 * mean
        // settingsManager is injected after first render; default until then
        if state.settingsManager?.settings.eA1cDisplayUnit == .mmolMol {
            let gmiMmolMol = (gmiPercentage - 2.152) * 10.929
            return "\(Int(gmiMmolMol.rounded())) mmol/mol"
        }
        return (gmiPercentage / 100).formatted(.oneDecimalPercent)
    }

    @ViewBuilder func statsBanner() -> some View {
        let face = state.settingsManager?.settings.homeStatsPanelFace ?? .timeInRange
        let range = state.homeStatsPanelRange
        let stats = state.statsPanelStats
        let hasData = stats.hasData
        let averageString = stats.meanGlucose?.formatted(withUnits: state.units) ?? "--"
        let gmiValueString = gmiString(stats.meanGlucose)
        let tirString = hasData
            ? (stats.inRangePct / 100).formatted(.upToOneDecimalPercent)
            : "--"
        let segments: [(color: Color, fraction: CGFloat)] = hasData ? [
            (.red, CGFloat(stats.veryLowPct / 100)),
            (.orange, CGFloat(stats.lowPct / 100)),
            (.loopGreen, CGFloat(stats.inRangePct / 100)),
            (.purple, CGFloat((stats.highPct + stats.veryHighPct) / 100))
        ] : [(Color.secondary.opacity(0.3), 1)]

        Button {
            // Tai: jump to the 24h glucose statistics, not the daily overview.
            appState.statSelectedViewType = .glucose
            appState.statSelectedInsulinTimeInterval = .day
            state.showModal(for: .statistics)
        } label: {
            ZStack {
                HStack(alignment: .center, spacing: 12) {
                    switch face {
                    case .profile,
                         .timeInRange:
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(tirString)
                                    .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                                    .foregroundStyle(.primary)
                                // chart shows 72h; make the reported scope explicit
                                (
                                    Text("Time in Range", comment: "Stats banner subtitle").fontWeight(.semibold)
                                        + Text(" ")
                                        + Text(range.scopeName)
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            }

                            statsDistributionBar(segments)
                                .frame(height: 6)
                        }
                    case .distributionBar:
                        VStack(alignment: .leading, spacing: 6) {
                            (
                                Text("Time in Range", comment: "Stats banner subtitle").fontWeight(.semibold)
                                    + Text(" ")
                                    + Text(range.scopeName)
                            )
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                            statsDistributionBar(segments)
                                .frame(height: 6)
                        }
                    case .averages:
                        VStack(alignment: .leading, spacing: 6) {
                            // "⌀" read as a diameter sign, so spell the label out (#1474)
                            (
                                Text("Avg. Glucose:", comment: "Stats banner label")
                                    + Text(" \(averageString) \u{00B7} GMI \(gmiValueString)")
                            )
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            Text(range.averageSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    case .hidden:
                        Text("View Statistics", comment: "Stats banner hidden face")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: HomeLayout.bottomPanelHeight)
            .glassPanel()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder func adjustmentsOverrideView(_ overrideString: (text: String, spoken: String)) -> some View {
        HStack {
            Image(systemName: "clock.arrow.2.circlepath")
                .font(.title2)
                .foregroundStyle(Color.primary, Color.purple)
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(latestOverride.first?.name ?? String(
                    localized: "Custom Override",
                    comment: "Fallback name on Home adjustments banner for an active override without a name"
                ))
                    .font(.subheadline)
                    .frame(alignment: .leading)

                Text(overrideString.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(overrideString.spoken)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            UserDefaults.standard.set(Adjustments.Tab.overrides.rawValue, forKey: Adjustments.pendingTabKey)
            selectedTab = 3
        }
    }

    @ViewBuilder func adjustmentsTempTargetView(_ tempTargetString: (text: String, spoken: String)) -> some View {
        HStack {
            let targetValue = latestTempTarget.first?.target?.doubleValue ?? 0.0
            let rotationValue: Double = targetValue < 100 ? 180 : 0
            Image(systemName: "arrow.up.circle.badge.clock")
                .rotationEffect(.degrees(rotationValue))
                .font(.system(size: 22))
                .foregroundStyle(Color.primary, Color.loopGreen)
                .frame(width: 28)
            VStack(alignment: .leading) {
                Text(latestTempTarget.first?.name ?? String(
                    localized: "Temp Target",
                    comment: "Fallback name on Home adjustments banner for an active temp target without a name"
                ))
                    .font(.subheadline)
                    .frame(alignment: .leading)
                Text(tempTargetString.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(tempTargetString.spoken)
                    .frame(alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            UserDefaults.standard.set(Adjustments.Tab.tempTargets.rawValue, forKey: Adjustments.pendingTabKey)
            selectedTab = 3
        }
    }

    @ViewBuilder func adjustmentsProfileView(_ profile: ProfileStored) -> some View {
        // Wider gap than OR/TT: the badge box has a hard edge, glyphs have air.
        HStack(spacing: 12) {
            Group {
                if profile.expiresAt != nil {
                    Image(systemName: "person.2.arrow.trianglehead.counterclockwise")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.primary, Color.blue)
                } else {
                    Image(systemName: "person.2", variableValue: 0.58)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.blue, Color.white, Color.white)
                        .font(.system(size: 14, weight: .regular))
                        .frame(width: 24, height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.blue, lineWidth: 1.5)
                        )
                }
            }
            .frame(width: 28)
            VStack(alignment: .leading) {
                Text(profile.name ?? String(
                    localized: "Active Profile",
                    comment: "Fallback name on Home adjustments banner for the active profile when it has no name set"
                ))
                    .font(.subheadline)
                    .frame(alignment: .leading)
                let subtitle = profileSubtitle(profile, now: state.timerDate)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            // Profiles live in the Adjustments tab (tag 3) as the third sub-tab next
            // to Overrides and Temp Targets. We can't reach AdjustmentsRootView's local
            // tab state directly, so we leave a flag in UserDefaults that the view
            // consumes on its next .onAppear.
            UserDefaults.standard.set(Adjustments.Tab.profiles.rawValue, forKey: Adjustments.pendingTabKey)
            selectedTab = 3
        }
    }

    /// Subtitle is recomputed against `state.timerDate` — the 5-second tick from
    /// HomeStateModel — so the countdown stays live without an ad-hoc timer.
    /// Same mechanism PumpView / LoopView use for their remaining-time displays.
    private func profileSubtitle(_ profile: ProfileStored, now: Date) -> String {
        var parts: [String] = []
        if let expires = profile.expiresAt {
            let minutesLeft = Int(expires.timeIntervalSince(now) / 60)
            let countdown = minutesLeft > 0 ? Duration.seconds(TimeInterval(minutesLeft) * 60).formattedTimeSpan(.largestTwoUnits) : String(
                localized: "Expiring",
                comment: "Countdown text on Home profile banner when less than a minute of a timed activation remains"
            )
            parts.append(countdown)
        }
        parts += ProfileSummaryLabel.strings(
            appliedPercent: profile.appliedPercent?.decimalValue,
            dailyBasalRate: profile.therapy?.basalProfile.totalDailyBasal,
            tuning: profileTuning(for: profile)
        )
        return parts.joined(separator: " · ")
    }

    /// Compares the profile's current prefs + glucose targets against its source to build
    /// the standard tuning badge. Returns `.none` if no source linkage exists.
    private func profileTuning(for profile: ProfileStored) -> ProfileSummaryLabel.Tuning {
        guard let sourceID = profile.sourceProfileID,
              let context = profile.managedObjectContext
        else { return .none }
        let req = ProfileStored.fetch(.profileByID(sourceID), fetchLimit: 1)
        guard let source = try? context.fetch(req).first else { return .none }
        let prefs: Bool = {
            guard let sp = source.preferences, let pp = profile.preferences else { return false }
            return pp != sp
        }()
        let targets: Bool = {
            guard let st = source.therapy?.bgTargets, let pt = profile.therapy?.bgTargets else { return false }
            return pt.targets != st.targets
        }()
        return ProfileSummaryLabel.Tuning(preferencesTuned: prefs, targetsTuned: targets)
    }

    @ViewBuilder func adjustmentsRevertProfileView() -> some View {
        Image(systemName: "xmark.app")
            .font(.system(size: 24))
            .foregroundStyle(Color.primary, Color.blue)
            .glassActionSheet(
                "Revert to previous profile?",
                isPresented: $isConfirmRevertProfilePresented,
                actions: [
                    GlassSheetAction("Revert", role: .destructive) {
                        Task { await state.revertActiveProfile() }
                    }
                ]
            )
            .onTapGesture {
                isConfirmRevertProfilePresented = true
            }
    }

    @ViewBuilder func adjustmentsCancelView(_ cancelAction: @escaping () -> Void) -> some View {
        Image(systemName: "xmark.app")
            .font(.system(size: 24))
            .foregroundStyle(
                Color.loopGreen,
                Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569)
            )
            .onTapGesture {
                cancelAction()
            }
            .accessibilityLabel(Text("Stop adjustment"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { cancelAction() }
    }

    @ViewBuilder func adjustmentsCancelTempTargetView() -> some View {
        Image(systemName: "xmark.app")
            .font(.system(size: 24))
            .foregroundStyle(Color.primary, Color.loopGreen)
            .glassActionSheet(
                "Stop the Temp Target \"\(latestTempTarget.first?.name ?? "")\"?",
                isPresented: $isConfirmStopTempTargetShown,
                actions: [
                    GlassSheetAction("Stop", role: .destructive) {
                        Task {
                            guard let objectID = latestTempTarget.first?.objectID else { return }
                            await state.cancelTempTarget(withID: objectID)
                        }
                    }
                ]
            )
            .onTapGesture {
                if !latestTempTarget.isEmpty {
                    isConfirmStopTempTargetShown = true
                }
            }
            .accessibilityLabel(Text("Stop temp target"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if !latestTempTarget.isEmpty {
                    isConfirmStopTempTargetShown = true
                }
            }
    }

    @ViewBuilder func adjustmentsCancelOverrideView() -> some View {
        Image(systemName: "xmark.app")
            .font(.system(size: 24))
            .foregroundStyle(Color.primary, Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569))
            .glassActionSheet(
                "Stop the Override \"\(latestOverride.first?.name ?? "")\"?",
                isPresented: $isConfirmStopOverridePresented,
                actions: [
                    GlassSheetAction("Stop", role: .destructive) {
                        Task {
                            guard let objectID = latestOverride.first?.objectID else { return }
                            await state.cancelOverride(withID: objectID)
                        }
                    }
                ]
            )
            .onTapGesture {
                if !latestOverride.isEmpty {
                    isConfirmStopOverridePresented = true
                }
            }
            .accessibilityLabel(Text("Stop override"))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if !latestOverride.isEmpty {
                    isConfirmStopOverridePresented = true
                }
            }
    }

    @ViewBuilder func noActiveAdjustmentsView() -> some View {
        Group {
            VStack {
                Text("No Active Adjustment")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Profile at \(1.0.formatted(.wholePercent))")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.leading, 10)

            Spacer()

            /// to ensure the same position....
            Image(systemName: "xmark.app")
                .font(.title)
                // clear color for the icon
                .foregroundStyle(Color.clear)
        }.onTapGesture {
            selectedTab = 3
        }
    }

    @ViewBuilder func adjustmentView() -> some View {
//            let background = colorScheme == .dark ? Material.ultraThinMaterial.opacity(0.5) : Color.black.opacity(0.2)

        let profileToShow: ProfileStored? = {
            guard overrideString == nil, tempTargetString == nil else { return nil }
            return activeProfile.first
        }()

        // Thin border in the state's color, same style as the multi-use panel.
        let cardTint: Color? = overrideString != nil
            ? Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569)
            : tempTargetString != nil ? Color.loopGreen
            : profileToShow != nil ? Color.blue : nil

        ZStack {
            HStack {
                if let overrideString = overrideString, let tempTargetString = tempTargetString {
                    HStack {
                        adjustmentsOverrideView(overrideString)

                        Spacer()

                        Divider()
                            .frame(height: HomeLayout.bottomPanelHeight - 16)
                            .padding(.horizontal, 2)

                        adjustmentsTempTargetView(tempTargetString)

                        Spacer()

                        adjustmentsCancelView({
                            if !latestTempTarget.isEmpty, !latestOverride.isEmpty {
                                showCancelConfirmDialog = true
                            } else if !latestOverride.isEmpty {
                                showCancelAlert = true
                            } else if !latestTempTarget.isEmpty {
                                showCancelAlert = true
                            }
                        })
                    }
                } else if let overrideString = overrideString {
                    adjustmentsOverrideView(overrideString)
                    Spacer()
                    adjustmentsCancelOverrideView()

                } else if let tempTargetString = tempTargetString {
                    HStack {
                        adjustmentsTempTargetView(tempTargetString)
                        Spacer()
                        adjustmentsCancelTempTargetView()
                    }
                } else if let profile = profileToShow {
                    HStack {
                        adjustmentsProfileView(profile)
                        Spacer()
                        if profile.expiresAt != nil, profile.previousProfileID != nil {
                            adjustmentsRevertProfileView()
                        }
                    }
                } else {
                    noActiveAdjustmentsView()
                }
            }.padding(.horizontal, 10)
                .glassActionSheet(
                    "Adjustment to Stop",
                    message: Text("Select Adjustment"),
                    isPresented: $showCancelConfirmDialog,
                    actions: [
                        GlassSheetAction("Stop Override", role: .destructive) {
                            Task {
                                guard let objectID = latestOverride.first?.objectID else { return }
                                await state.cancelOverride(withID: objectID)
                            }
                        },
                        GlassSheetAction("Stop Temp Target", role: .destructive) {
                            Task {
                                guard let objectID = latestTempTarget.first?.objectID else { return }
                                await state.cancelTempTarget(withID: objectID)
                            }
                        },
                        GlassSheetAction("Stop All Adjustments", role: .destructive) {
                            Task {
                                guard let overrideObjectID = latestOverride.first?.objectID else { return }
                                await state.cancelOverride(withID: overrideObjectID)

                                guard let tempTargetObjectID = latestTempTarget.first?.objectID else { return }
                                await state.cancelTempTarget(withID: tempTargetObjectID)
                            }
                        }
                    ]
                )
        }
        .frame(height: HomeLayout.bottomPanelHeight)
        // Neutral glass like the stats face; the state color survives only as
        // the slight border.
        .glassPanel(tint: cardTint, tintOpacity: 0, strokeOpacity: cardTint == nil ? 0.08 : 0.35)
    }

    @ViewBuilder func bolusProgressBar(_ progress: Decimal) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 15)
                .frame(height: 6)
                .foregroundColor(.clear)
                .background(
                    TaiStyle.linearGradient(
                        startPoint: .trailing,
                        endPoint: .leading
                    )
                    .mask(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 15)
                            .frame(width: geo.size.width * CGFloat(progress))
                    }
                )
        }
    }

    @ViewBuilder func bolusProgressView(_ progress: Decimal) -> some View {
        /// ensure that state.lastPumpBolus has a value, i.e. there is a last bolus done by the pump and not an external bolus
        /// - TRUE:  show the pump bolus
        /// - FALSE:  do not show a progress bar at all
        if let bolusTotal = state.lastPumpBolus?.bolus?.amount {
            let bolusFraction = progress * (bolusTotal as Decimal)
            let bolusString =
                (bolusProgressFormatter.string(from: bolusFraction as NSNumber) ?? "0")
                    + String(localized: " of ", comment: "Bolus string partial message: 'x U of y U' in home view") +
                    (bolusProgressFormatter.string(from: bolusTotal as NSNumber) ?? "0")
                    + String(localized: " U", comment: "Insulin unit")
            let bolusLabel = state
                .bolusStatus == .inProgress ? String(localized: "Bolusing") : String(localized: "Initiating…")

            ZStack {
                /// actual bolus view
                HStack {
                    Image("bolus")
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 25, height: 25)
                        .foregroundColor(Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902))
                        .accessibilityHidden(true)

                    Spacer()
                    Group {
                        Text(bolusLabel)
                            .font(.subheadline)
                        Text(bolusString)
                            .font(.subheadline)
                    }.padding(.leading, 5)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(bolusLabel))
                        .accessibilityValue(Text(bolusString))

                    Spacer()

                    if state.bolusStatus == .inProgress {
                        Button {
                            state.showProgressView()
                            state.cancelBolus()
                        } label: {
                            Image(systemName: "xmark.app")
                                .font(.system(size: 25))
                                .foregroundStyle(
                                    Color.primary,
                                    Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902)
                                )
                        }
                        .accessibilityLabel(Text("Cancel bolus"))
                    } else if state.bolusStatus == .initiating {
                        ProgressView()
                    }
                }.padding(.horizontal, 10)
            }
            .frame(height: HomeLayout.bottomPanelHeight)
            .glassPanel(tint: .insulin, tintOpacity: 0.18, strokeOpacity: 0.30)
            .overlay(alignment: .bottom) {
                let offset = HomeLayout.bottomPanelHeight * 0.75
                bolusProgressBar(progress)
                    .padding(.leading, 42)
                    .padding(.trailing, 50)
                    .offset(y: offset)
            }.clipShape(GlassChrome.panelShape)
        }
    }
}
