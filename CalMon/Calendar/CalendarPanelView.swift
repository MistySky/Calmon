import AppKit
import Observation
import SwiftUI

/// Seconds clock for the hot-key panel. Ticks only while the panel is visible
/// (docs/CALENDAR_HOTKEY_PANEL.md §8); it never writes into the calendar model,
/// preferences or monitoring snapshots.
@MainActor
@Observable
final class PanelClock {
    private(set) var now = Date()
    /// Number of timer fires since launch; diagnostics use it to prove the clock
    /// stops when the panel is hidden.
    private(set) var tickCount = 0
    private var timer: Timer?

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        now = Date()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // A fire can be queued just as the panel closes; drop it so no
                // state updates happen after stop().
                guard let self, self.timer != nil else { return }
                self.tickCount += 1
                self.now = Date()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var timeString: String { Self.formatter.string(from: now) }
}

/// Pure layout math for the hot-key panel so 4/5/6-row centering and the
/// content-derived scale can be tested without a window (CALENDAR_PANEL_UI_FOLLOWUP.md §4–5).
enum PanelLayout {
    // MARK: - Proportion sources
    //
    // The panel's calendar is the small menu-bar calendar scaled up so its grid
    // fills the right column (user request 2026-09-17): the small grid is 328 pt
    // wide and the right column is 528 pt, so the grid scales by 528 / 328.
    // The left column's rhythm follows the date-row magnification (77.3 / 56).
    nonisolated static let gridScale: CGFloat = rightWidth / 328          // 496/328 = 1.5122
    nonisolated static let rhythmScale: CGFloat = dateRowHeight / 56      // 1.2962

    /// Equal margin on all four sides (user: 50 pt).
    nonisolated static let margin: CGFloat = 50
    /// Content width is derived so the two columns keep their size while the
    /// margins stay equal on all four sides.
    nonisolated static var baseWidth: CGFloat { margin * 2 + leftWidth + columnGap + rightWidth }
    nonisolated static let columnGap: CGFloat = 24
    nonisolated static let leftWidth: CGFloat = 280
    /// Right column: the grid width the small calendar is scaled into. The
    /// window width stays 880, so the 40 pt margins come out of this column.
    nonisolated static let rightWidth: CGFloat = 496

    // MARK: - Right column (small calendar scaled by gridScale)
    nonisolated static let titleBandHeight: CGFloat = 32 * gridScale       // 48.39
    nonisolated static let titleGap: CGFloat = 8 * gridScale              // 12.10
    nonisolated static let weekdayBandHeight: CGFloat = 24 * gridScale     // 36.29
    nonisolated static let weekdayGap: CGFloat = 4 * gridScale            // 6.05
    nonisolated static let dateRowHeight: CGFloat = 48 * gridScale         // 72.59
    nonisolated static let monthTitleFont: CGFloat = 28
    nonisolated static let gridWeekdayFont: CGFloat = 12 * gridScale       // 18.15
    nonisolated static let navChevronFont: CGFloat = 14 * gridScale        // 21.17
    nonisolated static let navHit: CGFloat = 32 * gridScale                // 48.39
    nonisolated static let navGap: CGFloat = 8 * gridScale                 // 12.10
    nonisolated static let dayFont: CGFloat = 18 * gridScale               // 27.21
    nonisolated static let daySecondaryFont: CGFloat = 12 * gridScale      // 18.15
    nonisolated static let dayBadgeFont: CGFloat = 10 * gridScale          // 16.1
    nonisolated static let dayHighlight: CGFloat = 44 * gridScale          // 66.54
    nonisolated static let dayBadgeSize: CGFloat = 14 * gridScale          // 21.17
    nonisolated static let dayBadgeCorner: CGFloat = 3 * gridScale         // 4.54
    nonisolated static let dayBadgeInset: CGFloat = 3 * gridScale          // 4.54
    nonisolated static let dayDotSize: CGFloat = 4 * gridScale             // 6.05
    nonisolated static let dayDotArea: CGFloat = 6 * gridScale             // 9.07
    nonisolated static let dayTextSpacing: CGFloat = 2 * gridScale         // 3.02

