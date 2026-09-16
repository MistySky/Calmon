import Foundation
import Observation
import ServiceManagement

/// Settings only. Persisted with UserDefaults; never holds business state such as
/// CPU snapshots or the visible calendar month.
@MainActor
@Observable
final class Preferences {

    static let shared = Preferences()

    private enum Key {
        static let showCalendar = "menuBar.calendar.enabled"
        static let showMonitoring = "menuBar.monitoring.enabled"
        static let showWeekday = "calendar.showWeekday"
        static let showLunar = "calendar.showLunar"
        static let showChineseHolidays = "calendar.chineseHolidays"
        static let weekStartsOnMonday = "calendar.weekStartsOnMonday"
    }

    private let defaults: UserDefaults

    var showCalendar: Bool { didSet { defaults.set(showCalendar, forKey: Key.showCalendar) } }
    var showMonitoring: Bool { didSet { defaults.set(showMonitoring, forKey: Key.showMonitoring) } }
    var showWeekday: Bool { didSet { defaults.set(showWeekday, forKey: Key.showWeekday) } }
    var showLunar: Bool { didSet { defaults.set(showLunar, forKey: Key.showLunar) } }
    var showChineseHolidays: Bool { didSet { defaults.set(showChineseHolidays, forKey: Key.showChineseHolidays) } }
    var weekStartsOnMonday: Bool { didSet { defaults.set(weekStartsOnMonday, forKey: Key.weekStartsOnMonday) } }

    // MARK: - Login item

    private(set) var loginItemStatus: SMAppService.Status = .notRegistered
    private(set) var loginItemError: String?

    var launchAtLogin: Bool { loginItemStatus == .enabled }
    var launchAtLoginNeedsApproval: Bool { loginItemStatus == .requiresApproval }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.showCalendar: true,
            Key.showMonitoring: true,
            Key.showWeekday: true,
            Key.showLunar: true,
            Key.showChineseHolidays: true,
            Key.weekStartsOnMonday: true
        ])
        showCalendar = defaults.bool(forKey: Key.showCalendar)
        showMonitoring = defaults.bool(forKey: Key.showMonitoring)
        showWeekday = defaults.bool(forKey: Key.showWeekday)
        showLunar = defaults.bool(forKey: Key.showLunar)
        showChineseHolidays = defaults.bool(forKey: Key.showChineseHolidays)
        weekStartsOnMonday = defaults.bool(forKey: Key.weekStartsOnMonday)
        refreshLoginItemStatus()
    }

    // MARK: - Login item management

    func refreshLoginItemStatus() {
        loginItemStatus = SMAppService.mainApp.status
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        loginItemError = nil
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItemStatus()
    }
}
