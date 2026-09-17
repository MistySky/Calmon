import SwiftUI

/// Sizes/fonts for the month grid, so the same day-cell rendering can serve the
/// menu bar popover (base values) and the hot-key panel (base × scale).
struct CalendarGridMetrics {
    var columnWidth: CGFloat
    var rowHeight: CGFloat
    var highlight: CGFloat
    var badgeSize: CGFloat
    var badgeCorner: CGFloat
    var badgeInset: CGFloat
    var dotSize: CGFloat
    var dotArea: CGFloat
    var dayFont: Font
    var dayFontToday: Font
    var secondaryFont: Font
    var badgeFont: Font
    var textSpacing: CGFloat

    static var popover: CalendarGridMetrics {
        CalendarGridMetrics(
            columnWidth: UIStyle.Metrics.calendarGridWidth / 7,
            rowHeight: UIStyle.Metrics.calendarRowHeight,
            highlight: UIStyle.Metrics.dayHighlight,
            badgeSize: UIStyle.Metrics.badgeSize,
            badgeCorner: UIStyle.Metrics.badgeCorner,
            badgeInset: UIStyle.Metrics.badgeInset,
            dotSize: UIStyle.Metrics.festivalDot,
            dotArea: UIStyle.Metrics.festivalDotArea,
            dayFont: UIStyle.Fonts.dayNumber,
            dayFontToday: UIStyle.Fonts.dayNumberToday,
            secondaryFont: UIStyle.Fonts.gridSecondary,
            badgeFont: UIStyle.Fonts.badge,
            textSpacing: 1
        )
    }

    /// Panel layout: the small calendar scaled up by ``PanelLayout/gridScale``
    /// (docs/CALENDAR_PANEL_FINAL_LAYOUT.md, user request 2026-09-17).
    static func panel(scale: CGFloat, gridWidth: CGFloat) -> CalendarGridMetrics {
        let s = scale
        return CalendarGridMetrics(
            columnWidth: gridWidth / 7,
            rowHeight: PanelLayout.dateRowHeight * s,
            highlight: PanelLayout.dayHighlight * s,
            badgeSize: PanelLayout.dayBadgeSize * s,
            badgeCorner: PanelLayout.dayBadgeCorner * s,
            badgeInset: PanelLayout.dayBadgeInset * s,
            dotSize: PanelLayout.dayDotSize * s,
            dotArea: PanelLayout.dayDotArea * s,
            dayFont: .system(size: PanelLayout.dayFont * s),
            dayFontToday: .system(size: PanelLayout.dayFont * s, weight: .medium),
            secondaryFont: .system(size: PanelLayout.daySecondaryFont * s),
            badgeFont: .system(size: PanelLayout.dayBadgeFont * s, weight: .medium),
            textSpacing: PanelLayout.dayTextSpacing * s
        )
    }
}

/// One month-grid day cell. Shared by the menu bar popover and the hot-key panel.
struct CalendarDayCell: View {
    let day: CalendarModel.DayCell
    let metrics: CalendarGridMetrics
    let colorScheme: ColorScheme
    let onSelect: (Date) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ZStack {
                    if day.isToday {
                        Circle().fill(UIStyle.Colors.today).frame(width: metrics.highlight, height: metrics.highlight)
                    } else if day.isSelected {
                        Circle().fill(UIStyle.selectedDayFill(colorScheme)).frame(width: metrics.highlight, height: metrics.highlight)
                    }
                    VStack(spacing: metrics.textSpacing) {
                        Text("\(day.dayNumber)")
                            .font(day.isToday ? metrics.dayFontToday : metrics.dayFont)
                            .monospacedDigit()
                            .foregroundStyle(numberColor)
                        if let second = day.secondLine {
                            Text(second)
                                .font(metrics.secondaryFont)
                                .foregroundStyle(secondLineColor)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: metrics.columnWidth - 4)
                        }
                    }
                }
                .frame(height: metrics.highlight)

                Circle()
                    .fill(UIStyle.Colors.festivalDot)
                    .frame(width: metrics.dotSize, height: metrics.dotSize)
                    .opacity(day.showsDot ? 1 : 0)
                    .frame(height: metrics.dotArea)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let badge = day.badge {
                CalendarBadge(marker: badge, size: metrics.badgeSize, corner: metrics.badgeCorner, font: metrics.badgeFont)
                    .opacity(day.isCurrentMonth ? 1 : 0.45)
                    .offset(x: -metrics.badgeInset, y: metrics.badgeInset)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(day.date) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityAddTraits(day.isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var numberColor: Color {
        if day.isToday { return .white }
        if !day.isCurrentMonth { return Color(nsColor: .tertiaryLabelColor) }
        return .primary
    }

    private var secondLineColor: Color {
        if day.isToday { return .white }
        if !day.isCurrentMonth { return Color(nsColor: .tertiaryLabelColor) }
        return .secondary
    }
}

/// 休/班 corner badge.
struct CalendarBadge: View {
    let marker: HolidayProvider.Marker
    let size: CGFloat
    let corner: CGFloat
    let font: Font

    var body: some View {
        let isHoliday = marker == .holiday
        return Text(isHoliday ? "休" : "班")
            .font(font)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(isHoliday ? UIStyle.Colors.restBadgeBackground : UIStyle.Colors.workBadgeBackground)
            )
            .accessibilityHidden(true)
    }
}