    // MARK: - Left column (fixed top-down flow, rhythmScale)
    /// Shared with the right column so both titles sit on one baseline.
    nonisolated static let titleFont: CGFloat = 28
    nonisolated static let clockLabelHeight: CGFloat = 12 * rhythmScale     // 15.55
    nonisolated static let clockHeight: CGFloat = 56 * rhythmScale          // 72.59
    nonisolated static let clockFont: CGFloat = 44 * rhythmScale            // 57.03
    nonisolated static let postClockGap: CGFloat = 8 * rhythmScale          // 10.37
    nonisolated static let weekdayHeight: CGFloat = 20 * rhythmScale        // 25.92
    nonisolated static let weekdayFont: CGFloat = 16 * rhythmScale          // 20.74
    nonisolated static let isoWeekHeight: CGFloat = 16 * rhythmScale        // 20.74
    nonisolated static let isoFont: CGFloat = 12 * rhythmScale              // 15.55
    nonisolated static let preLunarGap: CGFloat = 6 * rhythmScale           // 7.78
    nonisolated static let lunarHeight: CGFloat = 20 * rhythmScale          // 25.92
    nonisolated static let lunarFont: CGFloat = 14 * rhythmScale            // 18.15
    nonisolated static let captionFont: CGFloat = 11 * rhythmScale          // 14.26
    nonisolated static let dividerTopGap: CGFloat = 10 * rhythmScale        // 12.96
    nonisolated static let dividerSlotHeight: CGFloat = 1
    nonisolated static let dividerBottomGap: CGFloat = 10 * rhythmScale     // 12.96
    nonisolated static let eventCardHeight: CGFloat = 40 * rhythmScale      // 51.85
    nonisolated static let eventSpacing: CGFloat = 6 * rhythmScale          // 7.78

    // MARK: - Event card metrics (left column rhythm)
    nonisolated static let infoLabelWidth: CGFloat = 28 * rhythmScale       // 36.29
    nonisolated static let infoGap: CGFloat = 8 * rhythmScale               // 10.37
    nonisolated static let infoCardPadding: CGFloat = 12 * rhythmScale      // 15.55
    nonisolated static let infoCardCorner: CGFloat = 10 * rhythmScale       // 12.96
    nonisolated static let infoRuleWidth: CGFloat = 3 * rhythmScale         // 3.89
    nonisolated static let infoBodyFont: CGFloat = 12 * rhythmScale         // 15.55
    nonisolated static let infoCaptionFont: CGFloat = 11 * rhythmScale      // 14.26
    nonisolated static let infoBadgeFont: CGFloat = 9 * rhythmScale         // 11.67
    nonisolated static let infoTagPadding: CGFloat = 8 * rhythmScale        // 10.37

    /// Three cards plus their gaps; more than three scroll inside this height.
    nonisolated static var eventAreaHeight: CGFloat { 3 * eventCardHeight + 2 * eventSpacing }

    /// Top band before the first date row.
    nonisolated static var gridTopHeight: CGFloat { titleBandHeight + titleGap + weekdayBandHeight + weekdayGap }

    /// Offset of the event area's top inside the left column.
    nonisolated static var eventAreaTop: CGFloat {
        titleBandHeight + titleGap + clockLabelHeight + clockHeight + postClockGap
            + weekdayHeight + isoWeekHeight + preLunarGap + lunarHeight
            + dividerTopGap + dividerSlotHeight + dividerBottomGap
    }

    /// Left column is a fixed flow; no flexible spacer is allowed.
    nonisolated static var leftColumnHeight: CGFloat { eventAreaTop + eventAreaHeight }

    /// Right column natural height R = 64n-equivalent: 109.4 + 77.3n.
    nonisolated static func rightColumnHeight(rows: Int) -> CGFloat {
        gridTopHeight + dateRowHeight * CGFloat(rows)
    }

    /// Shared column height B = max(left, right).
    nonisolated static func blockHeight(rows: Int) -> CGFloat {
        max(leftColumnHeight, rightColumnHeight(rows: rows))
    }

    /// Base window content height H = B + 40 + 40.
    nonisolated static func contentHeight(rows: Int) -> CGFloat {
        blockHeight(rows: rows) + margin * 2
    }

    /// Base content size for a month with n rows.
    nonisolated static func contentSize(rows: Int, scale: CGFloat) -> CGSize {
        CGSize(width: baseWidth * scale, height: contentHeight(rows: rows) * scale)
    }

    /// Live display scale from the real container size for this month.
    nonisolated static func scale(contentSize: CGSize, rows: Int) -> CGFloat {
        guard contentSize.width > 0, contentSize.height > 0 else { return 1 }
        let height = contentHeight(rows: rows)
        return max(0.1, min(contentSize.width / baseWidth, contentSize.height / height))
    }
}

