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
    // MARK: - Shell

    /// The window keeps the accepted overall proportion. The calendar itself is
    /// narrower than its column so its seven columns no longer feel stretched.
    nonisolated static let margin: CGFloat = 50
    nonisolated static var baseWidth: CGFloat { margin * 2 + leftWidth + columnGap + rightColumnWidth }
    nonisolated static let columnGap: CGFloat = 24
    nonisolated static let leftWidth: CGFloat = 280
    nonisolated static let rightColumnWidth: CGFloat = 609.70

    // MARK: - Shared title / right calendar

    nonisolated static let titleBandHeight: CGFloat = 44
    nonisolated static let titleGap: CGFloat = 12
    nonisolated static let weekdayBandHeight: CGFloat = 32
    nonisolated static let weekdayGap: CGFloat = 8
    nonisolated static let dateRowHeight: CGFloat = 64
    nonisolated static let cellWidth: CGFloat = 80
    nonisolated static var rightWidth: CGFloat { cellWidth * 7 }          // 560
    nonisolated static let monthTitleFont: CGFloat = 28
    nonisolated static let gridWeekdayFont: CGFloat = 16
    nonisolated static let navChevronFont: CGFloat = 18
    nonisolated static let navHit: CGFloat = 44
    nonisolated static let navGap: CGFloat = 4
    nonisolated static var navGroupWidth: CGFloat { navHit * 2 + navGap }
    nonisolated static let navTitleWidth: CGFloat = 170
    nonisolated static let dayFont: CGFloat = 24
    nonisolated static let daySecondaryFont: CGFloat = 16
    nonisolated static let dayBadgeFont: CGFloat = 12
    nonisolated static let dayDotSize: CGFloat = 5
    /// Highlight + dot area fill the date row exactly; growing the marker just
    /// moves the dot down, so the box can be as large as the row allows.
    nonisolated static let dayHighlight: CGFloat = 60
    nonisolated static var dayDotArea: CGFloat { dateRowHeight - dayHighlight }
    nonisolated static let dayBadgeSize: CGFloat = 18
    nonisolated static let dayBadgeCorner: CGFloat = 4
    nonisolated static let dayBadgeInset: CGFloat = 3
    nonisolated static let dayTextSpacing: CGFloat = 2

    // MARK: - Left column

    nonisolated static let titleFont: CGFloat = 28
    nonisolated static let clockLabelHeight: CGFloat = 16
    nonisolated static let clockLabelToClockGap: CGFloat = 4
    nonisolated static let clockHeight: CGFloat = 60
    nonisolated static let clockFont: CGFloat = 52
    nonisolated static let postClockGap: CGFloat = 12
    nonisolated static let weekdayHeight: CGFloat = 24
    nonisolated static let weekdayFont: CGFloat = 18
    nonisolated static let isoWeekHeight: CGFloat = 20
    nonisolated static let isoFont: CGFloat = 14
    nonisolated static let preLunarGap: CGFloat = 8
    nonisolated static let lunarHeight: CGFloat = 24
    nonisolated static let lunarFont: CGFloat = 16
    nonisolated static let captionFont: CGFloat = 13
    nonisolated static let dividerTopGap: CGFloat = 20
    nonisolated static let dividerSlotHeight: CGFloat = 1
    nonisolated static let dividerBottomGap: CGFloat = 16
    nonisolated static let eventCardHeight: CGFloat = 48
    nonisolated static let eventSpacing: CGFloat = 8

    // MARK: - Event card metrics
    nonisolated static let infoLabelWidth: CGFloat = 32
    nonisolated static let infoGap: CGFloat = 10
    nonisolated static let infoCardPadding: CGFloat = 14
    nonisolated static let infoCardCorner: CGFloat = 12
    nonisolated static let infoRuleWidth: CGFloat = 3
    nonisolated static let infoBodyFont: CGFloat = 15
    nonisolated static let infoCaptionFont: CGFloat = 13
    nonisolated static let infoBadgeFont: CGFloat = 11
    nonisolated static let infoTagPadding: CGFloat = 8

    /// Fixed six-row grid: the panel height never depends on the month.
    nonisolated static let gridRows = 6
    /// Three cards plus their gaps; more than three scroll inside this height.
    nonisolated static var eventAreaHeight: CGFloat { 3 * eventCardHeight + 2 * eventSpacing }

    /// Top band before the first date row.
    nonisolated static var gridTopHeight: CGFloat { titleBandHeight + titleGap + weekdayBandHeight + weekdayGap }

    /// Offset of the event area's top inside the left column.
    nonisolated static var eventAreaTop: CGFloat {
        titleBandHeight + titleGap + clockLabelHeight + clockLabelToClockGap + clockHeight + postClockGap
            + weekdayHeight + isoWeekHeight + preLunarGap + lunarHeight
            + dividerTopGap + dividerSlotHeight + dividerBottomGap
    }

    /// Left column's fixed flow: date, time, extra date info, then events.
    /// No flexible gap is inserted anywhere, so the events sit right below the
    /// divider and are top-aligned inside their three-card area.
    nonisolated static var leftColumnFlow: CGFloat { eventAreaTop + eventAreaHeight }

    /// Right column height for the fixed six-row grid.
    nonisolated static var rightColumnHeight: CGFloat {
        gridTopHeight + dateRowHeight * CGFloat(gridRows)
    }

    /// Shared column height B; the fixed six-row grid drives it.
    nonisolated static var blockHeight: CGFloat {
        max(leftColumnFlow, rightColumnHeight)
    }

    /// Base window content height H = B + 50 + 50.
    nonisolated static var contentHeight: CGFloat { blockHeight + margin * 2 }

    /// Base content size.
    nonisolated static func contentSize(scale: CGFloat) -> CGSize {
        CGSize(width: baseWidth * scale, height: contentHeight * scale)
    }

    /// Live display scale from the real container size.
    nonisolated static func scale(contentSize: CGSize) -> CGFloat {
        guard contentSize.width > 0, contentSize.height > 0 else { return 1 }
        return max(0.1, min(contentSize.width / baseWidth, contentSize.height / contentHeight))
    }
}

