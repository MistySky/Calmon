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
        XCTAssertGreaterThanOrEqual(CalendarPanelController.fitScale(visibleSize: visible), 1)
        XCTAssertEqual(
            CalendarPanelController.resolvedScale(remembered: 1, visibleSize: visible),
            1.0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            CalendarPanelController.resolvedScale(remembered: 1.25, visibleSize: visible),
            1.25,
            accuracy: 0.0001
        )
        // A remembered scale above sFit is clamped to this screen's fit scale.
        let fit = CalendarPanelController.fitScale(visibleSize: visible)
        XCTAssertGreaterThan(fit, 1.25)
        XCTAssertEqual(
            CalendarPanelController.resolvedScale(remembered: 3, visibleSize: visible),
            fit,
            accuracy: 0.0001
        )
        XCTAssertLessThan(CalendarPanelController.resolvedScale(remembered: 3, visibleSize: visible), 3)
    }

    func testScaleNeverShrinksBelowOneOnLargeScreen() {
        let visible = CGSize(width: 3840, height: 2160)
        XCTAssertEqual(
            CalendarPanelController.resolvedScale(remembered: 0.5, visibleSize: visible),
            1.0,
            accuracy: 0.0001
        )
    }

    func testTinyScreenAdaptsToFitWithoutChangingPreference() {
        // Smaller than the 4-row base plus margins.
        let visible = CGSize(width: 900, height: 500)
        let fit = CalendarPanelController.fitScale(visibleSize: visible)
        XCTAssertLessThan(fit, 1)
        XCTAssertEqual(
            CalendarPanelController.resolvedScale(remembered: 1.5, visibleSize: visible),
            fit,
            accuracy: 0.0001
        )
    }

    func testContentSizeIsFixedByTheSixRowGrid() {
        // Width is derived; the six-row grid fixes the height for every month.
        XCTAssertEqual(PanelLayout.contentSize(scale: 1).width, PanelLayout.baseWidth, accuracy: 0.001)
        XCTAssertEqual(PanelLayout.contentSize(scale: 1).height, 580, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.rightColumnHeight, 480, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.blockHeight, 480, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.gridRows, 6)
        // Scaling multiplies both axes by the same s.
        let scaled = PanelLayout.contentSize(scale: 1.25)
        XCTAssertEqual(scaled.width, PanelLayout.baseWidth * 1.25, accuracy: 0.001)
        XCTAssertEqual(scaled.height, 580 * 1.25, accuracy: 0.01)
    }

    func testGridUsesCompactRegularMetrics() {
        XCTAssertEqual(PanelLayout.dateRowHeight, 64, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.cellWidth, 80, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.rightWidth, 560, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.rightColumnWidth, 609.70, accuracy: 0.01)
        XCTAssertGreaterThan(PanelLayout.cellWidth, PanelLayout.dateRowHeight)
        XCTAssertEqual(PanelLayout.baseWidth, 1013.70, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.titleBandHeight, 44, accuracy: 0.0001)
        XCTAssertEqual(PanelLayout.weekdayBandHeight, 32, accuracy: 0.0001)
        XCTAssertEqual(PanelLayout.titleGap, 12, accuracy: 0.0001)
        XCTAssertEqual(PanelLayout.weekdayGap, 8, accuracy: 0.0001)
        XCTAssertEqual(PanelLayout.navGroupWidth, 92, accuracy: 0.0001)
        XCTAssertEqual(
            PanelLayout.rightWidth - PanelLayout.navGroupWidth * 2 - PanelLayout.navTitleWidth,
            206,
            accuracy: 0.0001
        )
    }

    func testFourSideMarginIsEqual() {
        XCTAssertEqual(PanelLayout.margin, 50)
        XCTAssertEqual(
            PanelLayout.baseWidth,
            PanelLayout.leftWidth + PanelLayout.columnGap + PanelLayout.rightColumnWidth + PanelLayout.margin * 2,
            accuracy: 0.0001
        )
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

    func testBlockHeightIsTheSixRowGrid() {
        XCTAssertEqual(PanelLayout.gridTopHeight, 96, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.dateRowHeight, 64, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.cellWidth, 80, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.rightWidth, 560, accuracy: 0.01)
        XCTAssertGreaterThan(PanelLayout.cellWidth, PanelLayout.dateRowHeight)
        XCTAssertEqual(PanelLayout.baseWidth, 1013.70, accuracy: 0.01)
        XCTAssertEqual(
            PanelLayout.rightColumnHeight,
            PanelLayout.gridTopHeight + PanelLayout.dateRowHeight * 6,
            accuracy: 0.0001
        )
    }

    func testWindowHeightIsBlockPlusEqualMargins() {
        XCTAssertEqual(PanelLayout.contentHeight, PanelLayout.blockHeight + PanelLayout.margin * 2, accuracy: 0.0001)
        XCTAssertEqual(PanelLayout.contentHeight, 580, accuracy: 0.01)
    }

    func testLeftColumnUsesOneSpacingSystem() {
        // Groups: date, time, extra date info, events. Fixed 20/16 divider gaps,
        // no flexible gap anywhere.
        XCTAssertEqual(PanelLayout.dividerTopGap, 20, accuracy: 0.0001)
        XCTAssertEqual(PanelLayout.dividerBottomGap, 16, accuracy: 0.0001)
        XCTAssertEqual(PanelLayout.eventAreaTop, 261, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.leftColumnFlow, 421, accuracy: 0.01)
        XCTAssertLessThan(PanelLayout.leftColumnFlow, PanelLayout.blockHeight)
    }

    func testEventAreaHoldsThreeCards() {
        XCTAssertEqual(PanelLayout.eventCardHeight, 48, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.eventSpacing, 8, accuracy: 0.01)
        XCTAssertEqual(PanelLayout.eventAreaHeight, 160, accuracy: 0.01)
        // Three cards plus spacing equal the event area.
        XCTAssertEqual(
            PanelLayout.eventAreaHeight,
            3 * PanelLayout.eventCardHeight + 2 * PanelLayout.eventSpacing,
            accuracy: 0.0001
        )
        XCTAssertEqual(PanelLayout.dividerSlotHeight, 1, accuracy: 0.0001)
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
        let base = PanelLayout.contentSize(scale: 1)
        XCTAssertEqual(PanelLayout.scale(contentSize: base), 1, accuracy: 0.0001)
        let scaled = PanelLayout.contentSize(scale: 1.25)
        XCTAssertEqual(PanelLayout.scale(contentSize: scaled), 1.25, accuracy: 0.0001)
        // The smaller of the two axes wins if a transient size is off-aspect.
        XCTAssertEqual(
            PanelLayout.scale(contentSize: CGSize(width: 1125, height: PanelLayout.contentHeight)),
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(PanelLayout.scale(contentSize: .zero), 1, accuracy: 0.0001)
    }
}
