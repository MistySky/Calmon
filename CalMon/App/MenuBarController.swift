import AppKit
import Observation
import SwiftUI

/// Owns the two independent NSStatusItems, their popovers and the shared
/// right-click menu. Routing stays here; business state lives in the modules.
@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate, NSWindowDelegate {

    private let preferences: Preferences
    private let calendarModel: CalendarModel
    private let monitor: SystemMonitor
    private let provider: HolidayProvider
    private let appSearch = AppSearchModel()
    private let globalHotKey = GlobalHotKeyController()

    private lazy var calendarPanel: CalendarPanelController = {
        let controller = CalendarPanelController(model: calendarModel, preferences: preferences)
        controller.onWillShow = { [weak self] in self?.closeAllPopovers() }
        return controller
    }()

    private var monitorItem: NSStatusItem?
    private var calendarItem: NSStatusItem?
    private var managementItem: NSStatusItem?

    private let monitorPopover = NSPopover()
    private let calendarPopover = NSPopover()

    private var settingsWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var isActive = false
    private var isRecordingHotKey = false
    private var capturePanelSize: CGSize?
    private var captureSelectDate: Date?
    private var captureYearJump = 0
    private var lastMonitorKey: String?
    private var lastCalendarText: String?

    init(preferences: Preferences, calendarModel: CalendarModel, monitor: SystemMonitor, provider: HolidayProvider) {
        self.preferences = preferences
        self.calendarModel = calendarModel
        self.monitor = monitor
        self.provider = provider
        super.init()
    }

    // MARK: - Start

    func start() {
        guard !isActive else { return }
        isActive = true

        monitorPopover.behavior = .transient
        monitorPopover.delegate = self
        calendarPopover.behavior = .transient
        calendarPopover.delegate = self

        syncStatusItems()
        syncMonitoringLifecycle()
        syncPanelLifecycle()
        observePreferences()
        observeMonitor()
        observeCalendar()
        observeWake()

        runCaptureHookIfRequested()
    }

    /// Keeps the sampling lifecycle tied to the "监控" setting: turning it off
    /// stops all queries, turning it on starts a fresh 3 s schedule.
    private func syncMonitoringLifecycle() {
        if preferences.showMonitoring {
            monitor.start()
        } else {
            monitor.stop()
        }
    }

    /// Registers or drops the calendar panel hot key with the "日历" setting.
    private func syncPanelLifecycle() {
        if preferences.showCalendar {
            syncPanelHotKey()
        } else {
            calendarPanel.close()
            globalHotKey.unregister()
        }
    }

    private func syncPanelHotKey() {
        guard !isRecordingHotKey else { return }
        guard preferences.showCalendar, let hotKey = preferences.panelHotKey else {
            globalHotKey.unregister()
            return
        }
        let status = globalHotKey.register(hotKey) { [weak self] in self?.toggleCalendarPanel() }
        #if DEBUG
        FileHandle.standardError.write(Data("EVENT panel hotkey register status=\(status)\n".utf8))
        #endif
    }

    /// Tries a new combo; on failure the previous registration is restored and
    /// the stored value is left untouched.
    private func trySetHotKey(_ hotKey: GlobalHotKeyController.HotKey) -> Bool {
        let previous = preferences.panelHotKey
        let status = globalHotKey.register(hotKey) { [weak self] in self?.toggleCalendarPanel() }
        if status == noErr {
            preferences.panelHotKey = hotKey
            return true
        }
        if let previous {
            _ = globalHotKey.register(previous) { [weak self] in self?.toggleCalendarPanel() }
        } else {
            globalHotKey.unregister()
        }
        return false
    }

    private func clearHotKey() {
        globalHotKey.unregister()
        preferences.panelHotKey = nil
    }

    private func toggleCalendarPanel() {
        if calendarPanel.isVisible {
            calendarPanel.close()
            return
        }
        calendarPanel.show()
    }

    /// Validation aid: opens/closes the hot-key panel 50 times, then reports the
    /// footprint delta and the clock tick counts while visible and after close.
    private func runPanelStress() {
        func footprint() -> UInt64 {
            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { pointer in
                    proc_pid_rusage(ProcessInfo.processInfo.processIdentifier, RUSAGE_INFO_V4, pointer)
                }
            }
            return result == 0 ? info.ri_phys_footprint : 0
        }
        var warmup = 5
        var cycles = 50
        var before: UInt64 = 0
        var visibleTicks = 0
        var phase = "warmup"

        func step() {
            switch phase {
            case "warmup":
                if warmup > 0 {
                    warmup -= 1
                    self.calendarPanel.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { step() }
                } else {
                    phase = "settleBefore"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                        before = footprint()
                        phase = "cycles"
                        step()
                    }
                }
            case "cycles":
                if cycles > 0 {
                    cycles -= 1
                    self.calendarPanel.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { step() }
                } else {
                    self.calendarPanel.close()
                    phase = "visibleSample"
                    self.calendarPanel.show()
                    let start = self.calendarPanel.clockTickCount
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                        visibleTicks = self.calendarPanel.clockTickCount - start
                        self.calendarPanel.close()
                        let closedStart = self.calendarPanel.clockTickCount
                        phase = "closedSample"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                            let closedTicks = self.calendarPanel.clockTickCount - closedStart
                            let after = footprint()
                            let message = "STRESS panel before=\(before / 1_048_576)MiB after=\(after / 1_048_576)MiB delta=\((Int64(after) - Int64(before)) / 1_048_576)MiB visibleTicks30s=\(visibleTicks) closedTicks20s=\(closedTicks)\n"
                            FileHandle.standardError.write(Data(message.utf8))
                        }
                    }
                }
            default:
                break
            }
        }
        step()
    }

    /// Validation aid: `CALMON_YEAR_JUMP=+1|-1|+2` runs the same model entry the
    /// year buttons use, so the resulting state can be captured without a click.
    private func applyCaptureYearJumpIfRequested() {
        guard let raw = ProcessInfo.processInfo.environment["CALMON_YEAR_JUMP"] else { return }
        captureYearJump = Int(raw) ?? 0
        applyCaptureYearJump()
    }

    private func applyCaptureYearJump() {
        guard captureYearJump != 0 else { return }
        for _ in 0..<abs(captureYearJump) {
            if captureYearJump > 0 {
                calendarModel.goToNextYear()
            } else {
                calendarModel.goToPreviousYear()
            }
        }
    }

    /// Validation aid: `CALMON_PANEL_SIZE=WxH` applies an exact content size so the
    /// content-scaling path can be compared across sizes (not a real mouse drag).
    private func applyCapturePanelSizeIfRequested() {
        guard let raw = ProcessInfo.processInfo.environment["CALMON_PANEL_SIZE"] else { return }
        let parts = raw.lowercased().split(separator: "x")
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]) else { return }
        let size = CGSize(width: width, height: height)
        capturePanelSize = size
        calendarPanel.applyCaptureContentSize(size)
    }

    /// Validation aid: selects `CALMON_SELECT_DATE` (yyyy-MM-dd) before a capture.
    @discardableResult
    private func selectCaptureDateIfRequested() -> Bool {
        guard let raw = ProcessInfo.processInfo.environment["CALMON_SELECT_DATE"] else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: raw) else { return false }
        captureSelectDate = date
        applyCaptureDate()
        return true
    }

    private func applyCaptureDate() {
        guard let date = captureSelectDate else { return }
        calendarModel.showMonth(date)
        calendarModel.select(date)
    }

    /// Validation aid: keeps the capture panel visible for long measurements on a
    /// machine where synthetic input is blocked. Never enabled in normal use.
    private func holdPanelIfRequested() {
        guard ProcessInfo.processInfo.environment["CALMON_PANEL_HOLD"] == "1" else { return }
        calendarPanel.closesWhenKeyResigns = false
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                #if DEBUG
                FileHandle.standardError.write(Data("EVENT panel hold visible=\(self.calendarPanel.isVisible) active=\(NSApp.isActive)\n".utf8))
                #endif
                if !self.calendarPanel.isVisible {
                    self.calendarPanel.show()
                    if let size = self.capturePanelSize {
                        self.calendarPanel.applyCaptureContentSize(size)
                    }
                    self.applyCaptureDate()
                    self.applyCaptureYearJump()
                }
            }
        }
    }

    private func logPanelFrame() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            FileHandle.standardError.write(Data("CALMON_PANEL \(self.calendarPanel.frameDescription)\n".utf8))
        }
    }

    /// Validation aid only: when the `CALMON_CAPTURE` environment variable is
    /// set (never set in normal use) the requested surface opens once so the
    /// real UI can be captured on a machine where synthetic clicks are blocked.
    private func runCaptureHookIfRequested() {
        #if DEBUG
        // Debug-only diagnostic: trigger the authorization prompt so the event
        // dump can run on a fresh ad-hoc build.
        if ProcessInfo.processInfo.environment["CALMON_DUMP_CALENDAR"] == "1" {
            provider.requestAccess()
        }
        #endif
        guard let target = ProcessInfo.processInfo.environment["CALMON_CAPTURE"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            let monitorFrame = self.monitorItem?.button?.window?.frame
            let calendarFrame = self.calendarItem?.button?.window?.frame
            let message = "CALMON_CAPTURE appearance=\(NSApp.effectiveAppearance.name.rawValue) monitorFrame=\(String(describing: monitorFrame)) calendarFrame=\(String(describing: calendarFrame))\n"
            FileHandle.standardError.write(Data(message.utf8))
            switch target {
            case "monitoring":
                self.toggleMonitorPopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if let q = ProcessInfo.processInfo.environment["CALMON_SEARCH"] {
                        self.appSearch.isExpanded = true
                        self.appSearch.query = q
                    }
                }
            case "calendar":
                self.toggleCalendarPopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.selectCaptureDateIfRequested()
                    self.applyCaptureYearJumpIfRequested()
                }
            case "calendar-festival":
                self.toggleCalendarPopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if !self.selectCaptureDateIfRequested() {
                        let days = self.calendarModel.weeks.flatMap { $0.days }.filter { $0.isCurrentMonth }
                        if let day = days.first(where: { $0.badge == .holiday }) ?? days.first(where: { $0.festivalShort != nil }) ?? days.first(where: { $0.solarTerm != nil }) {
                            self.calendarModel.select(day.date)
                        }
                    }
                    self.applyCaptureYearJumpIfRequested()
                }
            case "settings":
                self.openSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    guard let self else { return }
                    let p = self.preferences
                    let line = "CALMON_SETTINGS calendar=\(p.showCalendar) monitoring=\(p.showMonitoring) weekday=\(p.showWeekday) lunar=\(p.showLunar) holidays=\(p.showChineseHolidays) hotKey=\(p.panelHotKey.map(GlobalHotKeyController.displayString) ?? "nil") access=\(self.provider.accessState) source=\(self.provider.sourceStatus)\n"
                    FileHandle.standardError.write(Data(line.utf8))
                }
            case "panel":
                self.toggleCalendarPanel()
                self.selectCaptureDateIfRequested()
                self.applyCaptureYearJumpIfRequested()
                self.applyCapturePanelSizeIfRequested()
                self.logPanelFrame()
                self.holdPanelIfRequested()
            case "panel-scaled":
                self.preferences.panelScale = 1.25
                self.toggleCalendarPanel()
                self.logPanelFrame()
            case "menu-monitoring": self.showContextMenu(for: self.monitorItem)
            case "menu-calendar": self.showContextMenu(for: self.calendarItem)
            #if DEBUG
            case "toggle-stress": self.runToggleStress()
            case "panel-stress": self.runPanelStress()
            case "monitoring-toggle": self.runMonitoringToggleCheck()
            case "outside-close-check": self.runOutsideCloseCheck()
            #endif
            default: break
            }
            #if DEBUG
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let monitorKey = self.monitorPopover.contentViewController?.view.window?.isKeyWindow ?? false
                let calendarKey = self.calendarPopover.contentViewController?.view.window?.isKeyWindow ?? false
                let state = "CALMON_STATE active=\(NSApp.isActive) appKeyWindow=\(NSApp.keyWindow != nil) monitorKey=\(monitorKey) calendarKey=\(calendarKey)\n"
                FileHandle.standardError.write(Data(state.utf8))
            }
            #endif
        }
    }

