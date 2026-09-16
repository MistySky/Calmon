import AppKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var preferences: Preferences
    let provider: HolidayProvider

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
            } header: {
                Text("日历").font(UIStyle.Fonts.groupTitle)
            }
            .disabled(!preferences.showCalendar)
        }
        .formStyle(.grouped)
        .frame(width: UIStyle.Metrics.settingsWidth)
        .task {
            provider.refreshAccessState()
            provider.autoDiscoverSource()
        }
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
