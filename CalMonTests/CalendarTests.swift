import EventKit
import SwiftUI
import XCTest
@testable import CalMon

@MainActor
final class CalendarTests: XCTestCase {

    private var provider: HolidayProvider!
    private var preferences: Preferences!
    private var model: CalendarModel!

    override func setUp() async throws {
        try await super.setUp()
        provider = HolidayProvider()
        let suiteName = "CalMonTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        preferences = Preferences(defaults: defaults)
        model = CalendarModel(provider: provider, preferences: preferences)
    }

    override func tearDown() async throws {
        provider = nil
        preferences = nil
        model = nil
        try await super.tearDown()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    // MARK: - Solar terms (built-in calendrical data)

    func testSolarTerm2026() {
        XCTAssertEqual(provider.solarTerm(on: date(2026, 4, 5)), "清明")
        XCTAssertEqual(provider.solarTerm(on: date(2026, 12, 22)), "冬至")
    }

    func testSolarTermYearsLoaded() {
        XCTAssertTrue(provider.solarTermYears.contains(2026))
        XCTAssertTrue(provider.solarTermYears.contains(2027))
    }

    // MARK: - Lunar

    func testLunarNewYear2026() {
        let lunar = model.lunarDate(for: date(2026, 2, 17), calendar: .current)
        XCTAssertEqual(lunar.month, 1)
        XCTAssertEqual(lunar.day, 1)
        XCTAssertEqual(lunar.monthName, "正月")
        XCTAssertEqual(lunar.ganzhi, "丙午")
        XCTAssertEqual(lunar.zodiac, "马")
    }

    func testLunarEve2026() {
        let lunar = model.lunarDate(for: date(2026, 2, 16), calendar: .current)
        XCTAssertEqual(lunar.month, 12)
        XCTAssertEqual(lunar.day, 29)
        XCTAssertFalse(lunar.isLeapMonth)
    }

    func testLunarLeapMonth2025() {
        let lunar = model.lunarDate(for: date(2025, 7, 25), calendar: .current)
        XCTAssertTrue(lunar.isLeapMonth)
        XCTAssertEqual(lunar.month, 6)
    }

    func testLunarSummaryFormat() throws {
        model.showMonth(date(2026, 9, 25))
        model.select(date(2026, 9, 25))
        let detail = try XCTUnwrap(model.detail)
        XCTAssertEqual(detail.lunarSummary, "丙午年（马）八月十五")
    }

    func testSingleLineSummaryFormat() throws {
        model.select(date(2026, 9, 25))
        let detail = try XCTUnwrap(model.detail)
        XCTAssertEqual(detail.summaryDate, "2026年09月25日（第39周）")
    }

    // MARK: - Grid

    func testFebruary2026RowCounts() {
        preferences.weekStartsOnMonday = true
        model.showMonth(date(2026, 2, 1))
        XCTAssertEqual(model.weeks.count, 5)

        preferences.weekStartsOnMonday = false
        model.showMonth(date(2026, 2, 1))
        XCTAssertEqual(model.weeks.count, 4)
    }

    func testAllMonthsHaveFourToSixRows() {
        for month in 1...12 {
            model.showMonth(date(2026, month, 1))
            XCTAssertTrue((4...6).contains(model.weeks.count), "month \(month) rows \(model.weeks.count)")
        }
    }

    func testNeighborMonthSelectionSwitchesMonth() {
        model.showMonth(date(2026, 2, 1))
        model.select(date(2026, 3, 2))
        XCTAssertEqual(Calendar.current.component(.month, from: model.visibleMonth), 3)
        XCTAssertTrue(Calendar.current.isDate(model.selectedDate, inSameDayAs: date(2026, 3, 2)))
    }

    func testResetToToday() {
        model.showMonth(date(2020, 1, 1))
        model.resetToToday()
        XCTAssertTrue(Calendar.current.isDate(model.selectedDate, inSameDayAs: Date()))
        XCTAssertTrue(Calendar.current.isDate(model.visibleMonth, equalTo: Date(), toGranularity: .month))
    }

    func testRelativeText() {
        XCTAssertEqual(model.relativeText(for: model.today), "今天")
        let future = Calendar.current.date(byAdding: .day, value: 3, to: model.today)!
        XCTAssertEqual(model.relativeText(for: future), "距今天还有 3 天")
        let past = Calendar.current.date(byAdding: .day, value: -2, to: model.today)!
        XCTAssertEqual(model.relativeText(for: past), "距今天已过 2 天")
    }

    func testISOWeeks() {
        XCTAssertEqual(CalendarModel.isoWeekNumber(for: date(2026, 1, 1), timeZone: .current), 1)
        XCTAssertEqual(CalendarModel.isoWeekNumber(for: date(2025, 12, 29), timeZone: .current), 1)
        XCTAssertEqual(CalendarModel.isoWeekNumber(for: date(2026, 12, 31), timeZone: .current), 53)
    }

    func testWeekdayHeaderFollowsWeekStartPreference() {
        preferences.weekStartsOnMonday = true
        XCTAssertEqual(model.orderedWeekdaySymbols, ["周一", "周二", "周三", "周四", "周五", "周六", "周日"])
        preferences.weekStartsOnMonday = false
        XCTAssertEqual(model.orderedWeekdaySymbols, ["周日", "周一", "周二", "周三", "周四", "周五", "周六"])
    }

    func testWeekdayOnlyWhenEnabledInMenuBarText() {
        preferences.showWeekday = true
        model.rebuild()
        XCTAssertTrue(model.menuBarText.contains("周"))
        preferences.showWeekday = false
        model.rebuild()
        XCTAssertFalse(model.menuBarText.contains("周"))
    }

    /// R9: a preference change must rebuild the grid/detail without requiring a
    /// later date interaction.
    func testPreferenceChangeRebuildsWithoutManualCall() {
        preferences.weekStartsOnMonday = true
        model.showMonth(date(2026, 2, 1))
        XCTAssertEqual(model.weeks.count, 5)

        preferences.weekStartsOnMonday = false
        let exp = expectation(description: "rebuild after preference change")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(model.weeks.count, 4)
    }

    func testLunarDetailFollowsPreference() {
        preferences.showLunar = true
        XCTAssertTrue(model.showsLunarInDetail)
        preferences.showLunar = false
        XCTAssertFalse(model.showsLunarInDetail)
    }

    // MARK: - System source mapping (no built-in holidays)

    /// Uses the real event titles captured from the system "中国大陆节假日"
    /// calendar: plain entries (白露/秋分/中秋节/国庆节) vs arrangement entries
    /// with a （休）/（班） suffix.
    func testMapsRealHolidayCalendarFormat() {
        let store = EKEventStore()
        func event(_ title: String, _ s: (Int, Int, Int), _ e: (Int, Int, Int)) -> EKEvent {
            let x = EKEvent(eventStore: store)
            x.title = title
            x.startDate = date(s.0, s.1, s.2)
            x.endDate = date(e.0, e.1, e.2)
            return x
        }
        let events = [
            event("白露", (2026, 9, 7), (2026, 9, 8)),
            event("国庆节（班）", (2026, 9, 20), (2026, 9, 21)),
            event("秋分", (2026, 9, 23), (2026, 9, 24)),
            event("中秋节", (2026, 9, 25), (2026, 9, 26)),
            event("中秋节（休）", (2026, 9, 25), (2026, 9, 28)),
            event("国庆节", (2026, 10, 1), (2026, 10, 2)),
            event("国庆节（休）", (2026, 10, 1), (2026, 10, 8))
        ]
        let range = DateInterval(start: date(2026, 9, 1), end: date(2026, 11, 1))
        let mapped = HolidayProvider.map(events: events, range: range, calendar: .current)

        // Plain calendar entries show their name, no 休/班 marker.
        XCTAssertEqual(mapped.festivals["2026-09-07"]?.first?.title, "白露")
        XCTAssertNil(mapped.markers["2026-09-07"])
        XCTAssertEqual(mapped.festivals["2026-09-23"]?.first?.title, "秋分")
        XCTAssertNil(mapped.markers["2026-09-23"])

        // 补班 day: marker only, no festival name; arrangement keeps its title.
        XCTAssertEqual(mapped.markers["2026-09-20"], .workday)
        XCTAssertNil(mapped.festivals["2026-09-20"])
        XCTAssertEqual(mapped.arrangements["2026-09-20"]?.first?.title, "国庆节（班）")

        // 中秋 rest range 9/25–9/27: 休 on all days, name only on 9/25.
        XCTAssertEqual(mapped.markers["2026-09-25"], .holiday)
        XCTAssertEqual(mapped.markers["2026-09-26"], .holiday)
        XCTAssertEqual(mapped.markers["2026-09-27"], .holiday)
        XCTAssertEqual(mapped.festivals["2026-09-25"]?.first?.title, "中秋节")
        XCTAssertNil(mapped.festivals["2026-09-26"])
        XCTAssertNil(mapped.festivals["2026-09-27"])
        // Every rest day carries the arrangement title for the detail panel.
        XCTAssertEqual(mapped.arrangements["2026-09-26"]?.first?.title, "中秋节（休）")
        XCTAssertEqual(mapped.arrangements["2026-09-27"]?.first?.title, "中秋节（休）")

        // 国庆 rest range 10/1–10/7.
        XCTAssertEqual(mapped.markers["2026-10-01"], .holiday)
        XCTAssertEqual(mapped.markers["2026-10-07"], .holiday)
        XCTAssertEqual(mapped.festivals["2026-10-01"]?.first?.title, "国庆节")
        XCTAssertNil(mapped.festivals["2026-10-02"])
    }

    func testPlainFestivalNameStaysOnRealStartDay() {
        let store = EKEventStore()
        func event(_ title: String, _ s: (Int, Int, Int), _ e: (Int, Int, Int)) -> EKEvent {
            let x = EKEvent(eventStore: store)
            x.title = title
            x.startDate = date(s.0, s.1, s.2)
            x.endDate = date(e.0, e.1, e.2)
            return x
        }
        // Starts before the requested range and continues into it.
        let spanning = event("测试节", (2026, 9, 28), (2026, 10, 4))
        // Starts inside the range.
        let inside = event("国庆节", (2026, 10, 1), (2026, 10, 2))
        let range = DateInterval(start: date(2026, 10, 1), end: date(2026, 11, 1))
        let mapped = HolidayProvider.map(events: [spanning, inside], range: range, calendar: .current)
        let firstDayTitles = (mapped.festivals["2026-10-01"] ?? []).map(\.title)
        XCTAssertFalse(firstDayTitles.contains("测试节"), "multi-day event must not be relocated to the range start")
        XCTAssertTrue(firstDayTitles.contains("国庆节"))
    }

    func testMarkerForTitle() {
        XCTAssertEqual(HolidayProvider.marker(forTitle: "休"), .holiday)
        XCTAssertEqual(HolidayProvider.marker(forTitle: "中秋节（休）"), .holiday)
        XCTAssertEqual(HolidayProvider.marker(forTitle: "国庆节（班）"), .workday)
        XCTAssertEqual(HolidayProvider.marker(forTitle: " 补班 "), .workday)
        XCTAssertNil(HolidayProvider.marker(forTitle: "白露"))
        XCTAssertNil(HolidayProvider.marker(forTitle: "秋分"))
        XCTAssertNil(HolidayProvider.marker(forTitle: "中秋节"))
    }

    func testFestivalTitleStripsArrangementSuffix() {
        XCTAssertEqual(HolidayProvider.festivalTitle("中秋节（休）"), "中秋节")
        XCTAssertEqual(HolidayProvider.festivalTitle("国庆节（班）"), "国庆节")
        XCTAssertEqual(HolidayProvider.festivalTitle("白露"), "白露")
    }

    func testDetailFestivalsIncludeArrangementTitle() {
        let p = HolidayProvider(authorizationCheck: { true })
        p.selectedCalendarID = "abc"
        let arrangements = ["2026-10-02": [HolidayProvider.Festival(id: "a", title: "国庆节（休）", sourceTitle: "中国大陆节假日", marker: .holiday)]]
        p.publishFetchedEvents([:], arrangements: arrangements, markers: ["2026-10-02": .holiday], range: jan1Range, requestedGeneration: p.generation, calendarID: "abc", calendarTitle: "T")
        XCTAssertEqual(p.detailFestivals(on: date(2026, 10, 2)).first?.title, "国庆节（休）")
        XCTAssertEqual(p.detailFestivals(on: date(2026, 10, 2)).first?.marker, .holiday)
    }

    func testCalendarHolidayCandidateMatching() {
        // Title match alone is not enough; the calendar must be read-only.
        XCTAssertTrue(HolidayProvider.holidayCalendarCandidate(title: "中国大陆节假日", isReadOnly: true))
        XCTAssertTrue(HolidayProvider.holidayCalendarCandidate(title: "China Holidays", isReadOnly: true))
        XCTAssertFalse(HolidayProvider.holidayCalendarCandidate(title: "中国大陆节假日", isReadOnly: false))
        XCTAssertFalse(HolidayProvider.holidayCalendarCandidate(title: "中国节日计划", isReadOnly: false))
        XCTAssertFalse(HolidayProvider.holidayCalendarCandidate(title: "US Holidays", isReadOnly: true))
        XCTAssertFalse(HolidayProvider.holidayCalendarCandidate(title: "工作日历", isReadOnly: true))
        XCTAssertFalse(HolidayProvider.holidayCalendarCandidate(title: "个人", isReadOnly: false))
    }

    // MARK: - Dedup

    func testNormalizeMergesSameNames() {
        XCTAssertEqual(HolidayProvider.normalize("春节"), HolidayProvider.normalize(" 春节 "))
        XCTAssertEqual(HolidayProvider.normalize("国庆节"), HolidayProvider.normalize("国庆节"))
        XCTAssertNotEqual(HolidayProvider.normalize("国庆节"), HolidayProvider.normalize("中秋节"))
    }

    // MARK: - Source invalidation (F3)

    private var jan1Range: DateInterval { DateInterval(start: date(2026, 1, 1), duration: 86_400) }

    private func festivalMap() -> [String: [HolidayProvider.Festival]] {
        ["2026-01-01": [HolidayProvider.Festival(id: "x", title: "测试节日", sourceTitle: nil)]]
    }

    private func isError(_ status: HolidayProvider.SourceStatus) -> Bool {
        if case .error = status { return true }
        return false
    }

    func testReloadAndDisconnectInvalidateInFlightFetches() {
        let staleGeneration = provider.generation
        provider.reloadEvents()
        XCTAssertGreaterThan(provider.generation, staleGeneration, "reloadEvents must invalidate in-flight fetches")

        let afterReload = provider.generation
        provider.disconnect()
        XCTAssertGreaterThan(provider.generation, afterReload, "disconnect must invalidate in-flight fetches")

        provider.publishFetchedEvents(festivalMap(), arrangements: [:], markers: [:], range: jan1Range, requestedGeneration: staleGeneration, calendarID: "abc", calendarTitle: "T")
        XCTAssertTrue(provider.systemFestivals(on: date(2026, 1, 1)).isEmpty)
    }

    func testFetchedEventsDiscardedWhenSourceChanged() {
        provider.selectedCalendarID = "abc"
        provider.selectedCalendarTitle = "T"
        let generation = provider.generation
        provider.selectedCalendarID = "other"
        provider.publishFetchedEvents(festivalMap(), arrangements: [:], markers: [:], range: jan1Range, requestedGeneration: generation, calendarID: "abc", calendarTitle: "T")
        XCTAssertTrue(provider.systemFestivals(on: date(2026, 1, 1)).isEmpty)
    }

    func testFetchedEventsDiscardedWhenUnauthorized() {
        provider = HolidayProvider(authorizationCheck: { false })
        provider.selectedCalendarID = "abc"
        provider.selectedCalendarTitle = "T"
        provider.publishFetchedEvents(festivalMap(), arrangements: [:], markers: [:], range: jan1Range, requestedGeneration: provider.generation, calendarID: "abc", calendarTitle: "T")
        XCTAssertTrue(provider.systemFestivals(on: date(2026, 1, 1)).isEmpty)
        XCTAssertTrue(isError(provider.sourceStatus))
    }

    func testRevokedAccessClearsPreviouslyPublishedEvents() {
        var authorized = true
        provider = HolidayProvider(authorizationCheck: { authorized })
        provider.selectedCalendarID = "abc"
        provider.publishFetchedEvents(festivalMap(), arrangements: [:], markers: [:], range: jan1Range, requestedGeneration: provider.generation, calendarID: "abc", calendarTitle: "T")
        XCTAssertFalse(provider.systemFestivals(on: date(2026, 1, 1)).isEmpty)
        let oldGeneration = provider.generation
        authorized = false
        provider.reloadEvents()
        XCTAssertTrue(provider.systemFestivals(on: date(2026, 1, 1)).isEmpty)
        XCTAssertTrue(isError(provider.sourceStatus))
        provider.publishFetchedEvents(festivalMap(), arrangements: [:], markers: [:], range: jan1Range, requestedGeneration: oldGeneration, calendarID: "abc", calendarTitle: "T")
        XCTAssertTrue(provider.systemFestivals(on: date(2026, 1, 1)).isEmpty)
        let revision = provider.revision
        provider.ensureEvents(range: jan1Range)
        XCTAssertEqual(provider.revision, revision, "rebuild must not cause an invalidation loop")
    }

    // MARK: - Year navigation (docs/SEARCH_AND_YEAR_NAVIGATION.md §3)

    func testYearNavigationKeepsDayOfMonth() {
        model.select(date(2026, 9, 15))
        model.goToNextYear()
        XCTAssertTrue(Calendar.current.isDate(model.selectedDate, inSameDayAs: date(2027, 9, 15)))
        XCTAssertEqual(Calendar.current.component(.month, from: model.visibleMonth), 9)
        model.goToPreviousYear()
        XCTAssertTrue(Calendar.current.isDate(model.selectedDate, inSameDayAs: date(2026, 9, 15)))
    }

    func testYearNavigationClampsLeapDay() {
        model.select(date(2028, 2, 29))
        model.goToNextYear()
        XCTAssertTrue(Calendar.current.isDate(model.selectedDate, inSameDayAs: date(2029, 2, 28)))
        // No hidden "original day" memory: another year keeps the clamped day.
        model.goToNextYear()
        XCTAssertTrue(Calendar.current.isDate(model.selectedDate, inSameDayAs: date(2030, 2, 28)))
    }

    func testYearNavigationCrossesYearBoundary() {
        model.select(date(2026, 12, 31))
        model.goToNextYear()
        XCTAssertTrue(Calendar.current.isDate(model.selectedDate, inSameDayAs: date(2027, 12, 31)))
        model.select(date(2027, 1, 31))
        model.goToPreviousYear()
        XCTAssertTrue(Calendar.current.isDate(model.selectedDate, inSameDayAs: date(2026, 1, 31)))
    }

    func testMonthNavigationStillSingleStep() {
        model.select(date(2028, 2, 29))
        model.goToNextMonth()
        XCTAssertTrue(Calendar.current.isDate(model.selectedDate, inSameDayAs: date(2028, 3, 29)))
    }

    // MARK: - Fixed six-row panel grid (CALENDAR_PANEL_FINAL_LAYOUT follow-up)

    func testPanelGridAlwaysHasSixRows() {
        // 2027-02 has four natural rows, 2026-09 has five.
        model.select(date(2027, 2, 15))
        XCTAssertEqual(model.weeks.count, 4)
        let four = model.gridWeeks(minimumRows: 6)
        XCTAssertEqual(four.count, 6)
        XCTAssertEqual(four.flatMap { $0.days }.count, 42)
        // The extra rows are adjacent-month days, dimmed like the natural grid.
        let extra = four.dropFirst(4).flatMap { $0.days }
        XCTAssertTrue(extra.allSatisfy { !$0.isCurrentMonth })

        model.select(date(2026, 9, 15))
        XCTAssertEqual(model.weeks.count, 5)
        XCTAssertEqual(model.gridWeeks(minimumRows: 6).count, 6)
    }

    func testPanelGridKeepsTheNaturalGridWhenAlreadySixRows() {
        // 2026-08 has six natural rows.
        model.select(date(2026, 8, 15))
        XCTAssertEqual(model.weeks.count, 6)
        XCTAssertEqual(model.gridWeeks(minimumRows: 6).map(\.id), model.weeks.map(\.id))
    }

    // MARK: - Weekend marking (red numbers / header columns)

    func testWeekendFlagsFollowSaturdayAndSunday() {
        model.select(date(2026, 9, 19))   // Saturday
        XCTAssertTrue(model.weeks.flatMap { $0.days }.first { Calendar.current.isDate($0.date, inSameDayAs: date(2026, 9, 19)) }!.isWeekend)
        model.select(date(2026, 9, 18))   // Friday
        XCTAssertFalse(model.weeks.flatMap { $0.days }.first { Calendar.current.isDate($0.date, inSameDayAs: date(2026, 9, 18)) }!.isWeekend)
        model.select(date(2026, 9, 20))   // Sunday
        XCTAssertTrue(model.weeks.flatMap { $0.days }.first { Calendar.current.isDate($0.date, inSameDayAs: date(2026, 9, 20)) }!.isWeekend)
    }

    func testWeekendHeadersFollowWeekStart() {
        preferences.weekStartsOnMonday = true
        XCTAssertEqual(model.orderedWeekdayIsWeekend, [false, false, false, false, false, true, true])
        preferences.weekStartsOnMonday = false
        XCTAssertEqual(model.orderedWeekdayIsWeekend, [true, false, false, false, false, false, true])
        XCTAssertEqual(model.orderedWeekdaySymbols.first, "周日")
    }

    // MARK: - Weekend / holiday number colours

    func testWeekendNumbersAreRedUnlessItIsAMakeUpWorkday() {
        let red = UIStyle.Colors.restBadgeBackground
        // Weekend, no marker.
        XCTAssertEqual(CalendarDayCell.numberColor(isToday: false, isCurrentMonth: true, isWeekend: true, badge: nil), red)
        // Weekend with 班 (make-up workday) stays normal.
        XCTAssertEqual(CalendarDayCell.numberColor(isToday: false, isCurrentMonth: true, isWeekend: true, badge: .workday), .primary)
        // Weekday holiday is red as well.
        XCTAssertEqual(CalendarDayCell.numberColor(isToday: false, isCurrentMonth: true, isWeekend: false, badge: .holiday), red)
        // Ordinary weekday stays normal.
        XCTAssertEqual(CalendarDayCell.numberColor(isToday: false, isCurrentMonth: true, isWeekend: false, badge: nil), .primary)
        // Today wins over everything.
        XCTAssertEqual(CalendarDayCell.numberColor(isToday: true, isCurrentMonth: true, isWeekend: true, badge: nil), .white)
        // Adjacent-month weekends/holidays keep the red, dimmed like the badges.
        XCTAssertEqual(
            CalendarDayCell.numberColor(isToday: false, isCurrentMonth: false, isWeekend: true, badge: nil),
            red.opacity(UIStyle.Metrics.adjacentMonthOpacity)
        )
        XCTAssertEqual(
            CalendarDayCell.numberColor(isToday: false, isCurrentMonth: false, isWeekend: false, badge: .holiday),
            red.opacity(UIStyle.Metrics.adjacentMonthOpacity)
        )
        // Adjacent-month make-up workday stays dimmed grey, as do plain days.
        XCTAssertEqual(
            CalendarDayCell.numberColor(isToday: false, isCurrentMonth: false, isWeekend: true, badge: .workday),
            Color(nsColor: .tertiaryLabelColor)
        )
        XCTAssertEqual(
            CalendarDayCell.numberColor(isToday: false, isCurrentMonth: false, isWeekend: false, badge: nil),
            Color(nsColor: .tertiaryLabelColor)
        )
    }
}