#if DEBUG
    /// Validation aid: flips the "监控" setting off and on and reports whether the
    /// sampling lifecycle followed, then exits.
    private func runMonitoringToggleCheck() {
        func log(_ text: String) {
            FileHandle.standardError.write(Data("MONTOGGLE \(text)\n".utf8))
        }
        log("start isRunning=\(monitor.isRunning)")
        preferences.showMonitoring = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            log("after-off isRunning=\(self.monitor.isRunning)")
            self.preferences.showMonitoring = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self else { return }
                log("after-on isRunning=\(self.monitor.isRunning)")
                NSApp.terminate(nil)
            }
        }
    }

    /// Validation aid: opens each popover, simulates losing app activation (as
    /// when the user clicks another app or the desktop) and reports whether the
    /// transient popover closed, then exits.
    private func runOutsideCloseCheck() {
        func log(_ text: String) {
            FileHandle.standardError.write(Data("OUTSIDE \(text)\n".utf8))
        }
        func check(_ label: String, popover: NSPopover, open: @escaping () -> Void, next: @escaping () -> Void) {
            open()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                log("\(label) shownBeforeDeactivate=\(popover.isShown)")
                NSApp.deactivate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    log("\(label) shownAfterDeactivate=\(popover.isShown)")
                    next()
                }
            }
        }
        check("monitor", popover: monitorPopover, open: { self.toggleMonitorPopover() }) {
            // After the panel closed, wait past a 3 s period and report that the
            // per-application list stays empty (sampling stopped).
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                log("monitorAfterClose applications=\(self.monitor.applications.count) isRunning=\(self.monitor.isRunning)")
                check("calendar", popover: self.calendarPopover, open: { self.toggleCalendarPopover() }) {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// Validation aid: opens/closes both popovers and the settings window 50
    /// times and reports the physical footprint delta across one measured round.
    ///
    /// The first round is treated as warm-up (AppKit/SwiftUI caches keep growing
    /// for a couple of minutes after launch), so the reported delta is the second
    /// round measured from an already-warm footprint. This keeps the acceptance
    /// number about toggle-induced growth, not cold-start warm-up.
    private func runToggleStress() {
        func footprint() -> UInt64 {
            var info = rusage_info_v4()
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { pointer in
                    proc_pid_rusage(ProcessInfo.processInfo.processIdentifier, RUSAGE_INFO_V4, pointer)
                }
            }
            return result == 0 ? info.ri_phys_footprint : 0
        }
        var warmup = 5
        var calibrateCycles = 50
        var measureCycles = 50
        var before: UInt64 = 0
        var phase = "warmup"

        func toggleOnce() {
            if self.monitorPopover.isShown { self.monitorPopover.performClose(nil) } else { self.toggleMonitorPopover() }
            if self.calendarPopover.isShown { self.calendarPopover.performClose(nil) } else { self.toggleCalendarPopover() }
            if let window = self.settingsWindow, window.isVisible { window.close() } else { self.openSettings() }
        }

        func step() {
            switch phase {
            case "warmup":
                if warmup > 0 {
                    warmup -= 1
                    toggleOnce()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { step() }
                } else {
                    phase = "calibrateRest"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 120) { phase = "calibrate"; step() }
                }
            case "calibrate":
                if calibrateCycles > 0 {
                    calibrateCycles -= 1
                    toggleOnce()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { step() }
                } else {
                    phase = "calibrateSettle"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                        before = footprint()
                        phase = "measure"
                        step()
                    }
                }
            case "measure":
                if measureCycles > 0 {
                    measureCycles -= 1
                    toggleOnce()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { step() }
                } else {
                    phase = "measureSettle"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                        let after = footprint()
                        let message = "STRESS warmedBefore=\(before / 1_048_576)MiB afterSettle=\(after / 1_048_576)MiB delta=\((Int64(after) - Int64(before)) / 1_048_576)MiB (round2 of 50 toggles)\n"
                        FileHandle.standardError.write(Data(message.utf8))
                    }
                }
            default:
                break
            }
        }
        step()
    }
