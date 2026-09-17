# 快捷键面板布局/缩放 + 搜索与年份导航 — 实施与验证记录（2026-09-17）

> **历史记录**：本文记录布局/缩放/搜索/年份导航那一轮的实现与证据；大日历尺寸与居中方案已被 [CALENDAR_PANEL_FINAL_LAYOUT_2026-09-17.md](CALENDAR_PANEL_FINAL_LAYOUT_2026-09-17.md) 取代。正文按当时事实保留。

按 `docs/CALENDAR_PANEL_UI_FOLLOWUP.md`（F1 录入框、F2 居中与标题基线、F3 实时等比缩放）与 `docs/SEARCH_AND_YEAR_NAVIGATION.md`（监控搜索入口收起、双日历年份导航）实施。验收对象为构建产物 `build/Build/Products/Release/CalMon.app`；**未安装、未替换正式 App、未提交、未发布、未触发 Homebrew**。未执行项不视为通过。

## 1. 构建与测试

```sh
xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Release -derivedDataPath build build  # ** BUILD SUCCEEDED **
xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Debug  -derivedDataPath build test   # ** TEST SUCCEEDED **
```

- 全量测试 **104 项全部通过**（0 失败，较上轮 93 项新增 11 项）：年份导航（保日号/跨年/闰日截断/单月仍单步）、`PanelLayout`（H=88+64n、上下留白 108/76/44、事件区 83/147/211、s=内容宽高推导）、`AppSearchModel`（清除与失焦收起规则、空白非查询）。
- 改动文件：`Calendar/CalendarModel.swift`（`goToPreviousYear/goToNextYear`）、`Calendar/CalendarView.swift`（弹窗四个导航按钮）、`Calendar/CalendarPanelView.swift`（居中内容块 + 实测比例 + 年份导航 + 移除底部今天按钮，新增 `PanelLayout`）、`Calendar/CalendarPanelController.swift`（不再在 resize 路径重建内容；仅用户拖动结束保存比例）、`Settings/SettingsView.swift`（F1 原生组合录入框 + 错误行）、`Monitoring/MonitoringView.swift`（收起/展开搜索入口）、`App/MenuBarController.swift`（接线与捕获钩子）、`App/UIStyle.swift`（移除独立搜索宽度常量）。

## 2. F1 设置录入框

- 实现：`HotKeyRecorderView` 改为一个原生组合控件 `RecorderControl`：带边框 `NSTextField`（small，只读、可聚焦、Space/Return 可触发录入）+ 框内右下角无边框 `NSButton`（`xmark.circle.fill`，12 pt，20×20 命中，右内边距 6 pt）。未使用按钮套按钮，未自绘仿原生外框。
- 四态截图（控件右边缘均与同组开关/权限按钮尾端对齐，× 均在框内）：
  - 设置后：`screenshots/24-settings-hotkey-set.png`（真实用户组合 `⌘R`，日志 `hotKey=⌘R`）
  - 未设置：`screenshots/25-settings-hotkey-unset.png`（“录入快捷键”，× 隐藏）
  - 录制中：`screenshots/26-settings-hotkey-recording.png`（“请按快捷键…”，× 保留以便结束并清除）
  - 冲突错误：`screenshots/27-settings-hotkey-conflict.png`（错误文案位于控件下方独立右对齐行，控件右边界未移动）
  - 禁用（关闭日历）：`screenshots/28-settings-hotkey-disabled.png`
- 交互语义未改：清除 → 注销并移除保存值；改绑先注册新值、失败保留旧值；录制期间临时注销现有快捷键。

## 3. F2 有效内容居中与标题基线

- 实现：删除固定 512 pt 双列、固定六行占位、底部“今天”按钮及其占位；`H = 88 + 64n`，两块左右栏放进同一内容块由上下 `Spacer` 均分（等价于 Y=(560−H)/2）；左栏 261 pt 之后为事件区，高 (H−261)；左右标题同用 40 pt 标题带、20 pt medium。
- 实测（1760×1120 px 截图，2x）第一行深色文字（标题）顶边：

