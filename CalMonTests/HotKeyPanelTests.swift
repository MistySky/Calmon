import Carbon.HIToolbox
import XCTest
@testable import CalMon

/// Hot-key validation, preference round-trips and the panel's read-only model
/// accessors (docs/CALENDAR_HOTKEY_PANEL.md).
@MainActor
final class HotKeyPanelTests: XCTestCase {

    private func freshDefaults() -> (UserDefaults, String) {
        let name = "CalMonTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (defaults, name)
    }

    // MARK: - Validation

    func testHotKeyRequiresCommandOrControl() {
        XCTAssertEqual(
            GlobalHotKeyController.validate(modifiers: [.option], keyCode: 8, characters: "c"),
            .missingModifier
        )
        XCTAssertNil(GlobalHotKeyController.validate(modifiers: [.command], keyCode: 8, characters: "c"))
        XCTAssertNil(GlobalHotKeyController.validate(modifiers: [.control], keyCode: 8, characters: "c"))
    }

    func testHotKeyRequiresLetterOrDigit() {
        XCTAssertEqual(
            GlobalHotKeyController.validate(modifiers: [.command], keyCode: 8, characters: ""),
            .missingKey
        )
        XCTAssertEqual(
            GlobalHotKeyController.validate(modifiers: [.command], keyCode: 41, characters: ";"),
            .missingKey
        )
        XCTAssertEqual(
            GlobalHotKeyController.validate(modifiers: [.command], keyCode: 0, characters: "ab"),
            .missingKey
        )
        XCTAssertNil(GlobalHotKeyController.validate(modifiers: [.command, .shift], keyCode: 18, characters: "1"))
    }

    func testReservedCombinationsAreRejected() {
        XCTAssertEqual(
            GlobalHotKeyController.validate(modifiers: [.command], keyCode: 12, characters: "q"),
            .reserved
        )
        XCTAssertEqual(
            GlobalHotKeyController.validate(modifiers: [.command], keyCode: 43, characters: ","),
            .reserved
        )
        // Control+Q is not reserved by this app.
        XCTAssertNil(GlobalHotKeyController.validate(modifiers: [.control], keyCode: 12, characters: "q"))
    }

    // MARK: - Modifier conversion

    func testCarbonModifierConversion() {
        XCTAssertEqual(GlobalHotKeyController.carbonModifiers(from: .command), UInt32(cmdKey))
        XCTAssertEqual(
            GlobalHotKeyController.carbonModifiers(from: [.control, .option, .shift, .command]),
            UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(cmdKey)
        )
        // Caps lock and numeric-pad flags are ignored.
        XCTAssertEqual(GlobalHotKeyController.carbonModifiers(from: [.command, .capsLock]), UInt32(cmdKey))
    }

