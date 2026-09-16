import AppKit

/// Accessory app: no Dock icon, no main window. AppKit owns the lifecycle and
/// the status bar; SwiftUI renders the popover and settings content.
@main
@MainActor
final class CalMonApp: NSObject, NSApplicationDelegate {

    private var menuBarController: MenuBarController?
    private var preferences: Preferences!
    private var provider: HolidayProvider!
    private var calendarModel: CalendarModel!
    private let monitor = SystemMonitor()

    static func main() {
        let application = NSApplication.shared
        let delegate = CalMonApp()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // Hosted tests need Bundle.main resources, but must not start the
        // user's menu bar session or load their persisted calendar selection.
        if ProcessInfo.processInfo.environment["CALMON_TEST_HOST"] == "1" { return }
        #endif
        let preferences = Preferences.shared
        let provider = HolidayProvider()
        provider.refreshAccessState()
        provider.autoDiscoverSource()
        let calendarModel = CalendarModel(provider: provider, preferences: preferences)
        self.preferences = preferences
        self.provider = provider
        self.calendarModel = calendarModel

        buildMainMenu()

        let controller = MenuBarController(
            preferences: preferences,
            calendarModel: calendarModel,
            monitor: monitor,
            provider: provider
        )
        menuBarController = controller
        controller.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuBarController?.openSettings()
        return true
    }

    @objc private func openSettingsFromMenu() {
        menuBarController?.openSettings()
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 CalMon", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "偏好设置", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 CalMon", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 CalMon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }
}