| 截图 | 月份行数 | 左标题顶边 | 右标题顶边 | 差值 |
|---|---:|---:|---:|---:|
| `18-panel-base-880x560.png` | 5 | 175 px | 175 px | 0 px |
| `21-panel-4rows-2027-02.png` | 4 | 239 px | 239 px | 0 px |
| `22-panel-6rows-2026-08.png` | 6 | 111 px | 111 px | 0 px |

0 物理像素差，满足“≤1 个物理像素”。上下留白随行数变化（4/5/6 行）且相等，见上表与截图；底部独立“今天”按钮已消失，事件中的“今天”相对日期行保留（见 18 号截图“全天 今天”）。

## 4. F3 实时等比缩放

- 实现：`CalendarPanelView` 根布局改为观察真实容器尺寸推导 `s = min(宽/880, 高/560)`；`CalendarPanelController` 不再在显示/换屏时重建 hosting 根视图，拖动过程中 SwiftUI 容器布局直接更新内容。
- 几何日志（Debug 钩子 `CALMON_PANEL_GEOMETRY`，容器即内容区）：

```text
container=(880.0, 560.0)   scale=1.0
container=(990.0, 630.0)   scale=1.125     ← 非基准中间尺寸，内容按 1.125 渲染
container=(1100.0, 700.0)  scale=1.25
container=(1320.0, 840.0)  scale=1.5
```

- 截图：`19-panel-990x630.png`、`20-panel-1320x840.png` 与 `18-panel-base-880x560.png` 对比：时钟字号、日期行高、栏间距、卡片与按钮同步放大，圆仍为圆。
- 修复一处持久化缺陷：程序性 `setContentSize`（显示、换屏、捕获）也会触发 `windowDidEndLiveResize`，曾把中间尺寸写入偏好；现以 `windowWillStartLiveResize` 标记只在用户拖动结束时保存。
- **真实鼠标拖动仍未执行**（见 §7）；上表尺寸由程序设置，只能证明“实际容器尺寸 → 内容比例”通路，不代表已通过真实拖动验收。

## 5. 年份导航（两个日历）

- 实现：内侧单 chevron 切月保持原行为；外侧双 chevron 调用新增的 `goToPreviousYear/goToNextYear`，内部即 `changeMonth(by: ±12)`，单次调用、复用既有日期钳制，不连续调用 12 次切月、不新建事件查询。
- 截图：`31-calendar-yearnav-today.png` 与 `18-panel-...` 显示 `« ‹ 2026年9月 [今天] › »`，标题居中、按钮不碰撞；`23-panel-leap-2029-02-28.png` 与 `32-calendar-year-jump-leap.png` 显示 2028-02-29 经一次年份前进后到 2029 年 2 月 28 日（闰日按月末截断），农历、ISO 周、星期与事件行同步更新。
- 单元测试：`testYearNavigationKeepsDayOfMonth`、`testYearNavigationClampsLeapDay`（再前进一年仍为 28，无隐藏“原始日号”）、`testYearNavigationCrossesYearBoundary`、`testMonthNavigationStillSingleStep`。

## 6. 监控搜索入口收起