    func testModifierFlagsRoundTrip() {
        let carbon = UInt32(controlKey) | UInt32(shiftKey)
        XCTAssertEqual(GlobalHotKeyController.modifierFlags(fromCarbon: carbon), [.control, .shift])
        XCTAssertEqual(
            GlobalHotKeyController.modifierSymbols(UInt32(cmdKey) | UInt32(controlKey)),
            "⌃⌘"
        )
        XCTAssertEqual(
            GlobalHotKeyController.modifierSymbols(UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey) | UInt32(cmdKey)),
            "⌃⌥⇧⌘"
        )
    }

    func testDisplayStringUsesCurrentLayout() {
        let unset = GlobalHotKeyController.HotKey(keyCode: 0, carbonModifiers: 0)
        XCTAssertFalse(unset.isSet)
        XCTAssertEqual(GlobalHotKeyController.displayString(unset), "")

        // Key code 0 ("A" on the usual layout) resolves through UCKeyTranslate.
        let hotKey = GlobalHotKeyController.HotKey(keyCode: 0, carbonModifiers: UInt32(cmdKey))
        XCTAssertTrue(hotKey.isSet)
        let text = GlobalHotKeyController.displayString(hotKey)
        XCTAssertTrue(text.hasPrefix("⌘"), text)
        XCTAssertGreaterThanOrEqual(text.count, 2, text)
    }

    // MARK: - Preferences persistence

    func testPanelHotKeyDefaultsToUnset() {
        let (defaults, _) = freshDefaults()
        let preferences = Preferences(defaults: defaults)
        XCTAssertNil(preferences.panelHotKey)
        XCTAssertEqual(preferences.panelScale, 1, accuracy: 0.0001)
    }

    func testPanelHotKeyPersistsAndClears() {
        let (defaults, name) = freshDefaults()
        let first = Preferences(defaults: defaults)
        let hotKey = GlobalHotKeyController.HotKey(keyCode: 8, carbonModifiers: UInt32(cmdKey))
        first.panelHotKey = hotKey

        let second = Preferences(defaults: defaults)
        XCTAssertEqual(second.panelHotKey, hotKey)

        second.panelHotKey = nil
        let third = Preferences(defaults: defaults)
        XCTAssertNil(third.panelHotKey)

        defaults.removePersistentDomain(forName: name)
    }

    func testPanelScalePersists() {
        let (defaults, name) = freshDefaults()
        let first = Preferences(defaults: defaults)
        first.panelScale = 1.25

        let second = Preferences(defaults: defaults)
        XCTAssertEqual(second.panelScale, 1.25, accuracy: 0.0001)

        defaults.removePersistentDomain(forName: name)
    }

    // MARK: - Scale constraints (row-driven height)

    func testRegularScreenAllowsStoredScale() {
        let visible = CGSize(width: 1920, height: 1080)
        for rows in 4...6 {
            XCTAssertGreaterThanOrEqual(CalendarPanelController.fitScale(visibleSize: visible, rows: rows), 1)
        }
        XCTAssertEqual(
            CalendarPanelController.resolvedScale(remembered: 1, visibleSize: visible, rows: 5),
            1.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CalendarPanelController.resolvedScale(remembered: 1.25, visibleSize: visible, rows: 5),
            1.25,
            accuracy: 0.0001
        )
        // A remembered scale above sFit is clamped to this screen's fit scale.
        let fit = CalendarPanelController.fitScale(visibleSize: visible, rows: 5)
        XCTAssertGreaterThan(fit, 1.25)
        XCTAssertEqual(
            CalendarPanelController.resolvedScale(remembered: 3, visibleSize: visible, rows: 5),
            fit,
            accuracy: 0.0001
        )
        XCTAssertLessThan(CalendarPanelController.resolvedScale(remembered: 3, visibleSize: visible, rows: 5), 3)
    }

    func testScaleNeverShrinksBelowOneOnLargeScreen() {
        let visible = CGSize(width: 3840, height: 2160)
        for rows in 4...6 {
            XCTAssertEqual(
                CalendarPanelController.resolvedScale(remembered: 0.5, visibleSize: visible, rows: rows),
                1.0,
                accuracy: 0.0001
            )
        }
    }

    func testTinyScreenAdaptsToFitWithoutChangingPreference() {
        // Smaller than the 4-row base plus margins.
        let visible = CGSize(width: 900, height: 500)
        let fit = CalendarPanelController.fitScale(visibleSize: visible, rows: 4)
        XCTAssertLessThan(fit, 1)
        XCTAssertEqual(
            CalendarPanelController.resolvedScale(remembered: 1.5, visibleSize: visible, rows: 4),
            fit,
            accuracy: 0.0001
        )
    }

    func testContentSizeKeepsWidthAspectPerMonth() {
        // Width is fixed at 880; height follows the month's real row count.
        XCTAssertEqual(PanelLayout.contentSize(rows: 4, scale: 1).width, 900)
        XCTAssertEqual(PanelLayout.contentSize(rows: 5, scale: 1).width, 900)
        XCTAssertEqual(PanelLayout.contentSize(rows: 6, scale: 1).width, 900)
        XCTAssertEqual(PanelLayout.contentSize(rows: 4, scale: 1).height, 537.38, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.contentSize(rows: 5, scale: 1).height, 565.76, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.contentSize(rows: 6, scale: 1).height, 638.34, accuracy: 0.01)
        // Scaling multiplies both axes by the same s.
        let scaled = PanelLayout.contentSize(rows: 5, scale: 1.25)
        XCTAssertEqual(scaled.width, 1125, accuracy: 0.001)
        XCTAssertEqual(scaled.height, 565.76 * 1.25, accuracy: 0.01)
    }

    func testGridIsTheSmallCalendarScaledToTheRightColumn() {
        // Small calendar: 328 pt grid, 48 pt rows, 24 pt weekday band,
        // 32 pt title band, 8/4 pt gaps. The panel scales that to 528 pt.
        XCTAssertEqual(PanelLayout.gridScale, PanelLayout.rightWidth / 328, accuracy: 0.0001)
        XCTAssertEqual(PanelLayout.dateRowHeight, 48 * PanelLayout.gridScale, accuracy: 0.0001)
        XCTAssertEqual(PanelLayout.dateRowHeight, 72.59, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.titleBandHeight, 32 * PanelLayout.gridScale, accuracy: 0.0001)
        XCTAssertEqual(PanelLayout.weekdayBandHeight, 24 * PanelLayout.gridScale, accuracy: 0.0001)
        XCTAssertEqual(PanelLayout.titleGap, 8 * PanelLayout.gridScale, accuracy: 0.0001)
        XCTAssertEqual(PanelLayout.weekdayGap, 4 * PanelLayout.gridScale, accuracy: 0.0001)
        // Cells are near-square like the small calendar (48 / 46.86).
        let columnWidth = PanelLayout.rightWidth / 7
        XCTAssertEqual(PanelLayout.dateRowHeight / columnWidth, 48 / (328.0 / 7), accuracy: 0.0001)
    }

    func testFourSideMarginIsEqual() {
        XCTAssertEqual(PanelLayout.margin, 50)
        for rows in 4...6 {
            let width = PanelLayout.leftWidth + PanelLayout.columnGap + PanelLayout.rightWidth + PanelLayout.margin * 2
            XCTAssertEqual(PanelLayout.baseWidth, width, accuracy: 0.0001)
            XCTAssertEqual(
                PanelLayout.contentHeight(rows: rows),
                PanelLayout.blockHeight(rows: rows) + PanelLayout.margin * 2,
                accuracy: 0.0001
            )
        }
    }

    // MARK: - Clock lifecycle

    func testClockStartsAndStops() {
        let clock = PanelClock()
        XCTAssertFalse(clock.isRunning)
        clock.start()
        XCTAssertTrue(clock.isRunning)
        clock.start()
        XCTAssertTrue(clock.isRunning, "starting twice must not stack timers")
        clock.stop()
        XCTAssertFalse(clock.isRunning)
        clock.stop()
        XCTAssertFalse(clock.isRunning)
    }

    func testClockFormatsCurrentTime() {
        let clock = PanelClock()
        let text = clock.timeString
        XCTAssertEqual(text.count, 8)
        XCTAssertEqual(text.filter { $0 == ":" }.count, 2)
    }

    // MARK: - Global registration

    func testRegisterAndUnregisterSucceeds() {
        let controller = GlobalHotKeyController()
        // Control+Option+Shift+` is an unusual combo unlikely to clash.
        let hotKey = GlobalHotKeyController.HotKey(
            keyCode: 50,
            carbonModifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey)
        )
        let status = controller.register(hotKey) {}
        XCTAssertEqual(status, noErr)
        XCTAssertEqual(controller.registered, hotKey)
        controller.unregister()
        XCTAssertNil(controller.registered)
    }

    func testConflictingRegistrationFailsAndKeepsNothing() {
        let hotKey = GlobalHotKeyController.HotKey(
            keyCode: 50,
            carbonModifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(shiftKey)
        )
        let holder = GlobalHotKeyController()
        XCTAssertEqual(holder.register(hotKey) {}, noErr)
        // Exclusive registration: the same combo cannot be claimed twice.
        let second = GlobalHotKeyController()
        let status = second.register(hotKey) {}
        XCTAssertNotEqual(status, noErr)
        XCTAssertNil(second.registered)
        holder.unregister()
    }

    // MARK: - Panel model accessors

    func testPanelAccessorsFormatSelectedDate() {
        let (defaults, name) = freshDefaults()
        let preferences = Preferences(defaults: defaults)
        let model = CalendarModel(provider: HolidayProvider(), preferences: preferences)
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 17, hour: 12))!
        model.select(date)

        XCTAssertEqual(model.selectedGregorianTitle, "2026年9月17日")
        XCTAssertEqual(model.selectedWeekdayText, "星期四")
        XCTAssertEqual(model.selectedISOWeekText, "第 38 周")
        XCTAssertFalse(model.selectedLunarSummary.isEmpty)
        XCTAssertTrue(model.selectedLunarSummary.contains("年"), model.selectedLunarSummary)

        defaults.removePersistentDomain(forName: name)
    }

    /// ISO week numbering is independent of the configurable week start.
    func testISOWeekIsStableAcrossWeekStartSetting() {
        let (defaults, name) = freshDefaults()
        let preferences = Preferences(defaults: defaults)
        let model = CalendarModel(provider: HolidayProvider(), preferences: preferences)
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12))!

        model.select(date)
        XCTAssertEqual(model.selectedISOWeekText, "第 1 周")
        preferences.weekStartsOnMonday = false
        model.rebuild()
        XCTAssertEqual(model.selectedISOWeekText, "第 1 周")

        defaults.removePersistentDomain(forName: name)
    }

    // MARK: - Panel content block layout (CALENDAR_PANEL_UI_FOLLOWUP.md §4)

    func testBlockHeightFollowsRows() {
        // B = max(leftColumnHeight, gridTop + rowHeight * n).
        XCTAssertEqual(PanelLayout.leftColumnHeight, 437.38, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.gridTopHeight, 102.83, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.dateRowHeight, 72.59, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.rightColumnHeight(rows: 4), 393.17, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.rightColumnHeight(rows: 5), 465.76, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.rightColumnHeight(rows: 6), 538.34, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.blockHeight(rows: 4), 437.38, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.blockHeight(rows: 5), 465.76, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.blockHeight(rows: 6), 538.34, accuracy: 0.01)
    }

    func testWindowHeightIsBlockPlusEqualMargins() {
        for rows in 4...6 {
            let block = PanelLayout.blockHeight(rows: rows)
            XCTAssertEqual(PanelLayout.contentHeight(rows: rows), block + PanelLayout.margin * 2, accuracy: 0.0001)
        }
        XCTAssertEqual(PanelLayout.contentHeight(rows: 4), 537.38, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.contentHeight(rows: 5), 565.76, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.contentHeight(rows: 6), 638.34, accuracy: 0.01)
    }

    func testFourRowMonthKeepsTheDifferenceInTheRightColumn() {
        // 4-row months: the right column is shorter and nothing is stretched.
        XCTAssertEqual(PanelLayout.blockHeight(rows: 4) - PanelLayout.rightColumnHeight(rows: 4), 44.21, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.blockHeight(rows: 5) - PanelLayout.rightColumnHeight(rows: 5), 0, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.blockHeight(rows: 6) - PanelLayout.rightColumnHeight(rows: 6), 0, accuracy: 0.01)
    }

    func testLeftColumnFlowFitsTheEventArea() {
        XCTAssertEqual(PanelLayout.eventAreaTop, 266.28, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.eventAreaHeight, 171.09, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.eventAreaTop + PanelLayout.eventAreaHeight, PanelLayout.leftColumnHeight, accuracy: 0.0001)
        XCTAssertEqual(PanelLayout.dividerSlotHeight, 1, accuracy: 0.0001)
        // Three cards plus spacing equal the event area.
        XCTAssertEqual(
            PanelLayout.eventAreaHeight,
            3 * PanelLayout.eventCardHeight + 2 * PanelLayout.eventSpacing,
            accuracy: 0.0001
        )
    }

    func testPanelMetricsUseScaledCalendarAndEventRow() {
        let grid = CalendarGridMetrics.panel(scale: 1, gridWidth: PanelLayout.rightWidth)
        XCTAssertEqual(grid.rowHeight, PanelLayout.dateRowHeight, accuracy: 0.0001)
        XCTAssertEqual(grid.columnWidth, PanelLayout.rightWidth / 7, accuracy: 0.0001)
        let info = CalendarInfoMetrics.panel(scale: 1)
        XCTAssertEqual(info.minHeight, PanelLayout.eventCardHeight, accuracy: 0.0001)
        XCTAssertTrue(info.labelCentered)
    }

    func testScaleIsDerivedFromLiveContentSize() {
        for rows in 4...6 {
            let base = PanelLayout.contentSize(rows: rows, scale: 1)
            XCTAssertEqual(PanelLayout.scale(contentSize: base, rows: rows), 1, accuracy: 0.0001)
            let scaled = PanelLayout.contentSize(rows: rows, scale: 1.25)
            XCTAssertEqual(PanelLayout.scale(contentSize: scaled, rows: rows), 1.25, accuracy: 0.0001)
        }
        // The smaller of the two axes wins if a transient size is off-aspect.
        let fiveRows = PanelLayout.contentHeight(rows: 5)
        XCTAssertEqual(
            PanelLayout.scale(contentSize: CGSize(width: 1100, height: fiveRows), rows: 5),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(PanelLayout.scale(contentSize: .zero, rows: 5), 1, accuracy: 0.0001)
    }
}