#endif

    // MARK: - Status items

    private func makeItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        return item
    }

    private func syncStatusItems() {
        // NSStatusBar inserts newer items to the left, so the calendar item is
        // created first to leave monitoring on the left and the date on the
        // right, matching the spec default. The user can still Cmd-drag them.
        if preferences.showCalendar {
            if calendarItem == nil {
                calendarItem = makeItem()
                calendarItem?.autosaveName = "CalMon.Date"
            }
            calendarItem?.isVisible = true
            updateCalendarImage()
        } else {
            calendarItem?.isVisible = false
            calendarPopover.performClose(nil)
        }

        if preferences.showMonitoring {
            if monitorItem == nil {
                monitorItem = makeItem()
                monitorItem?.autosaveName = "CalMon.Monitor"
            }
            monitorItem?.isVisible = true
            updateMonitorImage()
        } else {
            monitorItem?.isVisible = false
            monitorPopover.performClose(nil)
        }

        if !preferences.showCalendar && !preferences.showMonitoring {
            if managementItem == nil {
                managementItem = makeItem()
                managementItem?.button?.image = managementImage()
                managementItem?.button?.imagePosition = .imageOnly
                managementItem?.button?.toolTip = "CalMon"
                managementItem?.button?.setAccessibilityLabel("CalMon 菜单")
            }
            managementItem?.isVisible = true
        } else {
            managementItem?.isVisible = false
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let isRight = NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true
        if sender == managementItem?.button {
            if isRight { showContextMenu(for: managementItem) } else { openSettings() }
            return
        }
        if isRight {
            showContextMenu(for: sender == calendarItem?.button ? calendarItem : monitorItem)
            return
        }
        if sender == calendarItem?.button {
            toggleCalendarPopover()
        } else {
            toggleMonitorPopover()
        }
    }

    private func showContextMenu(for item: NSStatusItem?) {
        guard let item else { return }
        let menu = NSMenu()
        // Version info only lives here, nowhere else in the UI.
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "CalMon \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "偏好设置", action: #selector(openSettingsAction), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quitAction), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func openSettingsAction() { openSettings() }
    @objc private func quitAction() { NSApp.terminate(nil) }

    // MARK: - Popovers

    private func toggleMonitorPopover() {
        if monitorPopover.isShown {
            monitorPopover.performClose(nil)
            return
        }
        calendarPanel.close()
        calendarPopover.performClose(nil)
        appSearch.beginPresentation()
        monitor.setPanelVisible(true)
        #if DEBUG
        FileHandle.standardError.write(Data("EVENT monitor popoverWillShow\n".utf8))
        #endif
        present(monitorPopover, content: monitorHosting, relativeTo: monitorItem)
    }

    private func toggleCalendarPopover() {
        if calendarPopover.isShown {
            calendarPopover.performClose(nil)
            return
        }
        calendarPanel.close()
        monitorPopover.performClose(nil)
        calendarModel.resetToToday()
        present(calendarPopover, content: calendarHosting, relativeTo: calendarItem)
    }

    /// Shows a popover on the clicked status item's display.
    ///
    /// Order matters: `show` first (anchored to the clicked item's status-bar
    /// window, which is the "true" item on the clicked display), then make it key,
    /// and only then activate the app. Activating before `show` can promote a
    /// window on another display and drag the popover there on multi-display
    /// setups. Making the popover key and activating keeps it in the active
    /// (not dimmed) material so no second click is needed.
    private func present(_ popover: NSPopover, content: NSViewController, relativeTo item: NSStatusItem?) {
        popover.contentViewController = content
        let button = item?.button ?? NSView()
        popover.show(relativeTo: item?.button?.bounds ?? .zero, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hosting controllers are created once and reused so repeated opening does
    /// not reallocate the SwiftUI hierarchy each time.
    private lazy var monitorHosting: NSHostingController<MonitoringView> = {
        let height = NSScreen.main?.visibleFrame.height ?? 800
        let controller = NSHostingController(rootView: MonitoringView(monitor: monitor, maxHeight: height * 0.8, search: appSearch, onClose: { [weak self] in
            self?.monitorPopover.performClose(nil)
        }))
        controller.sizingOptions = [.preferredContentSize]
        return controller
    }()

    private lazy var calendarHosting: NSHostingController<CalendarView> = {
        let height = NSScreen.main?.visibleFrame.height ?? 800
        let controller = NSHostingController(rootView: CalendarView(model: calendarModel, maxHeight: height * 0.8, onClose: { [weak self] in
            self?.calendarPopover.performClose(nil)
        }))
        controller.sizingOptions = [.preferredContentSize]
        return controller
    }()

    func popoverDidClose(_ notification: Notification) {
        if notification.object as? NSPopover === monitorPopover {
            #if DEBUG
            FileHandle.standardError.write(Data("EVENT monitor popoverDidClose\n".utf8))
            #endif
            appSearch.beginPresentation()
            monitor.setPanelVisible(false)
        }
    }

    private func closeAllPopovers() {
        monitorPopover.performClose(nil)
        calendarPopover.performClose(nil)
    }

    // MARK: - Settings window

    func openSettings() {
        closeAllPopovers()
        calendarPanel.close()
        preferences.refreshLoginItemStatus()
        provider.refreshAccessState()
        provider.autoDiscoverSource()
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = NSHostingController(rootView: SettingsView(
            preferences: preferences,
            provider: provider,
            onSetHotKey: { [weak self] hotKey in self?.trySetHotKey(hotKey) ?? false },
            onClearHotKey: { [weak self] in self?.clearHotKey() },
            onRecordingChanged: { [weak self] recording in
                self?.isRecordingHotKey = recording
                if recording {
                    self?.globalHotKey.unregister()
                } else {
                    self?.syncPanelHotKey()
                }
            }
        ))
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = "CalMon 设置"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        // Size to the form's content so no scroll bar is needed, capped to the screen.
        let fitting = controller.view.fittingSize
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 900) - 120
        let height = min(max(fitting.height, 560), maxHeight)
        window.setContentSize(NSSize(width: UIStyle.Metrics.settingsWidth, height: height))
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(
                x: visible.midX - window.frame.width / 2,
                y: visible.midY - window.frame.height / 2
            ))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === settingsWindow else { return }
        provider.reloadEvents()
    }

    // MARK: - Rendering

    private func updateMonitorImage() {
        let cpu = UIStyle.percentString(monitor.snapshot.cpu.usage)
        let mem = UIStyle.percentString(monitor.snapshot.memory?.usedPercent)
        let key = "\(cpu)|\(mem)"
        guard key != lastMonitorKey else { return }
        lastMonitorKey = key
        monitorItem?.button?.image = Self.metricImage(cpu: cpu, mem: mem)
        monitorItem?.button?.toolTip = "CPU \(cpu) · 内存 \(mem)"
        monitorItem?.button?.setAccessibilityLabel("CPU \(cpu)，内存 \(mem)")
    }

    private func updateCalendarImage() {
        let text = calendarModel.menuBarText
        guard text != lastCalendarText else { return }
        lastCalendarText = text
        calendarItem?.button?.image = Self.dateImage(text)
        calendarItem?.button?.toolTip = text
        calendarItem?.button?.setAccessibilityLabel("日期 \(text)")
    }

    private func managementImage() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let symbol = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "CalMon")?
            .withSymbolConfiguration(config)
        symbol?.isTemplate = true
        return symbol ?? NSImage(size: NSSize(width: 16, height: 16))
    }

    /// Two-line CPU/MEM label. Fixed column widths mean 0/9/99/100/-- never
    /// changes the status item width.
    static func metricImage(cpu: String, mem: String) -> NSImage {
        let font = UIStyle.Fonts.menuBarMetric
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        let labelWidth = max(("CPU" as NSString).size(withAttributes: attributes).width,
                             ("MEM" as NSString).size(withAttributes: attributes).width)
        let valueWidth = max(("100%" as NSString).size(withAttributes: attributes).width,
                             ("--%" as NSString).size(withAttributes: attributes).width)
        let lineHeight = ceil(("CPU" as NSString).size(withAttributes: attributes).height)
        let gap: CGFloat = 3
        let padding: CGFloat = 0
        let height = lineHeight * 2
        let width = ceil(padding + labelWidth + gap + valueWidth + padding)

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.black.set()
        let labelStyle = NSMutableParagraphStyle()
        labelStyle.alignment = .left
        let valueStyle = NSMutableParagraphStyle()
        valueStyle.alignment = .right

        let labelX = padding
        let valueX = padding + labelWidth + gap
        // Draw each line filling its own slot so both lines are vertically centred
        // in the status bar canvas (no clipping, no top-heavy offset).
        func draw(_ label: String, _ value: String, slot: Int) {
            let y = height - CGFloat(slot + 1) * lineHeight
            (label as NSString).draw(in: NSRect(x: labelX, y: y, width: labelWidth, height: lineHeight), withAttributes: [.font: font, .paragraphStyle: labelStyle, .foregroundColor: NSColor.black])
            (value as NSString).draw(in: NSRect(x: valueX, y: y, width: valueWidth, height: lineHeight), withAttributes: [.font: font, .paragraphStyle: valueStyle, .foregroundColor: NSColor.black])
        }
        draw("CPU", cpu, slot: 0)
        draw("MEM", mem, slot: 1)
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    static func dateImage(_ text: String) -> NSImage {
        let font = UIStyle.Fonts.menuBarDate
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let padding: CGFloat = 0
        let textHeight = ceil((text as NSString).size(withAttributes: attributes).height)
        let height = textHeight + 2
        let textWidth = ceil((text as NSString).size(withAttributes: attributes).width)
        let width = padding + textWidth + padding
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let y = (height - textHeight) / 2
        (text as NSString).draw(in: NSRect(x: padding, y: y, width: textWidth, height: textHeight), withAttributes: [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.black])
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - Observation

    private func observePreferences() {
        observe { [weak self] in
            _ = self?.preferences.showCalendar
            _ = self?.preferences.showMonitoring
            _ = self?.preferences.panelHotKey
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.syncStatusItems()
                self?.syncMonitoringLifecycle()
                self?.syncPanelLifecycle()
                self?.observePreferences()
            }
        }
    }

    private func observeMonitor() {
        observe { [weak self] in
            _ = self?.monitor.snapshot.timestamp
            _ = self?.monitor.snapshot.cpu.usage
            _ = self?.monitor.snapshot.memory?.usedPercent
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateMonitorImage()
                self?.observeMonitor()
            }
        }
    }

    private func observeCalendar() {
        observe { [weak self] in
            _ = self?.calendarModel.menuBarText
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateCalendarImage()
                self?.observeCalendar()
            }
        }
    }

    private func observe(_ read: @escaping () -> Void, onChange: @escaping @Sendable () -> Void) {
        withObservationTracking(read, onChange: onChange)
    }

    private func observeWake() {
        let wake = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.monitor.handleWake()
                self?.updateCalendarImage()
            }
        }
        observers.append(wake)
        // The panel is a temporary surface: it never survives sleep.
        let sleep = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.calendarPanel.close()
            }
        }
        observers.append(sleep)
    }

}
