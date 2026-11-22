import Foundation
import Testing

@testable import Trio

@Suite("ProfileSchedule next-fire math") struct ProfileScheduleTests {
    /// UTC calendar is used for cases where timezone shouldn't affect results. DST-sensitive
    /// tests explicitly use Europe/Berlin.
    private static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private static var berlinCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return cal
    }

    /// Helper: build a Date at a specific wall time in a given calendar.
    private static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0,
        in calendar: Calendar
    ) -> Date {
        var comp = DateComponents()
        comp.year = year
        comp.month = month
        comp.day = day
        comp.hour = hour
        comp.minute = minute
        return calendar.date(from: comp)!
    }

    // MARK: - Weekday cases

    @Test("Single weekday at fixed time — returns next occurrence") func testWeekdaySingle() {
        let cal = Self.utcCalendar
        let rule = ProfileScheduleRule(
            repeatRule: .weekdays([.friday]),
            firesAt: [.init(hour: 20, minute: 0)]
        )
        // Wednesday 2026-04-22 12:00 UTC → next Fri is 2026-04-24 20:00.
        let from = Self.date(2026, 4, 22, 12, 0, in: cal)
        let expected = Self.date(2026, 4, 24, 20, 0, in: cal)
        #expect(rule.nextFire(after: from, calendar: cal) == expected)
    }

    @Test("Multiple weekdays — picks the soonest") func testWeekdayMultiple() {
        let cal = Self.utcCalendar
        let rule = ProfileScheduleRule(
            repeatRule: .weekdays([.monday, .wednesday, .friday]),
            firesAt: [.init(hour: 8, minute: 0)]
        )
        // Thursday 2026-04-23 09:00 → next Mon/Wed/Fri is Fri 2026-04-24 08:00.
        let from = Self.date(2026, 4, 23, 9, 0, in: cal)
        let expected = Self.date(2026, 4, 24, 8, 0, in: cal)
        #expect(rule.nextFire(after: from, calendar: cal) == expected)
    }

    @Test("Two firesAt same day — second time of day wins when first is past") func testTwoFiresAtSameDay() {
        let cal = Self.utcCalendar
        let rule = ProfileScheduleRule(
            repeatRule: .weekdays([.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]),
            firesAt: [.init(hour: 8, minute: 0), .init(hour: 20, minute: 0)]
        )
        // Mon 2026-04-20 09:00 → next fire same day 20:00.
        let from = Self.date(2026, 4, 20, 9, 0, in: cal)
        let expected = Self.date(2026, 4, 20, 20, 0, in: cal)
        #expect(rule.nextFire(after: from, calendar: cal) == expected)
    }

    @Test("Empty weekday set — nil") func testWeekdayEmpty() {
        let rule = ProfileScheduleRule(
            repeatRule: .weekdays([]),
            firesAt: [.init(hour: 8, minute: 0)]
        )
        #expect(rule.nextFire(after: Date(), calendar: Self.utcCalendar) == nil)
    }

    @Test("Empty firesAt on recurring rule — nil") func testWeekdayNoTimes() {
        let rule = ProfileScheduleRule(
            repeatRule: .weekdays([.friday]),
            firesAt: []
        )
        #expect(rule.nextFire(after: Date(), calendar: Self.utcCalendar) == nil)
    }

    // MARK: - Monthly-days cases

    @Test("Monthly day 14 — returns this month if future, else next month") func testMonthlyDaySingle() {
        let cal = Self.utcCalendar
        let rule = ProfileScheduleRule(
            repeatRule: .monthlyDays([14]),
            firesAt: [.init(hour: 8, minute: 0)]
        )
        // 2026-04-10 → next is 2026-04-14 08:00.
        let fromEarly = Self.date(2026, 4, 10, 0, 0, in: cal)
        #expect(rule.nextFire(after: fromEarly, calendar: cal) == Self.date(2026, 4, 14, 8, 0, in: cal))

        // 2026-04-14 08:01 → next is 2026-05-14 08:00.
        let fromLate = Self.date(2026, 4, 14, 8, 1, in: cal)
        #expect(rule.nextFire(after: fromLate, calendar: cal) == Self.date(2026, 5, 14, 8, 0, in: cal))
    }

    @Test("Monthly day 31 from Feb — skips Feb (strict matching)") func testMonthlyDay31SkipsFeb() {
        let cal = Self.utcCalendar
        let rule = ProfileScheduleRule(
            repeatRule: .monthlyDays([31]),
            firesAt: [.init(hour: 8, minute: 0)]
        )
        // 2026-02-10 → Feb has no 31st, next is 2026-03-31 08:00.
        let from = Self.date(2026, 2, 10, 0, 0, in: cal)
        let expected = Self.date(2026, 3, 31, 8, 0, in: cal)
        #expect(rule.nextFire(after: from, calendar: cal) == expected)
    }

    @Test("Monthly days 1–5 — cycle-window use case, picks earliest in window") func testMonthlyDaysRange() {
        let cal = Self.utcCalendar
        let rule = ProfileScheduleRule(
            repeatRule: .monthlyDays([1, 2, 3, 4, 5]),
            firesAt: [.init(hour: 6, minute: 0)]
        )
        // 2026-04-02 12:00 — already past 2nd @ 06:00, so next is 3rd @ 06:00.
        let from = Self.date(2026, 4, 2, 12, 0, in: cal)
        let expected = Self.date(2026, 4, 3, 6, 0, in: cal)
        #expect(rule.nextFire(after: from, calendar: cal) == expected)
    }

    @Test("Empty monthlyDays — nil") func testMonthlyDaysEmpty() {
        let rule = ProfileScheduleRule(
            repeatRule: .monthlyDays([]),
            firesAt: [.init(hour: 8, minute: 0)]
        )
        #expect(rule.nextFire(after: Date(), calendar: Self.utcCalendar) == nil)
    }

    // MARK: - Once cases

    @Test("Once in future — returns the date") func testOnceFuture() {
        let cal = Self.utcCalendar
        let target = Self.date(2026, 6, 1, 9, 30, in: cal)
        let rule = ProfileScheduleRule(repeatRule: .once(target), firesAt: [])
        let from = Self.date(2026, 5, 1, 0, 0, in: cal)
        #expect(rule.nextFire(after: from, calendar: cal) == target)
    }

    @Test("Once in past — nil") func testOncePast() {
        let cal = Self.utcCalendar
        let target = Self.date(2026, 1, 1, 0, 0, in: cal)
        let rule = ProfileScheduleRule(repeatRule: .once(target), firesAt: [])
        let from = Self.date(2026, 4, 23, 0, 0, in: cal)
        #expect(rule.nextFire(after: from, calendar: cal) == nil)
    }

    @Test("Once exactly equal to from — nil (strictly after)") func testOnceEqualToFrom() {
        let cal = Self.utcCalendar
        let target = Self.date(2026, 4, 23, 12, 0, in: cal)
        let rule = ProfileScheduleRule(repeatRule: .once(target), firesAt: [])
        #expect(rule.nextFire(after: target, calendar: cal) == nil)
    }

    // MARK: - DST edge case

    @Test("Weekday rule during DST spring-forward — skips to next valid minute") func testDSTSpringForward() {
        // Europe/Berlin: 2026-03-29 02:00 → 03:00 (no 02:30 exists that day).
        let cal = Self.berlinCalendar
        let rule = ProfileScheduleRule(
            repeatRule: .weekdays([.sunday]),
            firesAt: [.init(hour: 2, minute: 30)]
        )
        // From Sat 2026-03-28, next Sunday fire should be either 2026-03-29 (adjusted by
        // Calendar.nextDate's .nextTime policy to the nearest valid wall-time) or skip to next
        // week. Either is defensible; we only assert it's not nil and lands on a Sunday.
        let from = Self.date(2026, 3, 28, 0, 0, in: cal)
        let result = rule.nextFire(after: from, calendar: cal)
        #expect(result != nil)
        if let result {
            #expect(cal.component(.weekday, from: result) == ProfileSchedule.Weekday.sunday.rawValue)
        }
    }

    // MARK: - Every-N-days cases

    private static func everyDaysRule(
        _ intervalDays: Int,
        anchor: Date,
        firesAt: [ProfileSchedule.TimeOfDay] = [.init(hour: 8, minute: 0)]
    ) -> ProfileScheduleRule {
        ProfileScheduleRule(repeatRule: .everyDays(intervalDays: intervalDays, anchor: anchor), firesAt: firesAt)
    }

    @Test("Every 28 days — first fire is the anchor when from precedes it") func testEveryDaysAnchorFirst() {
        let cal = Self.utcCalendar
        let rule = Self.everyDaysRule(28, anchor: Self.date(2026, 1, 5, in: cal))
        let from = Self.date(2026, 1, 1, in: cal)
        #expect(rule.nextFire(after: from, calendar: cal) == Self.date(2026, 1, 5, 8, 0, in: cal))
    }

    @Test("Every 28 days — a missed occurrence does not shift the grid") func testEveryDaysMissedOccurrence() {
        let cal = Self.utcCalendar
        let rule = Self.everyDaysRule(28, anchor: Self.date(2026, 1, 5, in: cal))
        let from = Self.date(2026, 1, 5, 9, 0, in: cal)
        #expect(rule.nextFire(after: from, calendar: cal) == Self.date(2026, 2, 2, 8, 0, in: cal))
    }

    @Test("Every 28 days — mid-interval from") func testEveryDaysMidInterval() {
        let cal = Self.utcCalendar
        let rule = Self.everyDaysRule(28, anchor: Self.date(2026, 1, 5, in: cal))
        let from = Self.date(2026, 1, 20, in: cal)
        #expect(rule.nextFire(after: from, calendar: cal) == Self.date(2026, 2, 2, 8, 0, in: cal))
    }

    @Test("Every 28 days — several intervals after the anchor") func testEveryDaysSeveralIntervals() {
        let cal = Self.utcCalendar
        let rule = Self.everyDaysRule(28, anchor: Self.date(2026, 1, 5, in: cal))
        let from = Self.date(2026, 4, 1, in: cal)
        #expect(rule.nextFire(after: from, calendar: cal) == Self.date(2026, 4, 27, 8, 0, in: cal))
    }

    @Test("Interval 1 — behaves daily") func testEveryDaysIntervalOne() {
        let cal = Self.utcCalendar
        let rule = Self.everyDaysRule(1, anchor: Self.date(2026, 1, 5, in: cal))
        #expect(
            rule.nextFire(after: Self.date(2026, 3, 10, 9, 0, in: cal), calendar: cal) == Self
                .date(2026, 3, 11, 8, 0, in: cal)
        )
        #expect(
            rule.nextFire(after: Self.date(2026, 3, 10, 7, 0, in: cal), calendar: cal) == Self
                .date(2026, 3, 10, 8, 0, in: cal)
        )
    }

    @Test("Interval outside 1…365 — nil") func testEveryDaysIntervalOutOfRange() {
        let cal = Self.utcCalendar
        let anchor = Self.date(2026, 1, 5, in: cal)
        let from = Self.date(2026, 1, 1, in: cal)
        #expect(Self.everyDaysRule(0, anchor: anchor).nextFire(after: from, calendar: cal) == nil)
        #expect(Self.everyDaysRule(366, anchor: anchor).nextFire(after: from, calendar: cal) == nil)
    }

    @Test("Two firesAt on the anchor day — second time wins when first is past") func testEveryDaysTwoFiresAt() {
        let cal = Self.utcCalendar
        let rule = Self.everyDaysRule(
            28,
            anchor: Self.date(2026, 1, 5, in: cal),
            firesAt: [.init(hour: 8, minute: 0), .init(hour: 20, minute: 0)]
        )
        let from = Self.date(2026, 1, 5, 9, 0, in: cal)
        #expect(rule.nextFire(after: from, calendar: cal) == Self.date(2026, 1, 5, 20, 0, in: cal))
    }

    @Test("Chained fires stay exactly one interval apart") func testEveryDaysChainedNoDrift() {
        let cal = Self.utcCalendar
        let rule = Self.everyDaysRule(28, anchor: Self.date(2026, 1, 5, in: cal))
        var from = Self.date(2026, 1, 1, in: cal)
        var previous: Date?
        for _ in 0 ..< 13 {
            guard let next = rule.nextFire(after: from, calendar: cal) else {
                Issue.record("nextFire returned nil")
                return
            }
            if let previous {
                #expect(next.timeIntervalSince(previous) == 28 * 24 * 3600)
            }
            previous = next
            from = next
        }
    }

    @Test("Every 7 days across DST spring-forward — keeps the wall time") func testEveryDaysDST() {
        let cal = Self.berlinCalendar
        let rule = Self.everyDaysRule(7, anchor: Self.date(2026, 3, 22, in: cal))
        let from = Self.date(2026, 3, 22, 9, 0, in: cal)
        let expected = Self.date(2026, 3, 29, 8, 0, in: cal)
        let result = rule.nextFire(after: from, calendar: cal)
        #expect(result == expected)
        if let result {
            #expect(cal.component(.hour, from: result) == 8)
        }
    }
}
