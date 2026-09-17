import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var preferences: Preferences
    let provider: HolidayProvider
    var onSetHotKey: (GlobalHotKeyController.HotKey) -> Bool = { _ in false }
    var onClearHotKey: () -> Void = {}
    var onRecordingChanged: (Bool) -> Void = { _ in }

    @State private var hotKeyError: String?
    /// Validation aid: capture-only tokens so the recorder's four states can be
    /// photographed without synthetic input. Never set in normal use.
    @State private var captureRecordToken = 0

    var body: some View {
        Form {
            Section {
                settingToggle(
                    title: "登录时启动",
                    detail: "使用系统登录项，状态以系统设置为准",
                    isOn: Binding(
                        get: { preferences.launchAtLogin },
                        set: { preferences.setLaunchAtLogin($0) }
                    )
                )
                if preferences.launchAtLoginNeedsApproval {
                    HStack(spacing: 8) {
                        Text("需在“系统设置 › 通用 › 登录项”中批准")
                            .font(UIStyle.Fonts.caption)
                            .foregroundStyle(.secondary)
                        Button("打开系统设置") { openLoginItemsSettings() }
                            .controlSize(.small)
                    }
                }
                if let error = preferences.loginItemError {
                    Text(error)
                        .font(UIStyle.Fonts.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("通用").font(UIStyle.Fonts.groupTitle)
            }

            Section {
                settingToggle(
                    title: "日历",
                    detail: "菜单栏日期项目与月历",
                    isOn: $preferences.showCalendar
                )
                settingToggle(
                    title: "监控",
                    detail: "菜单栏 CPU/MEM 项目与采样",
                    isOn: $preferences.showMonitoring
                )
            } header: {
                Text("菜单栏").font(UIStyle.Fonts.groupTitle)
            }

            Section {
                settingToggle(
                    title: "显示星期",
                    detail: "菜单栏日期中的星期",
                    isOn: $preferences.showWeekday
                )
                settingToggle(
                    title: "显示农历",
                    detail: "关闭后日期格与详情不显示农历，节日与班/休不受影响",
                    isOn: $preferences.showLunar
                )
                settingToggle(
                    title: "中国节假日",
                    detail: "中国节日名称与班/休标记",
                    isOn: $preferences.showChineseHolidays
                )

                HStack {
                    Text("周起始日")
                    Spacer(minLength: 8)
                    WeekStartRadio(startsOnMonday: $preferences.weekStartsOnMonday)
                        .fixedSize()
                }

                permissionRow

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("日历快捷键")
                        Spacer(minLength: 8)
                        HotKeyRecorderView(
                            displayText: recorderDisplayText,
                            isPlaceholder: preferences.panelHotKey == nil,
                            isClearVisible: preferences.panelHotKey != nil,
                            isEnabled: preferences.showCalendar,
                            currentHotKey: preferences.panelHotKey,
                            startRecordingToken: captureRecordToken,
                            errorText: $hotKeyError,
                            onSet: onSetHotKey,
                            onClear: onClearHotKey,
                            onRecordingChanged: onRecordingChanged
                        )
                        .fixedSize()
                    }
                    // Error copy gets its own row below the control so the input
                    // box keeps its right edge (CALENDAR_PANEL_UI_FOLLOWUP.md §3.2).
                    if let hotKeyError {
                        Text(hotKeyError)
                            .font(UIStyle.Fonts.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            } header: {
                Text("日历").font(UIStyle.Fonts.groupTitle)
            }
            .disabled(!preferences.showCalendar)
        }
        .formStyle(.grouped)
        .scrollIndicators(.hidden)
        .frame(width: UIStyle.Metrics.settingsWidth)
        .task {
            provider.refreshAccessState()
            provider.autoDiscoverSource()
            applyCaptureStateIfRequested()
        }
    }

    /// Validation aid only (env-gated): seeds the recorder's recording/error states
    /// so the four control states can be captured without synthetic input.
    private func applyCaptureStateIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        if let text = environment["CALMON_SETTINGS_ERROR"], !text.isEmpty {
            hotKeyError = text
        }
        if environment["CALMON_SETTINGS_RECORD"] == "1" {
            captureRecordToken += 1
        }
    }

    // MARK: - Hot key display

    /// Read in `body` so the recorder redraws when the stored combo changes.
    private var recorderDisplayText: String {
        guard let hotKey = preferences.panelHotKey else { return "设置快捷键" }
        return GlobalHotKeyController.displayString(hotKey)
    }

    // MARK: - Permission row

    @ViewBuilder
    private var permissionRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("系统日历权限")
            Spacer(minLength: 8)
            permissionContent
        }
    }

    @ViewBuilder
    private var permissionContent: some View {
        switch provider.accessState {
        case .notDetermined:
            Button("获取权限") { provider.requestAccess() }
                .controlSize(.small)
        case .requesting:
            Text("正在请求…")
                .font(UIStyle.Fonts.caption)
                .foregroundStyle(.secondary)
        case .authorized:
            VStack(alignment: .trailing, spacing: 2) {
                Text("已授权")
                    .font(UIStyle.Fonts.caption)
                    .foregroundStyle(.secondary)
                if !provider.hasHolidayCalendar {
                    Text("未找到系统节日日历，显示普通日历")
                        .font(UIStyle.Fonts.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        case .denied:
            HStack(spacing: 8) {
                Text("未授权")
                    .font(UIStyle.Fonts.caption)
                    .foregroundStyle(.secondary)
                Button("打开系统设置") { openCalendarPrivacySettings() }
                    .controlSize(.small)
            }
        case .restricted:
            Text("访问受限")
                .font(UIStyle.Fonts.caption)
                .foregroundStyle(.secondary)
        }
        if let error = provider.accessError {
            Text(error)
                .font(UIStyle.Fonts.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func settingToggle(title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(UIStyle.Fonts.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
    }

    private func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openCalendarPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Native horizontal radio group for the week-start choice (周一 / 周日).
struct WeekStartRadio: NSViewRepresentable {
    @Binding var startsOnMonday: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 16
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        let monday = NSButton(radioButtonWithTitle: "周一", target: context.coordinator, action: #selector(Coordinator.selectMonday))
        let sunday = NSButton(radioButtonWithTitle: "周日", target: context.coordinator, action: #selector(Coordinator.selectSunday))
        monday.state = startsOnMonday ? .on : .off
        sunday.state = startsOnMonday ? .off : .on
        stack.addArrangedSubview(monday)
        stack.addArrangedSubview(sunday)
        context.coordinator.monday = monday
        context.coordinator.sunday = sunday
        return stack
    }

    func updateNSView(_ nsView: NSStackView, context: Context) {
        context.coordinator.monday?.state = startsOnMonday ? .on : .off
        context.coordinator.sunday?.state = startsOnMonday ? .off : .on
    }

    final class Coordinator: NSObject {
        var parent: WeekStartRadio
        weak var monday: NSButton?
        weak var sunday: NSButton?

        init(_ parent: WeekStartRadio) { self.parent = parent }

        @objc func selectMonday() { parent.startsOnMonday = true }
        @objc func selectSunday() { parent.startsOnMonday = false }
    }
}

/// Single right-aligned native hot-key recorder: one bezelled text field with a
/// borderless clear button inside it (CALENDAR_PANEL_UI_FOLLOWUP.md §3).
struct HotKeyRecorderView: NSViewRepresentable {
    var displayText: String
    var isPlaceholder: Bool
    var isClearVisible: Bool
    var isEnabled: Bool
    var currentHotKey: GlobalHotKeyController.HotKey?
    var startRecordingToken = 0
    @Binding var errorText: String?
    var onSet: (GlobalHotKeyController.HotKey) -> Bool
    var onClear: () -> Void
    var onRecordingChanged: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> RecorderControl {
        let control = RecorderControl()
        control.onActivate = { [weak coordinator = context.coordinator] in coordinator?.beginRecording() }
        control.onClear = { [weak coordinator = context.coordinator] in coordinator?.clear() }
        context.coordinator.control = control
        context.coordinator.refresh()
        return control
    }

    func updateNSView(_ nsView: RecorderControl, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refresh()
        if startRecordingToken != context.coordinator.lastStartToken {
            context.coordinator.lastStartToken = startRecordingToken
            if startRecordingToken > 0 {
                context.coordinator.beginRecording()
            }
        }
    }

    static func dismantleNSView(_ nsView: RecorderControl, coordinator: Coordinator) {
        coordinator.stopRecording()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: HotKeyRecorderView
        private var monitor: Any?
        private(set) var isRecording = false
        var lastStartToken = 0
        weak var control: RecorderControl?

        init(parent: HotKeyRecorderView) { self.parent = parent }

        func refresh() {
            guard let control else { return }
            control.configure(
                text: isRecording ? "请按键…" : parent.displayText,
                isPlaceholder: !isRecording && parent.isPlaceholder,
                // The clear button stays available while recording so it can
                // cancel the recording and drop the stored combo (§3.2).
                clearVisible: parent.isClearVisible,
                isEnabled: parent.isEnabled
            )
        }

        func beginRecording() {
            guard !isRecording, parent.isEnabled else { return }
            parent.errorText = nil
            isRecording = true
            // The existing global hot key is dropped while recording so pressing
            // the old combo is captured as input instead of toggling the panel.
            parent.onRecordingChanged(true)
            refresh()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                self?.handle(event)
                return nil
            }
        }

        func stopRecording() {
            guard isRecording || monitor != nil else { return }
            isRecording = false
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            parent.onRecordingChanged(false)
            refresh()
        }

        func clear() {
            stopRecording()
            parent.errorText = nil
            parent.onClear()
        }

        private func handle(_ event: NSEvent) {
            if event.keyCode == 53 { // Esc cancels, keeping the previous combo
                stopRecording()
                return
            }
            if let error = GlobalHotKeyController.validate(
                modifiers: event.modifierFlags,
                keyCode: event.keyCode,
                characters: event.charactersIgnoringModifiers
            ) {
                switch error {
                case .missingModifier:
                    parent.errorText = "快捷键需包含 ⌘ 或 ⌃"
                case .missingKey:
                    parent.errorText = "请再加一个字母或数字"
                case .reserved:
                    parent.errorText = "此组合由系统或常用操作使用，请换一个"
                }
                return
            }
            let hotKey = GlobalHotKeyController.HotKey(
                keyCode: UInt32(event.keyCode),
                carbonModifiers: GlobalHotKeyController.carbonModifiers(from: event.modifierFlags)
            )
            // Re-recording the same combo is a no-op success.
            if hotKey == parent.currentHotKey {
                stopRecording()
                return
            }
            if parent.onSet(hotKey) {
                parent.errorText = nil
                stopRecording()
            } else {
                parent.errorText = "快捷键无法注册或已被占用，请换一个"
            }
        }
    }
}

/// Native composite: a bezelled read-only text field with a borderless clear
/// button inside its trailing edge. No custom bezel drawing.
final class RecorderControl: NSView {
    static let targetWidth: CGFloat = 104
    static let targetHeight: CGFloat = 24
    /// Inline clear geometry (UI_COMPACT_ALIGNMENT.md §3): 20 pt hit, 4 pt right
    /// inset, 12 pt symbol.
    private static let clearHit: CGFloat = 20
    private static let clearInset: CGFloat = 4

    var onActivate: (() -> Void)?
    var onClear: (() -> Void)?

    private let field = RecorderTextField()
    private let clearButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.targetWidth, height: Self.targetHeight))
        field.frame = bounds
        field.autoresizingMask = [.width, .height]
        field.isEditable = false
        field.isSelectable = false
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.controlSize = .small
        field.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        field.usesSingleLineMode = true
        field.setAccessibilityLabel("日历快捷键")
        field.onActivate = { [weak self] in self?.onActivate?() }
        addSubview(field)

        clearButton.isBordered = false
        clearButton.bezelStyle = .inline
        clearButton.imagePosition = .imageOnly
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clearTapped)
        clearButton.setAccessibilityLabel("清除日历快捷键")
        clearButton.autoresizingMask = [.minXMargin]
        addSubview(clearButton)
        layoutClearButton()
    }

    private func layoutClearButton() {
        clearButton.frame = NSRect(
            x: Self.targetWidth - Self.clearInset - Self.clearHit,
            y: (Self.targetHeight - Self.clearHit) / 2,
            width: Self.clearHit,
            height: Self.clearHit
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.targetWidth, height: Self.targetHeight) }

    @objc private func clearTapped() { onClear?() }

    func configure(text: String, isPlaceholder: Bool, clearVisible: Bool, isEnabled: Bool) {
        field.stringValue = text
        field.textColor = isPlaceholder ? .secondaryLabelColor : .labelColor
        field.toolTip = text
        field.setAccessibilityValue(text)
        field.isEnabled = isEnabled
        clearButton.isHidden = !clearVisible
        clearButton.isEnabled = isEnabled && clearVisible
        if let cell = field.cell as? InsetTextFieldCell {
            cell.alignment = .center
            // Centre the value in the area left of the clear button so a long
            // combo can never sit under it.
            let rightInset: CGFloat = clearVisible
                ? Self.clearInset + Self.clearHit + 2
                : 4
            cell.textInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: rightInset)
        }
    }
}

/// Read-only field that forwards clicks and Space/Return to the recorder so the
/// control has a keyboard path.
final class RecorderTextField: NSTextField {
    var onActivate: (() -> Void)?

    init() {
        super.init(frame: .zero)
        let cell = InsetTextFieldCell(textCell: "")
        cell.isBezeled = true
        cell.bezelStyle = .roundedBezel
        cell.controlSize = .small
        cell.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        cell.alignment = .center
        cell.lineBreakMode = .byTruncatingTail
        cell.usesSingleLineMode = true
        self.cell = cell
        isEditable = false
        isSelectable = false
        focusRingType = .default
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49, 76: // Return, Space, keypad Enter
            onActivate?()
        default:
            super.keyDown(with: event)
        }
    }
}