/// Content of the global hot-key calendar panel. It uses one fixed six-row
/// calendar and derives a single display scale from the live container size, so
/// a real window drag scales the shell and every internal metric together.
struct CalendarPanelView: View {
    let model: CalendarModel
    let clock: PanelClock
    var onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let s = PanelLayout.scale(contentSize: proxy.size)
            content(scale: s)
                .frame(
                    width: PanelLayout.baseWidth * s,
                    height: PanelLayout.contentHeight * s
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .onAppear { logGeometry(proxy.size, s) }
                .onChange(of: proxy.size) { _, size in
                    logGeometry(size, PanelLayout.scale(contentSize: size))
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

    /// Both columns are top-aligned inside one block with equal outer margins.
    private func content(scale s: CGFloat) -> some View {
        HStack(alignment: .top, spacing: PanelLayout.columnGap * s) {
            leftColumn(scale: s)
            rightColumn(scale: s)
        }
        .padding(PanelLayout.margin * s)
        .frame(
            width: PanelLayout.baseWidth * s,
            height: PanelLayout.contentHeight * s,
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
                .frame(height: PanelLayout.clockLabelHeight * s)

            Gap(height: PanelLayout.clockLabelToClockGap * s)

            Text(clock.timeString)
                .font(.system(size: PanelLayout.clockFont * s, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .frame(height: PanelLayout.clockHeight * s)

            Gap(height: PanelLayout.postClockGap * s)

            Text(model.selectedWeekdayText)
                .font(.system(size: PanelLayout.weekdayFont * s, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: PanelLayout.weekdayHeight * s)

            Text(model.selectedISOWeekText)
                .font(.system(size: PanelLayout.isoFont * s))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: PanelLayout.isoWeekHeight * s)

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
        .frame(width: PanelLayout.leftWidth * s, height: PanelLayout.blockHeight * s, alignment: .top)
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
        // Validation aid only: `CALMON_PANEL_EVENTS=1|3` renders that many fixed
        // placeholder rows so the panel layout can be reviewed without live
        // calendar data. Never set in normal use; it is not real event data.
        if let raw = ProcessInfo.processInfo.environment["CALMON_PANEL_EVENTS"],
           let count = Int(raw), count > 0 {
            let fixtures = ["距今天还有 14 天", "国庆节", "国庆节（休）"]
            return fixtures.prefix(count).enumerated().map { index, text in
                EventItem(id: "fixture-\(index)", text: text, tag: nil, help: nil)
            }
        }
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

    /// Up to three rows are a plain top-aligned list; more than three reuse the
    /// same area as a scrollable overflow with hidden indicators.
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

    private func rightColumn(scale s: CGFloat) -> some View {
        VStack(spacing: 0) {
            navBand(scale: s)
            Gap(height: PanelLayout.titleGap * s)
            weekdayRow(scale: s)
                .frame(height: PanelLayout.weekdayBandHeight * s)
            Gap(height: PanelLayout.weekdayGap * s)
            monthGrid(scale: s)
        }
        .frame(
            width: PanelLayout.rightColumnWidth * s,
            height: PanelLayout.blockHeight * s,
            alignment: .top
        )
    }

    /// Navigation uses the calendar grid as its boundary: the left and right
    /// button groups have equal fixed widths, while the month stays at the
    /// absolute centre of the grid.
    private func navBand(scale s: CGFloat) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: PanelLayout.navGap * s) {
                navButton("chevron.left.2", label: "上一年", scale: s) { model.goToPreviousYear() }
                navButton("chevron.left", label: "上一个月", scale: s) { model.goToPreviousMonth() }
            }
            .frame(width: PanelLayout.navGroupWidth * s)

            Spacer(minLength: 0)

            Text(monthTitle)
                .font(.system(size: PanelLayout.monthTitleFont * s, weight: .medium))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .frame(width: PanelLayout.navTitleWidth * s)

            Spacer(minLength: 0)

            HStack(spacing: PanelLayout.navGap * s) {
                navButton("chevron.right", label: "下一个月", scale: s) { model.goToNextMonth() }
                navButton("chevron.right.2", label: "下一年", scale: s) { model.goToNextYear() }
            }
            .frame(width: PanelLayout.navGroupWidth * s)
        }
        .frame(width: PanelLayout.rightWidth * s)
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
        let weekend = model.orderedWeekdayIsWeekend
        let columnWidth = PanelLayout.rightWidth * s / 7
        return HStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.system(size: PanelLayout.gridWeekdayFont * s, weight: .medium))
                    .foregroundStyle(weekend[index] ? UIStyle.Colors.restBadgeBackground : Color.secondary)
                    .frame(width: columnWidth, height: PanelLayout.weekdayBandHeight * s)
            }
        }
    }

    private func monthGrid(scale s: CGFloat) -> some View {
        let gridWidth = PanelLayout.rightWidth * s
        let metrics = CalendarGridMetrics.panel(scale: s, gridWidth: gridWidth)
        return VStack(spacing: 0) {
            ForEach(model.gridWeeks(minimumRows: PanelLayout.gridRows)) { week in
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
