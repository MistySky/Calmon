import AppKit
import SwiftUI

/// Single source of truth for all shared visual constants (docs/UI_SPEC.md).
/// No theme framework, no second set of fonts/corners/colors.
enum UIStyle {

    // MARK: - Fonts

    enum Fonts {
        static let panelTitle = SwiftUI.Font.system(size: 14, weight: .medium)
        static let body = SwiftUI.Font.system(size: 12)
        static let groupTitle = SwiftUI.Font.system(size: 12, weight: .medium)
        static let caption = SwiftUI.Font.system(size: 11)
        static let weekday = SwiftUI.Font.system(size: 11, weight: .medium)
        static let dayNumber = SwiftUI.Font.system(size: 14)
        static let dayNumberToday = SwiftUI.Font.system(size: 14, weight: .medium)
        static let gridSecondary = SwiftUI.Font.system(size: 10.5)
        static let badge = SwiftUI.Font.system(size: 9, weight: .medium)
        static let ringPercent = SwiftUI.Font.system(size: 18, weight: .medium)

        static let menuBarDate = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        static let menuBarMetric = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)
    }

    // MARK: - Metrics

    enum Metrics {
        static let contentMargin: CGFloat = 16
        static let groupSpacing: CGFloat = 16
        static let titleGap: CGFloat = 8
        static let cardPadding: CGFloat = 12
        static let cardSpacing: CGFloat = 8
        static let cardCorner: CGFloat = 10

        static let dayHighlight: CGFloat = 34
        static let badgeSize: CGFloat = 12
        static let badgeCorner: CGFloat = 3
        static let badgeInset: CGFloat = 2
        static let festivalDot: CGFloat = 4
        static let festivalDotArea: CGFloat = 6

        static let calendarPanelWidth: CGFloat = 360
        static let calendarGridWidth: CGFloat = 328
        static let calendarRowHeight: CGFloat = 48
        static let calendarHeaderHeight: CGFloat = 32
        static let calendarChevronHit: CGFloat = 28

        static let monitoringPanelWidth: CGFloat = 400
        static let settingsWidth: CGFloat = 420

        static let ringDiameter: CGFloat = 64
        static let ringLineWidth: CGFloat = 6
        static let searchFieldWidth: CGFloat = 130
        static let applicationRowHeight: CGFloat = 36
        static let applicationIcon: CGFloat = 20
        static let applicationBarWidth: CGFloat = 64
        static let applicationBarHeight: CGFloat = 6
        static let applicationValueWidth: CGFloat = 64
    }

    // MARK: - Colors

    enum Colors {
        static let today = Color(nsColor: .systemRed)

        static let cpuRing = Color(nsColor: .systemGreen)
        static let memoryRing = Color(nsColor: .systemIndigo)
        static let diskRing = Color(nsColor: .systemOrange)

        static let track = Color(nsColor: .quaternaryLabelColor)
        static let applicationBar = Color(nsColor: .systemBlue)
        static let festivalDot = Color(nsColor: .systemGreen)
        static let restBadgeBackground = Color(nsColor: .systemRed)
        static let workBadgeBackground = Color(nsColor: .systemGray)

        /// Single content-card background shared by both popovers so their
        /// material role is identical (docs/UI_REVIEW_FOLLOWUP.md U5).
        static let cardBackground = Color(nsColor: .quaternaryLabelColor).opacity(0.25)
    }

    /// Light-red fill for the selected (non-today) day: 16% light / 24% dark.
    static func selectedDayFill(_ scheme: ColorScheme) -> Color {
        Color.red.opacity(scheme == .dark ? 0.24 : 0.16)
    }

    // MARK: - Formatting

    private static let gib = 1_073_741_824.0
    private static let mib = 1_048_576.0

    /// Memory sizes use binary units (1024 base) labelled MB/GB, matching
    /// Activity Monitor and the physical RAM macOS reports. Per docs/MONITORING.md §6.
    static func memoryString(_ bytes: UInt64) -> String {
        if bytes >= UInt64(gib) {
            return String(format: "%.2f GB", Double(bytes) / gib)
        }
        if bytes == 0 { return "0 MB" }
        let mb = Double(bytes) / mib
        if mb < 1 { return "<1 MB" }
        return String(format: "%.0f MB", mb.rounded())
    }

    /// Whole-machine memory capacity: binary GB, at most one decimal, no trailing .0.
    static func memoryCapacityString(_ bytes: UInt64) -> String {
        let value = (Double(bytes) / gib * 10).rounded() / 10
        return value == value.rounded() ? String(format: "%.0f GB", value) : String(format: "%.1f GB", value)
    }

    /// Disk capacity uses decimal GB, matching Finder. Per docs/MONITORING.md §6.
    static func diskCapacityString(_ bytes: UInt64) -> String {
        let value = (Double(bytes) / 1_000_000_000 * 10).rounded() / 10
        return value == value.rounded() ? String(format: "%.0f GB", value) : String(format: "%.1f GB", value)
    }

    static func percentString(_ percent: Double?) -> String {
        guard let percent, percent.isFinite else { return "--%" }
        return "\(Int(percent.rounded()))%"
    }
}