/// Sizes/fonts for a detail information row, scaled per surface.
struct CalendarInfoMetrics {
    var labelWidth: CGFloat
    var gap: CGFloat
    var cardPadding: CGFloat
    var cardCorner: CGFloat
    var ruleWidth: CGFloat
    var bodyFont: Font
    var captionFont: Font
    var badgeFont: Font
    var minHeight: CGFloat
    var tagPadding: CGFloat
    /// Panel event cards center their "全天" column against the card; the
    /// popover keeps the original top-aligned label.
    var labelCentered: Bool

    static var popover: CalendarInfoMetrics {
        CalendarInfoMetrics(
            labelWidth: 28,
            gap: 8,
            cardPadding: UIStyle.Metrics.cardPadding,
            cardCorner: UIStyle.Metrics.cardCorner,
            ruleWidth: 3,
            bodyFont: UIStyle.Fonts.body,
            captionFont: UIStyle.Fonts.caption,
            badgeFont: UIStyle.Fonts.badge,
            minHeight: 0,
            tagPadding: 8,
            labelCentered: false
        )
    }

    /// Panel event card metrics follow the left column's rhythm scale.
    static func panel(scale s: CGFloat) -> CalendarInfoMetrics {
        CalendarInfoMetrics(
            labelWidth: PanelLayout.infoLabelWidth * s,
            gap: PanelLayout.infoGap * s,
            cardPadding: PanelLayout.infoCardPadding * s,
            cardCorner: PanelLayout.infoCardCorner * s,
            ruleWidth: PanelLayout.infoRuleWidth * s,
            bodyFont: .system(size: PanelLayout.infoBodyFont * s),
            captionFont: .system(size: PanelLayout.infoCaptionFont * s),
            badgeFont: .system(size: PanelLayout.infoBadgeFont * s, weight: .medium),
            minHeight: PanelLayout.eventCardHeight * s,
            tagPadding: PanelLayout.infoTagPadding * s,
            labelCentered: true
        )
    }
}

/// One detail row: narrow "全天" column + light rounded card with a green rule.
struct CalendarInfoRow: View {
    let text: String
    let tag: HolidayProvider.Marker?
    var help: String?
    let metrics: CalendarInfoMetrics

    private var alignment: VerticalAlignment { metrics.labelCentered ? .center : .top }

    var body: some View {
        HStack(alignment: alignment, spacing: metrics.gap) {
            Text("全天")
                .font(metrics.captionFont)
                .foregroundStyle(.secondary)
                .frame(width: metrics.labelWidth, alignment: .leading)
                .padding(.top, metrics.labelCentered ? 0 : metrics.cardPadding / 2)

            HStack(alignment: .top, spacing: metrics.gap) {
                Rectangle()
                    .fill(UIStyle.Colors.festivalDot)
                    .frame(width: metrics.ruleWidth)
                Text(text)
                    .font(metrics.bodyFont)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: metrics.gap)
                if let tag {
                    CalendarTag(marker: tag, font: metrics.badgeFont, horizontalPadding: metrics.tagPadding)
                }
            }
            .padding(metrics.cardPadding)
            .frame(maxWidth: .infinity, minHeight: metrics.minHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: metrics.cardCorner, style: .continuous)
                    .fill(UIStyle.Colors.cardBackground)
            )
        }
        .frame(minHeight: metrics.minHeight > 0 ? metrics.minHeight : nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("全天 \(text)")
        .help(help ?? "")
    }
}

/// 休息/补班 capsule tag.
struct CalendarTag: View {
    let marker: HolidayProvider.Marker
    let font: Font
    let horizontalPadding: CGFloat

    var body: some View {
        let isHoliday = marker == .holiday
        return Text(isHoliday ? "休息" : "补班")
            .font(font)
            .foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(isHoliday ? UIStyle.Colors.restBadgeBackground : UIStyle.Colors.workBadgeBackground)
            )
    }
}
