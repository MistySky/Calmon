import AppKit
import SwiftUI

/// Owns the single global-hot-key calendar panel: an NSPanel whose width is a
/// fixed 880 pt base and whose height follows the current month's real row count,
/// reusing the shared CalendarModel. Handles screen selection, aspect-ratio
/// sizing, live scale, month-driven height and close-on-resign
/// (docs/CALENDAR_PANEL_FINAL_LAYOUT.md).
@MainActor
final class CalendarPanelController: NSObject, NSWindowDelegate {

    nonisolated static var baseWidth: CGFloat { PanelLayout.baseWidth }
    private nonisolated static let safetyInset: CGFloat = 24
    /// Allowance for the system title bar when computing the fit scale.
    private nonisolated static let decorationHeight: CGFloat = 28

    private let model: CalendarModel
    private let preferences: Preferences
    private let clock = PanelClock()

    private var panel: KeyPanel?
    /// True only between the user's own live-resize callbacks, so programmatic
    /// `setContentSize` (show/screen change/capture) never persists a scale.
    private var isUserResizing = false
    /// Called before the panel appears so other surfaces (popovers/settings) close.
    var onWillShow: () -> Void = {}
    /// Always true in normal use; the capture-hold diagnostic disables it so the
    /// panel can stay on screen for long measurements without synthetic input.
    var closesWhenKeyResigns = true

    init(model: CalendarModel, preferences: Preferences) {
        self.model = model
        self.preferences = preferences
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func currentScale(of panel: KeyPanel) -> CGFloat {
        let width = panel.contentView?.bounds.width ?? 0
        guard width > 0 else { return CGFloat(preferences.panelScale) }
        return width / PanelLayout.baseWidth
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    /// Validation aid: panel clock fires so far.
    var clockTickCount: Int { clock.tickCount }

    /// Validation aid: current window geometry in points.
    var frameDescription: String {
        guard let panel else { return "nil" }
        let content = panel.contentView.map { NSStringFromRect($0.bounds) } ?? "nil"
        let safe = panel.contentView.map { "\($0.safeAreaInsets)" } ?? "nil"
        let liveScale = (panel.contentView?.bounds.width ?? 0) / PanelLayout.baseWidth
        return "frame=\(NSStringFromRect(panel.frame)) contentView=\(content) safeArea=\(safe) liveScale=\(liveScale) storedScale=\(preferences.panelScale)"
    }

    // MARK: - Show / close

    func toggle() {
        if isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        onWillShow()
        model.resetToToday()
        let screen = targetScreen()
        let panel = existingOrNewPanel(for: screen)
        applyGeometry(
            scale: resolvedScale(for: screen),
            to: panel,
            screen: screen,
            keepTopCentre: false,
            persist: false
        )
        position(panel, on: screen)
        clock.start()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        guard let panel else { return }
        clock.stop()
        panel.orderOut(nil)
        // Release the SwiftUI tree while hidden; the window, its aspect ratio and
        // the stored scale stay, and `show()` rebuilds the content in a few ms.
        panel.contentViewController = nil
    }

    // MARK: - Panel

    private func existingOrNewPanel(for screen: NSScreen) -> KeyPanel {
        if let panel {
            ensureContent(for: panel)
            return panel
        }
        let initial = PanelLayout.contentSize(scale: 1)
        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: initial.width, height: initial.height),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace]
        // Native material shell matching the existing popovers, so the SwiftUI
        // content stays transparent (docs/CALENDAR_HOTKEY_PANEL.md §5).
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // The panel is a temporary surface: no minimise, no full screen.
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        panel.contentViewController = makeContentController()
        self.panel = panel
        return panel
    }

    private func makeContentController() -> PanelContentController {
        PanelContentController(rootView: CalendarPanelView(model: model, clock: clock) { [weak self] in self?.close() })
    }

    /// The window outlives its content: after `close()` releases the view tree,
    /// the next `show()` installs a fresh content controller.
    private func ensureContent(for panel: KeyPanel) {
        guard panel.contentViewController == nil else { return }
        panel.contentViewController = makeContentController()
    }

    /// Validation aid: apply an exact content size without persisting it, so the
    /// live content-scaling path can be exercised. The aspect ratio is taken from
    /// the requested size (this diagnostic may use intermediate sizes).
    func applyCaptureContentSize(_ size: CGSize) {
        guard let panel else { return }
        let screen = panel.screen ?? targetScreen()
        panel.contentAspectRatio = NSSize(width: size.width, height: size.height)
        panel.contentMinSize = NSSize(width: 200, height: 200 * size.height / size.width)
        panel.contentMaxSize = NSSize(width: 100_000, height: 100_000 * size.height / size.width)
        panel.setContentSize(NSSize(width: size.width, height: size.height))
        position(panel, on: screen)
    }

    // MARK: - Scale

    /// Fit scale for a screen (the panel's height is constant now).
    nonisolated static func fitScale(visibleSize: CGSize) -> CGFloat {
        let availableWidth = visibleSize.width - safetyInset * 2
        let availableHeight = visibleSize.height - safetyInset * 2 - decorationHeight
        return max(0.1, min(availableWidth / baseWidth, availableHeight / PanelLayout.contentHeight))
    }