/// Content of the global hot-key calendar panel. Width is a fixed 880 pt and the
/// height follows the month's real row count; the display scale is derived from
/// the live container size so a real window drag scales the content continuously
/// (docs/CALENDAR_PANEL_FINAL_LAYOUT.md).
struct CalendarPanelView: View {
    let model: CalendarModel
    let clock: PanelClock
    var onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let rows = model.weeks.count
            let s = PanelLayout.scale(contentSize: proxy.size, rows: rows)
            content(scale: s, rows: rows)
                .frame(
                    width: PanelLayout.baseWidth * s,
                    height: PanelLayout.contentHeight(rows: rows) * s
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .onAppear { logGeometry(proxy.size, s) }
                .onChange(of: proxy.size) { _, size in
                    logGeometry(size, PanelLayout.scale(contentSize: size, rows: rows))
                }
        }
        .ignoresSafeArea()
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { model.moveSelection(byDays: -1); return .handled }
        .onKeyPress(.rightArrow) { model.moveSelection(byDays: 1); return .handled }
        .onKeyPress(.upArrow) { model.moveSelection(byDays: -7); return .handled }
        .onKeyPress(.downArrow) { model.moveSelection(byDays: 7); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(.init("t")) { model.resetToToday(); return .handled }
        .background(Color.clear)
    }

    // MARK: - Equal-margin content block

    /// Both columns are top-aligned inside one block with equal 24 pt margins on
    /// all four sides; the shorter column keeps its difference at its own end.
    private func content(scale s: CGFloat, rows: Int) -> some View {
        HStack(alignment: .top, spacing: PanelLayout.columnGap * s) {
            leftColumn(scale: s)
            rightColumn(scale: s, rows: rows)
        }
        .padding(PanelLayout.margin * s)
        .frame(
            width: PanelLayout.baseWidth * s,
            height: PanelLayout.contentHeight(rows: rows) * s,
            alignment: .top
        )
    }

    // MARK: - Left column

