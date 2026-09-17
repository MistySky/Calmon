# 快捷键日历面板 — 实施与验证记录（2026-09-17）

> **历史记录**：本文记录 2026-09-17 快捷键面板那一轮的实现与证据（当时基准 880×560、11:7）。当前大日历基准见 [CALENDAR_PANEL_FINAL_LAYOUT_2026-09-17.md](CALENDAR_PANEL_FINAL_LAYOUT_2026-09-17.md)（900 宽、四边 50、按月份行数驱动高度）。正文按当时事实保留，不作改写。

本轮按 `docs/CALENDAR_HOTKEY_PANEL.md` 实现全局快捷键唤出的日历面板。本文只记录可复核的实现范围、命令、原始数值与未执行项；未执行项不视为通过。验收对象为构建产物 `build/Build/Products/Release/CalMon.app`（**未安装、未替换正式 App、未提交、未发布**）。

## 1. 工具链与构建

- 平台：macOS 27.0 (26A428)，MacBookPro18,1 / Apple M1 Pro / 10 核 / 32 GiB。
- Xcode 27.0 (27A266a)，Swift 6.4，SDK macOS 27.0，arm64 thin。
- 构建命令：

```sh
xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Release -derivedDataPath build build   # ** BUILD SUCCEEDED **
xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Debug  -derivedDataPath build test    # ** TEST SUCCEEDED **
```

- 新增/修改文件：`App/GlobalHotKeyController.swift`、`Calendar/CalendarPanelController.swift`、`Calendar/CalendarPanelView.swift`、`Calendar/CalendarComponents.swift`（新增）；`App/Preferences.swift`、`App/MenuBarController.swift`、`Calendar/CalendarModel.swift`、`Calendar/CalendarView.swift`、`Settings/SettingsView.swift`（修改）；`CalMonTests/HotKeyPanelTests.swift`（新增）。四个新源文件已登记进 `project.pbxproj`。
- 全局快捷键使用系统框架 Carbon/HIToolbox 的 `RegisterEventHotKey`/`UnregisterEventHotKey` + `InstallEventHandler`（`kEventHotKeyExclusive`），未新增第三方依赖、未新增辅助功能或输入监控权限，未使用 event tap、shell 命令或轮询。

## 2. 实现要点

- 窗口：单个 `NSPanel`（`.titled/.closable/.resizable/.fullSizeContentView`），隐藏标题文字与标题栏背景，隐藏最小化/缩放按钮（不提供最小化/全屏），层级 `.floating`，`contentAspectRatio = 11:7`，`contentMinSize/contentMaxSize` 按屏幕计算。
- 材质：单个 `NSVisualEffectView(material: .popover, blendingMode: .behindWindow, state: .active)` 外壳，Hosting 视图与滚动区透明，事件卡片沿用 `UIStyle.Colors.cardBackground`。
- 等比缩放：基准 880×560，`sFit = min((visibleW-48)/880, (visibleH-48-28)/560)`；正常范围 1…sFit，极小屏例外取 sFit；只在拖动结束（`windowDidEndLiveResize`）持久化 `calendar.panel.scale`；屏幕参数变化/窗口换屏时按同一公式重算。
- 互斥与生命周期：面板、月历弹窗、监控弹窗三界面互斥；打开面板先关闭两个弹窗；打开弹窗/设置先关闭面板；`windowDidResignKey` 关闭；Esc（`cancelOperation`）关闭；休眠（`willSleepNotification`）关闭且唤醒不自动弹出；关闭日历关闭面板并注销快捷键。
- 每次打开 `resetToToday()`；日期状态不恢复、窗口比例恢复。
- 时钟：`PanelClock` 只在面板可见时启动，1 次/秒；`stop()` 后丢弃在途回调（见 §5 时钟计数）。
- 快捷键：主线程单注册、单事件入口；长按去抖 0.35 s；校验需 ⌘/⌃ + 字母/数字，拒绝 ⌘Q/⌘,/空格 等；改绑先注册新组合，失败恢复旧组合并保留旧值；录入期间临时注销现有快捷键，避免录入旧组合时弹出面板。