    /// Clamp the remembered scale to this screen; on tiny screens adapt to fit.
    nonisolated static func resolvedScale(remembered: Double, visibleSize: CGSize) -> CGFloat {
        let fit = fitScale(visibleSize: visibleSize)
        let desired = max(CGFloat(remembered), 1)
        if fit < 1 { return fit }
        return min(desired, fit)
    }

    func fitScale(for screen: NSScreen) -> CGFloat {
        Self.fitScale(visibleSize: screen.visibleFrame.size)
    }

    func resolvedScale(for screen: NSScreen) -> CGFloat {
        Self.resolvedScale(remembered: preferences.panelScale, visibleSize: screen.visibleFrame.size)
    }

    /// Applies the month's aspect ratio, size limits and content size. The scale
    /// may be trimmed to fit the screen, but that is never persisted.
    private func applyGeometry(
        scale requestedScale: CGFloat,
        to panel: KeyPanel,
        screen: NSScreen,
        keepTopCentre: Bool,
        persist: Bool
    ) {
        let fit = fitScale(for: screen)
        let lower = min(1, fit)
        let upper = max(fit, lower)
        let scale = min(max(requestedScale, lower), upper)

        let baseHeight = PanelLayout.contentHeight
        panel.contentAspectRatio = NSSize(width: PanelLayout.baseWidth, height: baseHeight)
        panel.contentMinSize = NSSize(width: PanelLayout.baseWidth * lower, height: baseHeight * lower)
        panel.contentMaxSize = NSSize(width: PanelLayout.baseWidth * upper, height: baseHeight * upper)

        let oldFrame = panel.frame
        panel.setContentSize(NSSize(width: PanelLayout.baseWidth * scale, height: baseHeight * scale))
        if keepTopCentre {
            let size = panel.frame.size
            let origin = NSPoint(
                x: oldFrame.midX - size.width / 2,
                y: oldFrame.maxY - size.height
            )
            panel.setFrameOrigin(origin)
            #if DEBUG
            FileHandle.standardError.write(Data("EVENT panel resize old=\(NSStringFromRect(oldFrame)) new=\(NSStringFromRect(panel.frame))\n".utf8))
            #endif
        }
        clampIntoVisibleArea(panel, screen: screen)
        if persist {
            preferences.panelScale = Double(scale)
        }
    }

    /// Translates the window back inside the usable area (never resizes it).
    private func clampIntoVisibleArea(_ panel: KeyPanel, screen: NSScreen) {
        let visible = screen.visibleFrame
        var frame = panel.frame
        if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
        if frame.minX < visible.minX { frame.origin.x = visible.minX }
        if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
        if frame.minY < visible.minY { frame.origin.y = visible.minY }
        if frame.origin != panel.frame.origin {
            panel.setFrameOrigin(frame.origin)
        }
    }

    private func position(_ panel: KeyPanel, on screen: NSScreen) {
        let visible = screen.visibleFrame
        let frame = panel.frame
        let x = visible.midX - frame.width / 2
        let y = visible.midY - frame.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return screen
        }
        if let keyScreen = NSApp.keyWindow?.screen {
            return keyScreen
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen.screens[0]
    }

    // MARK: - Window delegate

    /// Persist the scale only when the user finished a drag/resize, never on
    /// programmatic adaptation.
    func windowWillStartLiveResize(_ notification: Notification) {
        isUserResizing = true
    }

    /// Live scaling is driven by the SwiftUI container size; the delegate only
    /// records the final user-completed scale.
    func windowDidEndLiveResize(_ notification: Notification) {
        guard isUserResizing else { return }
        isUserResizing = false
        guard let panel, panel.isVisible else { return }
        let scale = (panel.contentView?.bounds.width ?? 0) / Self.baseWidth
        guard scale.isFinite, scale > 0 else { return }
        preferences.panelScale = Double(scale)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking another app, the desktop, the settings window or the menu bar
        // dismisses the panel.
        guard closesWhenKeyResigns else { return }
        if panel?.isVisible == true {
            close()
        }
    }

    func windowDidChangeScreen(_ notification: Notification) {
        guard let panel, panel.isVisible, let screen = panel.screen else { return }
        applyGeometry(
            scale: currentScale(of: panel),
            to: panel,
            screen: screen,
            keepTopCentre: false,
            persist: false
        )
        position(panel, on: screen)
    }

    @objc private func screenParametersChanged() {
        guard let panel, panel.isVisible, let screen = panel.screen ?? NSScreen.main else { return }
        applyGeometry(
            scale: currentScale(of: panel),
            to: panel,
            screen: screen,
            keepTopCentre: true,
            persist: false
        )
    }
}

/// Borderless-looking but resizable/key panel; Esc is routed to `onCancel`.
final class KeyPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Native material shell for the panel content: one NSVisualEffectView layer
/// (matching the popovers' material) with a transparent SwiftUI hosting view on
/// top. The hosting root is created once and never rebuilt on resize.
@MainActor
final class PanelContentController: NSViewController {
    private let effect = NSVisualEffectView()
    private let hosting: NSHostingController<CalendarPanelView>

    init(rootView: CalendarPanelView) {
        hosting = NSHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() {
        let container = NSView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.frame = container.bounds
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect)

        hosting.sizingOptions = []
        addChild(hosting)
        hosting.view.frame = container.bounds
        hosting.view.autoresizingMask = [.width, .height]
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(hosting.view)

        view = container
    }
}
