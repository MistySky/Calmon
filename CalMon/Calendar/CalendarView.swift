import SwiftUI

struct CalendarView: View {
    let model: CalendarModel
    let maxHeight: CGFloat
    var onClose: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var gridWidth: CGFloat { UIStyle.Metrics.calendarGridWidth }
    private var columnWidth: CGFloat { gridWidth / 7 }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, UIStyle.Metrics.titleGap)
                weekdayRow
                    .padding(.bottom, 4)
                monthGrid
                Divider()
                    .padding(.vertical, 12)
                detailSection
            }
            .padding(UIStyle.Metrics.contentMargin)
            .frame(width: UIStyle.Metrics.calendarPanelWidth)
        }
        .frame(width: UIStyle.Metrics.calendarPanelWidth)
        .frame(maxHeight: maxHeight)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { model.moveSelection(byDays: -1); return .handled }
        .onKeyPress(.rightArrow) { model.moveSelection(byDays: 1); return .handled }
        .onKeyPress(.upArrow) { model.moveSelection(byDays: -7); return .handled }
        .onKeyPress(.downArrow) { model.moveSelection(byDays: 7); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
        .onKeyPress(.init("t")) { model.resetToToday(); return .handled }
    }

    // MARK: - Header

    private var monthTitle: String {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: model.visibleMonth)
        let month = calendar.component(.month, from: model.visibleMonth)
        return "\(year)年\(month)月"
    }

    private var header: some View {
        ZStack {
            HStack(spacing: 6) {
                Text(monthTitle)
                    .font(UIStyle.Fonts.panelTitle)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if model.showsTodayButton {
                    Button("今天") { model.resetToToday() }
                        .buttonStyle(.link)
                        .controlSize(.small)
                        .accessibilityLabel("回到今天")
                }
            }

            HStack(spacing: 0) {
                HStack(spacing: yearChevronGap) {
                    navButton("chevron.left.2", label: "上一年") { model.goToPreviousYear() }
                    navButton("chevron.left", label: "上一个月") { model.goToPreviousMonth() }
                }
                Spacer(minLength: 0)
                HStack(spacing: yearChevronGap) {
                    navButton("chevron.right", label: "下一个月") { model.goToNextMonth() }
                    navButton("chevron.right.2", label: "下一年") { model.goToNextYear() }
                }
            }
        }
        .frame(height: UIStyle.Metrics.calendarHeaderHeight)
    }

    /// Small-calendar navigation button: existing single-chevron size and hit area.
    private var yearChevronGap: CGFloat { 4 }

    private func navButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: UIStyle.Metrics.calendarChevronHit, height: UIStyle.Metrics.calendarChevronHit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    private var weekdayRow: some View {
        let ordered = model.orderedWeekdaySymbols
        return HStack(spacing: 0) {
            ForEach(Array(ordered.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(UIStyle.Fonts.weekday)
                    .foregroundStyle(.secondary)
                    .frame(width: columnWidth, height: 22)
            }
        }
        .frame(width: gridWidth)
    }

    // MARK: - Grid

    private var monthGrid: some View {
        VStack(spacing: 0) {
            ForEach(model.weeks) { week in
                HStack(spacing: 0) {
                    ForEach(week.days) { day in
                        dayCell(day)
                            .frame(width: columnWidth, height: UIStyle.Metrics.calendarRowHeight)
                    }
                }
            }
        }
        .frame(width: gridWidth)
    }

    private func dayCell(_ day: CalendarModel.DayCell) -> some View {
        CalendarDayCell(day: day, metrics: .popover, colorScheme: colorScheme) { model.select($0) }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailSection: some View {
        if let detail = model.detail {
            VStack(alignment: .leading, spacing: 8) {
                summaryRow(detail)

                // Relative date and festivals share one information-row style.
                CalendarInfoRow(text: detail.relative, tag: nil, metrics: .popover)

                ForEach(detail.festivals) { festival in
                    CalendarInfoRow(text: festival.title, tag: festival.marker, help: festival.sourceTitle.map { "来源：\($0)" } ?? festival.title, metrics: .popover)
                }

                if detail.festivals.isEmpty, let marker = detail.marker {
                    CalendarInfoRow(text: marker == .holiday ? "休息" : "补班", tag: marker, metrics: .popover)
                }

                if let sourceNote = detail.sourceNote {
                    Text(sourceNote)
                        .font(UIStyle.Fonts.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Single-line summary: date + ISO week on the left, lunar year/生肖/月日 on
    /// the right (right side collapses when 农历 is off).
    private func summaryRow(_ detail: CalendarModel.Detail) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(detail.summaryDate)
                .font(UIStyle.Fonts.body)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Spacer(minLength: 8)
            if model.showsLunarInDetail {
                Text(detail.lunarSummary)
                    .font(UIStyle.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
        }
    }

}