## 3. 自动化测试

- 全量测试 **93 项全部通过**（0 失败）：`MonitoringTests` 36、`CalendarTests` 28、`LifecycleTests` 10、`HotKeyPanelTests` 19。
- `HotKeyPanelTests` 覆盖：快捷键校验（缺修饰键/缺主键/保留组合）、Carbon 修饰键转换与符号顺序、`UCKeyTranslate` 显示串、`Preferences` 快捷键与比例往返、比例公式（普通屏 1…sFit、大屏最小 1、极小屏取 sFit、11:7）、时钟启停（重复 start 不叠加计时器）、Carbon 注册/注销与排他冲突失败、面板只读访问点（日期/星期/ISO 周/农历）及 ISO 周不随周起始设置变化。

## 4. 运行与截图证据

所有截图与数值来自 Release 构建产物（除标注 Debug 的挂件压力）。截图清单：

| 文件 | 内容 |
|---|---|
| `screenshots/11-panel-base.png` | 基线 880×560，浅色，活动态 |
| `screenshots/12-panel-125.png` | 1.25× = 1100×700，浅色 |
| `screenshots/13-panel-dark.png` | 基线 880×560，深色，活动态 |
| `screenshots/14-panel-plain-calendar.png` | 选中 2026-10-01，无系统节日数据时降级为普通公历/农历（`距今天还有 14 天`，未虚构节日/班休） |
| `screenshots/15-settings-hotkey.png` | 设置“日历快捷键”行（非活动窗口外观，见 §6） |
| `screenshots/16-material-light.png` | 浅色材质对照：面板 + 月历弹窗 + 监控弹窗 |
| `screenshots/17-material-dark.png` | 深色材质对照：面板 + 月历弹窗 |

- 窗口几何日志（stderr，`CALMON_PANEL`）：

```text
frame={{2248, 281}, {880, 560}} contentView={{0, 0}, {880, 560}} safeArea=NSEdgeInsets(top: 32.0, left: 0.0, bottom: 0.0, right: 0.0) storedScale=1.0
frame={{2138, 211}, {1100, 700}} contentView={{0, 0}, {1100, 700}} ... storedScale=1.25
```

内容区为 880×560 / 1100×700，比例 11:7；`fullSizeContentView` 下 `contentView` 即内容区，标题栏浮于内容上方，安全区忽略后内容正好 880×560（今天按钮距底 24 pt）。

- 材质对照方法：三次独立运行同一 Release 产物，在同一外接屏、同一壁纸、同一系统外观下分别截图（面板 `.floating` 可直接截到，弹窗用窗口清单确认在屏后截图）；不是同一时刻的叠加截图，差异已如实列出。

## 5. 性能与生命周期（Release）

### 5.1 面板可见、监控关闭 5 分钟

命令：`CALMON_CAPTURE=panel CALMON_PANEL_HOLD=1`（监控 `menuBar.monitoring.enabled=false`），预热后逐分钟用 `footprint`/`ps` 采样，并核对 CalMon 窗口仍在屏（`calmon_windows` 非 0）：

| 时刻 | physical footprint | RSS | ps %CPU | 在屏窗口 |
|---|---|---|---|---|
| 预热后 | 31 MiB | 98.5 MiB | 0.8% | 1（面板） |
| t+1min | 31 MiB | 98.5 MiB | 0.1% | 1 |
| t+2min | 31 MiB | 98.5 MiB | 0.0% | 1 |
| t+3min | 31 MiB | 98.7 MiB | 0.4% | 1 |
| t+4min | 32 MiB | 99.4 MiB | 0.1% | 1 |
| t+5min | 31 MiB | 99.8 MiB | 1.1% | 1 |

- 预算（`ACCEPTANCE.md` §6.1 / `CALENDAR_HOTKEY_PANEL.md` §8）：平均进程 CPU ≤2%、physical footprint ≤220 MiB。实测 footprint 31–32 MiB、逐分钟 `ps %CPU` 峰值 1.1%，均满足。
- `ps %CPU` 是短窗口值，不是 5 分钟均值；5 分钟窗口内进程无持续 CPU 占用（多数采样 0.0–0.4%）。
- 未执行 idle wakeups 计数（本机无法可靠归因 App 自建回调）；时钟回调次数以 §5.2 的 Debug 计数为准。