- 实现：`AppSearchModel` 增加 `isExpanded`、`trimmedQuery/isFiltering`、`beginPresentation()`、`endEditing()`；标题行右侧收起为 24 pt 圆形放大镜按钮，点击向左展开为原生 `NSSearchField`，展开宽度 = `applicationBarWidth − 4 pt`（预留原生边框描边），右侧固定；标题行固定 24 pt。
- 行为：重新打开面板 → 清空并收起；清空文字保持展开与焦点；空查询失焦收起、有查询失焦保持；Esc 语义未改（中文候选优先、有查询先清空、空查询关闭面板）。匹配、排序、无结果与“查看更多”逻辑未改。
- 截图：`29-monitoring-search-collapsed.png`（圆形入口，右边缘与占用条右边缘一致）、`30-monitoring-search-expanded.png`（输入 "Chrome" 后仅 Chrome 命中）、`30b-monitoring-search-expanded-cjk.png`（输入 "飞" 命中"飞书"，聚合行未拆分）。
- 像素对齐（2x）：占用条 track 右边缘 771 px，展开框右边缘 771 px（差 0 px）；track 左边缘 644 px，展开框可见左边框约 648 px（在条内），未越过。
- **宽度缺口（按要求如实报告）**：在 64 pt 上限下，原生搜索框的放大镜与清除按钮占据大部分宽度，实际文本可视区仅约 1 个字符宽（截图 30/30b 可见字段只显示 "C"/"–"，但模型查询为完整字符串、筛选结果正确）。输入、清除与内部滚动可用，但可读性差。按规格要求不越过左边界，此处提交尺寸与截图，未擅自加宽。

## 7. 未执行 / 受限项

本机 `AXIsProcessTrusted=false`，无法合成鼠标与键盘；构建产物 `access=notDetermined`（无 EventKit 授权）。以下**未执行**：

- 真实鼠标拖动窗口边缘/角观察拖动过程中内容连续缩放（仅用程序设置尺寸验证同一通路）；真实点击四个导航按钮、点击圆形放大镜并键入（含中文 IME）、点击 × 清除。
- 减少透明度/增加对比度外观；多显示器拔屏/等比收回；有系统日历数据时的年份跳转事件一致性。
- 浮动窗口与被测弹窗的同步活动态材质对照（沿用上轮结论）。
- `未设置/录制中/冲突` 三态的**真实操作**入口（截图通过 env 钩子注入状态，控件布局与真实一致，但点击/键入路径未实测）。

## 8. 说明与还原

- 捕获钩子（`CALMON_PANEL_SIZE`、`CALMON_YEAR_JUMP`、`CALMON_SETTINGS_RECORD/ERROR`、`CALMON_SEARCH`、`CALMON_PANEL_HOLD`）仅由环境变量触发，正常使用不设置、不改变产品行为。
- 验证期间临时改动的用户偏好均已还原：`calendar.panel.hotKeyCode/Modifiers`（用户的 `⌘R`）已按原值写回；`menuBar.calendar.enabled` 已恢复；`calendar.panel.scale` 恢复为用户拖动值（`defaults` 以 float 写回，存在 1e-8 量级浮点差，视觉与行为一致）。
- 用户已在真实使用中拖动过面板并把比例持久化为 1.3636、录制了 `⌘R`，这本身是 F3 持久化与 F1 录入真实可用的旁证；本轮未对其做破坏性测试。

## 9. 复现

```sh
# 基准/中间尺寸/放大（内容比例由真实容器推导）
CALMON_PANEL_SIZE=880x560  CALMON_CAPTURE=panel build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
CALMON_PANEL_SIZE=990x630  CALMON_CAPTURE=panel build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
CALMON_PANEL_SIZE=1320x840 CALMON_CAPTURE=panel build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon

# 4/5/6 行与闰日
CALMON_SELECT_DATE=2027-02-15 CALMON_CAPTURE=panel build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
CALMON_SELECT_DATE=2028-02-29 CALMON_YEAR_JUMP=1 CALMON_CAPTURE=panel build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon

# 搜索收起/展开
CALMON_CAPTURE=monitoring build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
CALMON_SEARCH=飞 CALMON_CAPTURE=monitoring build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
```

## 10. 结论

- 通过：构建、104 项测试、F1 四态布局与右端对齐、F2 4/5/6 行居中与标题 0 px 基线差、F3 真实容器尺寸→比例通路与持久化时机修复、双日历年份导航与闰日截断、搜索入口收起与宽度边界（含如实报告的宽度缺口）。
- 未执行：真实鼠标拖动/点击/键入、IME、可访问性外观与多屏项（见 §7）。