    private func leftColumn(scale s: CGFloat) -> some View {
        VStack(spacing: 0) {
            titleBand(model.selectedGregorianTitle, scale: s)

            Gap(height: PanelLayout.titleGap * s)

            Text("当前时间")
                .font(.system(size: PanelLayout.captionFont * s))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 12 * s)

            Text(clock.timeString)
                .font(.system(size: PanelLayout.clockFont * s, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .frame(height: 56 * s)

            Gap(height: 8 * s)

            Text(model.selectedWeekdayText)
                .font(.system(size: PanelLayout.weekdayFont * s, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 20 * s)

            Text(model.selectedISOWeekText)
                .font(.system(size: PanelLayout.isoFont * s))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 16 * s)

            Gap(height: PanelLayout.preLunarGap * s)

            Text(model.showsLunarInDetail ? model.selectedLunarSummary : " ")
                .font(.system(size: PanelLayout.lunarFont * s, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .frame(height: PanelLayout.lunarHeight * s)
                .accessibilityLabel(model.selectedLunarSummary)

            Gap(height: PanelLayout.dividerTopGap * s)
                .overlay(alignment: .bottomTrailing) { hintText(scale: s) }

            // Horizontal separator; its slot never moves with the event count.
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: PanelLayout.dividerSlotHeight * s)

            Gap(height: PanelLayout.dividerBottomGap * s)

            eventSection(scale: s)
        }
        .frame(width: PanelLayout.leftWidth * s, height: PanelLayout.leftColumnHeight * s, alignment: .top)
    }

    /// Low-key trailing hint near the separator: source failure note, or the
    /// overflow count when there are more than three events. Overlaid inside an
    /// existing gap so it never takes event capacity or grows the window.
    @ViewBuilder
    private func hintText(scale s: CGFloat) -> some View {
        let overflow = eventItems.count > 3
        if let hint = model.detail?.sourceNote ?? (overflow ? "共 \(eventItems.count) 条" : nil) {
            Text(hint)
                .font(.system(size: 10 * s))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// Shared 32×s title band; the right column uses the same band so the two
    /// titles sit on one baseline.
    private func titleBand(_ text: String, scale s: CGFloat) -> some View {
        Text(text)
            .font(.system(size: PanelLayout.titleFont * s, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
            .frame(height: PanelLayout.titleBandHeight * s)
    }

    private struct EventItem: Identifiable {
        let id: String
        let text: String
        let tag: HolidayProvider.Marker?
        let help: String?
    }

    private var eventItems: [EventItem] {
        guard let detail = model.detail else { return [] }
        var items: [EventItem] = [EventItem(id: "relative", text: detail.relative, tag: nil, help: nil)]
        for festival in detail.festivals {
            items.append(EventItem(
                id: festival.id,
                text: festival.title,
                tag: festival.marker,
                help: festival.sourceTitle.map { "来源：\($0)" } ?? festival.title
            ))
        }
        if detail.festivals.isEmpty, let marker = detail.marker {
            items.append(EventItem(id: "marker", text: marker == .holiday ? "休息" : "补班", tag: marker, help: nil))
        }
        return items
    }

    /// Up to three rows are a plain list on the shared bottom line; more than
    /// three reuse the same 132 pt area as a scrollable overflow (no scrollbars).
    @ViewBuilder
    private func eventSection(scale s: CGFloat) -> some View {
        let metrics = CalendarInfoMetrics.panel(scale: s)
        let items = eventItems
        let list = VStack(alignment: .leading, spacing: PanelLayout.eventSpacing * s) {
            ForEach(items) { item in
                CalendarInfoRow(text: item.text, tag: item.tag, help: item.help, metrics: metrics)
                    .frame(height: PanelLayout.eventCardHeight * s)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if items.count <= 3 {
            list.frame(height: PanelLayout.eventAreaHeight * s, alignment: .top)
        } else {
            ScrollView(.vertical) {
                list
            }
            .frame(height: PanelLayout.eventAreaHeight * s)
            .scrollIndicators(.hidden)
            .accessibilityLabel("共 \(items.count) 条事件，可滚动查看全部")
        }
    }

    // MARK: - Right column

    private func rightColumn(scale s: CGFloat, rows: Int) -> some View {
        VStack(spacing: 0) {
            navBand(scale: s)
            Gap(height: PanelLayout.titleGap * s)
            weekdayRow(scale: s)
                .frame(height: PanelLayout.weekdayBandHeight * s)
            Gap(height: PanelLayout.weekdayGap * s)
            monthGrid(scale: s)
        }
        .frame(
            width: PanelLayout.rightWidth * s,
            height: PanelLayout.rightColumnHeight(rows: rows) * s,
            alignment: .top
        )
    }

    /// Single month arrows inside, double year arrows outside; the month title
    /// stays centered because both button groups are equally wide.
    private func navBand(scale s: CGFloat) -> some View {
        ZStack {
            Text(monthTitle)
                .font(.system(size: PanelLayout.monthTitleFont * s, weight: .medium))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 0) {
                HStack(spacing: PanelLayout.navGap * s) {
                    navButton("chevron.left.2", label: "上一年", scale: s) { model.goToPreviousYear() }
                    navButton("chevron.left", label: "上一个月", scale: s) { model.goToPreviousMonth() }
                }
                Spacer(minLength: 0)
                HStack(spacing: PanelLayout.navGap * s) {
                    navButton("chevron.right", label: "下一个月", scale: s) { model.goToNextMonth() }
                    navButton("chevron.right.2", label: "下一年", scale: s) { model.goToNextYear() }
                }
            }
        }
        .frame(height: PanelLayout.titleBandHeight * s)
    }

    private func navButton(_ symbol: String, label: String, scale s: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: PanelLayout.navChevronFont * s, weight: .medium))
                .frame(width: PanelLayout.navHit * s, height: PanelLayout.navHit * s)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private var monthTitle: String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: model.visibleMonth)
        let month = calendar.component(.month, from: model.visibleMonth)
        return "\(year)年\(month)月"
    }

    private func weekdayRow(scale s: CGFloat) -> some View {
        let ordered = model.orderedWeekdaySymbols
        let columnWidth = PanelLayout.rightWidth * s / 7
        return HStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: PanelLayout.gridWeekdayFont * s, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: columnWidth, height: PanelLayout.weekdayBandHeight * s)
            }
        }
    }

    private func monthGrid(scale s: CGFloat) -> some View {
        let gridWidth = PanelLayout.rightWidth * s
        let metrics = CalendarGridMetrics.panel(scale: s, gridWidth: gridWidth)
        return VStack(spacing: 0) {
            ForEach(model.weeks) { week in
                HStack(spacing: 0) {
                    ForEach(week.days) { day in
                        CalendarDayCell(day: day, metrics: metrics, colorScheme: colorScheme) { model.select($0) }
                            .frame(width: metrics.columnWidth, height: metrics.rowHeight)
                    }
                }
            }
        }
        .frame(width: gridWidth)
    }
}

/// Validation aid: reports the live container size and derived scale so the
/// resize path can be checked without synthetic input.
private func logGeometry(_ size: CGSize, _ scale: CGFloat) {
    #if DEBUG
    guard ProcessInfo.processInfo.environment["CALMON_PANEL_HOLD"] == "1" else { return }
    FileHandle.standardError.write(Data("CALMON_PANEL_GEOMETRY container=\(size) scale=\(scale)\n".utf8))
    #endif
}

/// Fixed-size vertical gap so scaled positions stay predictable.
private struct Gap: View {
    let height: CGFloat
    var body: some View { Color.clear.frame(height: height) }
}