（原始输出：`docs/validation/measurements/panel-5min-2026-09-17.txt`。）

### 5.2 开关与时钟计数（Debug 挂件压力，50 次开关）

```text
STRESS panel before=32MiB after=32MiB delta=0MiB visibleTicks30s=29 closedTicks20s=0
```

- 50 次打开/关闭后静置 footprint 增长 0 MiB（Debug 基线 32 MiB）。
- 可见 30 秒时钟回调 29 次（≈1 次/秒，符合 §8“平均 ≤1.1 次/秒”）。
- 关闭后 20 秒新增时钟回调 0 次（修复：`stop()` 后在途回调被丢弃）。

## 6. 未执行 / 受限项

本机 `AXIsProcessTrusted=false`，无法合成键盘/鼠标事件；且构建产物 `access=notDetermined`（无 EventKit 授权）。以下**未执行**，需人工或授权后复核：

- 真实全局快捷键从其他应用前台唤出、长按去抖、系统保留组合不被吞掉；真实边缘拖动缩放 1×/1.25×/1.5×；Cmd-Tab 与点击桌面关闭。
- 真实多显示器下拔屏、窗口移至更小屏幕后的收回。
- 新旧日历在**有系统日历数据**时的日期/农历/周数/事件/班休一致性；本机无授权，面板正确降级为普通公历/农历（见 `14-panel-plain-calendar.png`，未虚构节日或班休）。
- 与两个弹窗的同屏活动态材质对照：面板为 `.floating` 可直接截图，设置窗口为非活动态；活动态对照需人工。
- 减少透明度/增加对比度外观。

以上均不因“使用原生 API”而宣称通过。

## 7. 复现

```sh
# 面板基线与放大
CALMON_CAPTURE=panel       build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon     # stderr: CALMON_PANEL ...
CALMON_CAPTURE=panel-scaled build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon    # 会写入 calendar.panel.scale=1.25，测量后删除该键

# 指定日期（如节日/降级演示）
CALMON_SELECT_DATE=2026-10-01 CALMON_CAPTURE=panel build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon

# 开关/时钟计数（Debug）
CALMON_CAPTURE=panel-stress build/Build/Products/Debug/CalMon.app/Contents/MacOS/CalMon       # stderr: STRESS panel ...
```

`CALMON_PANEL_HOLD=1` 仅在 `CALMON_CAPTURE=panel` 分支内生效：用于本机无法合成输入时保持面板可见（同时在该诊断路径关闭“失焦即关”）。正常使用不设置、不触发，产品行为仍是失焦即关。

## 8. 结论

- 通过：Release/Debug 构建、93 项测试、面板基线与等比放大几何与内容区尺寸、新文件登记、注册/注销/排他冲突回退（单元级）、50 次开关足迹与时钟启停计数、无授权时的普通日历降级、浅/深色与两弹窗的材质对照截图。
- 未执行（本机限制）：真实快捷键唤出与长按去抖、真实边缘拖动 1×/1.25×/1.5×、Cmd-Tab/点击桌面关闭、多显示器拔屏与跨屏收回、有系统日历数据时的新旧一致性、活动态设置窗口外观、减少透明度/增加对比度外观。详见 §6。
- 性能：面板可见 5 分钟 footprint 31–32 MiB、CPU 峰值 1.1%，50 次开关 +0 MiB、关闭后时钟回调 0 次。
- 说明：本机同时运行着正式安装版 `1.5`（菜单栏常驻）。验收只运行构建产物，未安装、未替换、未提交、未发布、未触发 Homebrew；过程中临时改动过的系统外观与 `menuBar.monitoring.enabled` 均已还原，`calendar.panel.scale` 已删除。

以上未执行项不视为通过，交独立验收方在具备交互与日历授权的环境复核。
