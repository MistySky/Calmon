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
        HStack(spacing: 0) {
            Button {
                model.goToPreviousMonth()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: UIStyle.Metrics.calendarChevronHit, height: UIStyle.Metrics.calendarChevronHit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上一个月")

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                Text(monthTitle)
                    .font(UIStyle.Fonts.panelTitle)
                    .accessibilityAddTraits(.isHeader)
                if model.showsTodayButton {
                    Button("今天") { model.resetToToday() }
                        .buttonStyle(.link)
                        .controlSize(.small)
                        .accessibilityLabel("回到今天")
                }
            }

            Spacer(minLength: 4)

            Button {
                model.goToNextMonth()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: UIStyle.Metrics.calendarChevronHit, height: UIStyle.Metrics.calendarChevronHit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下一个月")
        }
        .frame(height: UIStyle.Metrics.calendarHeaderHeight)
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
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ZStack {
                    if day.isToday {
                        Circle().fill(UIStyle.Colors.today).frame(width: UIStyle.Metrics.dayHighlight, height: UIStyle.Metrics.dayHighlight)
                    } else if day.isSelected {
                        Circle().fill(UIStyle.selectedDayFill(colorScheme)).frame(width: UIStyle.Metrics.dayHighlight, height: UIStyle.Metrics.dayHighlight)
                    }
                    VStack(spacing: 1) {
                        Text("\(day.dayNumber)")
                            .font(day.isToday ? UIStyle.Fonts.dayNumberToday : UIStyle.Fonts.dayNumber)
                            .monospacedDigit()
                            .foregroundStyle(numberColor(day))
                        if let second = day.secondLine {
                            Text(second)
                                .font(UIStyle.Fonts.gridSecondary)
                                .foregroundStyle(secondLineColor(day))
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: columnWidth - 4)
                        }
                    }
                }
                .frame(height: UIStyle.Metrics.dayHighlight)

                Circle()
                    .fill(UIStyle.Colors.festivalDot)
                    .frame(width: UIStyle.Metrics.festivalDot, height: UIStyle.Metrics.festivalDot)
                    .opacity(day.showsDot ? 1 : 0)
                    .frame(height: UIStyle.Metrics.festivalDotArea)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let badge = day.badge {
                badgeView(badge)
                    .opacity(day.isCurrentMonth ? 1 : 0.45)
                    .offset(x: -UIStyle.Metrics.badgeInset, y: UIStyle.Metrics.badgeInset)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { model.select(day.date) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityAddTraits(day.isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private func numberColor(_ day: CalendarModel.DayCell) -> Color {
        if day.isToday { return .white }
        if !day.isCurrentMonth { return Color(nsColor: .tertiaryLabelColor) }
        return .primary
    }

    private func secondLineColor(_ day: CalendarModel.DayCell) -> Color {
        if day.isToday { return .white }
        if !day.isCurrentMonth { return Color(nsColor: .tertiaryLabelColor) }
        return .secondary
    }

    private func badgeView(_ marker: HolidayProvider.Marker) -> some View {
        let isHoliday = marker == .holiday
        return Text(isHoliday ? "休" : "班")
            .font(UIStyle.Fonts.badge)
            .foregroundStyle(.white)
            .frame(width: UIStyle.Metrics.badgeSize, height: UIStyle.Metrics.badgeSize)
            .background(
                RoundedRectangle(cornerRadius: UIStyle.Metrics.badgeCorner, style: .continuous)
                    .fill(isHoliday ? UIStyle.Colors.restBadgeBackground : UIStyle.Colors.workBadgeBackground)
            )
            .accessibilityHidden(true)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailSection: some View {
        if let detail = model.detail {
            VStack(alignment: .leading, spacing: 8) {
                summaryRow(detail)

                // Relative date and festivals share one information-row style.
                infoRow(text: detail.relative, tag: nil)

                ForEach(detail.festivals) { festival in
                    infoRow(text: festival.title, tag: festival.marker)
                        .help(festival.sourceTitle.map { "来源：\($0)" } ?? festival.title)
                }

                if detail.festivals.isEmpty, let marker = detail.marker {
                    infoRow(text: marker == .holiday ? "休息" : "补班", tag: marker)
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

    /// Narrow "全天" column + a light rounded block with a short green rule.
    /// This is date/festival information, not a personal event.
    private func infoRow(text: String, tag: HolidayProvider.Marker?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("全天")
                .font(UIStyle.Fonts.caption)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
                .padding(.top, 6)

            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(UIStyle.Colors.festivalDot)
                    .frame(width: 3)
                Text(text)
                    .font(UIStyle.Fonts.body)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let tag {
                    tagView(tag)
                }
            }
            .padding(UIStyle.Metrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: UIStyle.Metrics.cardCorner, style: .continuous)
                    .fill(UIStyle.Colors.cardBackground)
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("全天 \(text)")
    }

    private func tagView(_ marker: HolidayProvider.Marker) -> some View {
        let isHoliday = marker == .holiday
        return Text(isHoliday ? "休息" : "补班")
            .font(UIStyle.Fonts.badge)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(isHoliday ? UIStyle.Colors.restBadgeBackground : UIStyle.Colors.workBadgeBackground)
            )
    }
}
