import Combine
import Foundation
import Testing

@testable import Trio

@Suite("Multi-Use Panel State Tests") struct MultiUsePanelStateTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var fresh: Date { now.addingTimeInterval(-5 * 60) }
    private var stale: Date { now.addingTimeInterval(-20 * 60) }

    private func resolve(
        bolusInProgress: Bool = false,
        notificationsDisabled: Bool = false,
        pumpTimeMismatch: Bool = false,
        lastGlucoseDate: Date?,
        maxIOB: Decimal = 10,
        garminStall: Bool = false,
        tidepoolLoginRequired: Bool = false,
        hasOverride: Bool = false,
        hasTempTarget: Bool = false,
        hasTempProfile: Bool = false,
        hasUnacknowledgedReleaseNotes: Bool = false,
        dosingMode: DosingMode = .closed
    ) -> MultiUsePanelState {
        MultiUsePanelState.resolve(
            bolusInProgress: bolusInProgress,
            notificationsDisabled: notificationsDisabled,
            pumpTimeMismatch: pumpTimeMismatch,
            lastGlucoseDate: lastGlucoseDate,
            maxIOB: maxIOB,
            garminRestartGuidanceRequired: garminStall,
            tidepoolLoginRequired: tidepoolLoginRequired,
            hasOverride: hasOverride,
            hasTempTarget: hasTempTarget,
            hasTempProfile: hasTempProfile,
            hasUnacknowledgedReleaseNotes: hasUnacknowledgedReleaseNotes,
            dosingMode: dosingMode,
            now: now
        )
    }

    @Test("Constrained modes announce themselves even with a non-zero stored Max IOB") func testDosingModeLimited() {
        for mode in [DosingMode.lowGlucoseSuspend, .basalTesting] {
            #expect(resolve(lastGlucoseDate: fresh, maxIOB: 10, dosingMode: mode) == .dosingModeLimited(mode))
        }
    }

    @Test("Open and closed loop fall through to the stored Max IOB") func testUnconstrainedModes() {
        for mode in [DosingMode.closed, .open] {
            #expect(resolve(lastGlucoseDate: fresh, maxIOB: 10, dosingMode: mode) == .stats)
            #expect(resolve(lastGlucoseDate: fresh, maxIOB: 0, dosingMode: mode) == .maxIOBZero)
        }
    }

    @Test("A stale CGM still outranks the mode banner") func testCgmStaleOutranksMode() {
        #expect(resolve(lastGlucoseDate: stale, dosingMode: .lowGlucoseSuspend) == .cgmStale)
    }

    @Test("All healthy shows stats") func testStatsDefault() {
        #expect(resolve(lastGlucoseDate: fresh) == .stats)
    }

    @Test("Missing notifications outranks everything") func testNotificationsTop() {
        #expect(resolve(
            notificationsDisabled: true,
            pumpTimeMismatch: true,
            lastGlucoseDate: nil,
            maxIOB: 0
        ) == .notificationsDisabled)
    }

    @Test("Pump time mismatch outranks CGM and MaxIOB") func testTimeMismatchSecond() {
        #expect(resolve(pumpTimeMismatch: true, lastGlucoseDate: nil, maxIOB: 0) == .pumpTimeMismatch)
    }

    @Test("Stale glucose outranks MaxIOB") func testCgmStaleThird() {
        #expect(resolve(lastGlucoseDate: stale, maxIOB: 0) == .cgmStale)
    }

    @Test("No glucose at all counts as stale") func testNoGlucoseIsStale() {
        #expect(resolve(lastGlucoseDate: nil) == .cgmStale)
    }

    @Test("Fresh glucose within threshold is not stale") func testFreshGlucose() {
        #expect(resolve(lastGlucoseDate: now.addingTimeInterval(-11 * 60)) == .stats)
    }

    @Test("MaxIOB zero shows its warning") func testMaxIOBZero() {
        #expect(resolve(lastGlucoseDate: fresh, maxIOB: 0) == .maxIOBZero)
    }

    @Test("Bolus in progress beats every warning") func bolusBeatsAll() {
        #expect(resolve(
            bolusInProgress: true,
            notificationsDisabled: true,
            lastGlucoseDate: stale,
            maxIOB: 0,
            hasOverride: true
        ) == .bolusProgress)
    }

    @Test("Adjustments beat stats but not warnings") func adjustmentPriority() {
        #expect(resolve(lastGlucoseDate: fresh, hasTempTarget: true) == .adjustments(.tempTarget))
        #expect(resolve(lastGlucoseDate: stale, hasTempTarget: true) == .cgmStale)
    }

    @Test("Adjustment sub-state precedence") func adjustmentSubState() {
        #expect(resolve(lastGlucoseDate: fresh, hasOverride: true, hasTempTarget: true) == .adjustments(.dual))
        #expect(resolve(lastGlucoseDate: fresh, hasOverride: true) == .adjustments(.override))
        #expect(resolve(lastGlucoseDate: fresh, hasTempProfile: true) == .adjustments(.profile))
        #expect(resolve(lastGlucoseDate: fresh) == .stats)
    }

    @Test("Adjustments outrank release notes") func adjustmentsBeatWhatsNew() {
        #expect(resolve(
            lastGlucoseDate: fresh,
            hasTempTarget: true,
            hasUnacknowledgedReleaseNotes: true
        ) == .adjustments(.tempTarget))
    }

    @Test("Unacknowledged release notes displace the stats") func testWhatsNewOverStats() {
        #expect(resolve(lastGlucoseDate: fresh, hasUnacknowledgedReleaseNotes: true) == .whatsNew)
    }

    @Test("Every warning outranks release notes") func testWhatsNewYieldsToWarnings() {
        #expect(resolve(
            notificationsDisabled: true,
            lastGlucoseDate: fresh,
            hasUnacknowledgedReleaseNotes: true
        ) == .notificationsDisabled)
        #expect(resolve(
            pumpTimeMismatch: true,
            lastGlucoseDate: fresh,
            hasUnacknowledgedReleaseNotes: true
        ) == .pumpTimeMismatch)
        #expect(resolve(lastGlucoseDate: stale, hasUnacknowledgedReleaseNotes: true) == .cgmStale)
        #expect(resolve(
            lastGlucoseDate: fresh,
            maxIOB: 0,
            hasUnacknowledgedReleaseNotes: true
        ) == .maxIOBZero)
    }

    @Test("Acknowledged release notes fall back to stats") func testAcknowledgedShowsStats() {
        #expect(resolve(lastGlucoseDate: fresh, hasUnacknowledgedReleaseNotes: false) == .stats)
    }

    @Test("Tidepool login sits between dosing warnings and release notes") func testTidepoolLoginRequired() {
        #expect(resolve(lastGlucoseDate: fresh, tidepoolLoginRequired: true) == .tidepoolLoginRequired)
        #expect(resolve(
            lastGlucoseDate: fresh,
            tidepoolLoginRequired: true,
            hasUnacknowledgedReleaseNotes: true
        ) == .tidepoolLoginRequired)
        #expect(resolve(lastGlucoseDate: fresh, maxIOB: 0, tidepoolLoginRequired: true) == .maxIOBZero)
        #expect(resolve(lastGlucoseDate: stale, tidepoolLoginRequired: true) == .cgmStale)
    }

    @Test("Garmin guidance yields to bolus progress and every safety warning") func testGarminStallYieldsToEverySafetyState() {
        #expect(resolve(bolusInProgress: true, lastGlucoseDate: fresh, garminStall: true) == .bolusProgress)
        #expect(resolve(notificationsDisabled: true, lastGlucoseDate: fresh, garminStall: true) == .notificationsDisabled)
        #expect(resolve(pumpTimeMismatch: true, lastGlucoseDate: fresh, garminStall: true) == .pumpTimeMismatch)
        #expect(resolve(lastGlucoseDate: stale, garminStall: true) == .cgmStale)
        #expect(resolve(lastGlucoseDate: nil, garminStall: true) == .cgmStale)
        for mode in [DosingMode.lowGlucoseSuspend, .basalTesting] {
            #expect(resolve(lastGlucoseDate: fresh, garminStall: true, dosingMode: mode) == .dosingModeLimited(mode))
        }
        #expect(resolve(lastGlucoseDate: fresh, maxIOB: 0, garminStall: true) == .maxIOBZero)
    }

    @Test(
        "Garmin guidance outranks Tidepool, adjustments, release notes and stats"
    )  func testGarminStallOutranksTidepoolAdjustmentsReleaseNotesAndStats() {
        let cases: [(tidepool: Bool, override: Bool, tempTarget: Bool, profile: Bool, notes: Bool, normal: MultiUsePanelState)] =
            [
                (true, false, false, false, false, .tidepoolLoginRequired),
                (false, true, true, false, false, .adjustments(.dual)),
                (false, true, false, false, false, .adjustments(.override)),
                (false, false, true, false, false, .adjustments(.tempTarget)),
                (false, false, false, true, false, .adjustments(.profile)),
                (false, false, false, false, true, .whatsNew),
                (false, false, false, false, false, .stats)
            ]
        for input in cases {
            for garminStall in [false, true] {
                #expect(resolve(
                    lastGlucoseDate: fresh,
                    garminStall: garminStall,
                    tidepoolLoginRequired: input.tidepool,
                    hasOverride: input.override,
                    hasTempTarget: input.tempTarget,
                    hasTempProfile: input.profile,
                    hasUnacknowledgedReleaseNotes: input.notes
                ) == (garminStall ? .garminStall : input.normal))
            }
        }
    }

    @Test(
        "Garmin guidance returns after a higher warning clears and has no acknowledgement"
    )  func testUnacknowledgedGarminStallResurfacesAfterPreemption() {
        #expect(resolve(lastGlucoseDate: fresh, garminStall: true, hasUnacknowledgedReleaseNotes: true) == .garminStall)
        #expect(resolve(lastGlucoseDate: stale, garminStall: true, hasUnacknowledgedReleaseNotes: true) == .cgmStale)
        #expect(resolve(lastGlucoseDate: fresh, garminStall: true, hasUnacknowledgedReleaseNotes: false) == .garminStall)
        #expect(resolve(lastGlucoseDate: fresh, garminStall: false, hasUnacknowledgedReleaseNotes: true) == .whatsNew)
    }

    @Test("Home routes the Garmin publisher into the panel state") @MainActor  func testHomePanelSelectsGarminStallFromPublisher() async {
        let model = Home.StateModel()
        model.maxIOB = 10
        model.dosingMode = .closed
        model.timerDate = now
        let required = CurrentValueSubject<Bool, Never>(true)
        model.bindGarminRestartGuidance(required.eraseToAnyPublisher())
        let panel = {
            model.resolveMultiUsePanelState(
                lastGlucoseDate: fresh,
                notificationsDisabled: false,
                hasOverride: false,
                hasTempTarget: false,
                hasTempProfile: false,
                hasUnacknowledgedReleaseNotes: false
            )
        }
        await Task.yield()
        #expect(await panelEventually(.garminStall, panel))
        required.send(false)
        #expect(await panelEventually(.stats, panel))
    }

    @MainActor private func panelEventually(
        _ expected: MultiUsePanelState,
        _ panel: () -> MultiUsePanelState
    ) async -> Bool {
        for _ in 0 ..< 50 {
            if panel() == expected { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return panel() == expected
    }
}
