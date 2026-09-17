# 界面收紧：搜索对齐、快捷键与大日历 — 实施与验证记录（2026-09-17）

> **历史记录**：本文记录 UI 收紧那一轮的实现与证据；其大日历尺寸已被 [CALENDAR_PANEL_FINAL_LAYOUT_2026-09-17.md](CALENDAR_PANEL_FINAL_LAYOUT_2026-09-17.md) 取代。正文按当时事实保留。

按 `docs/UI_COMPACT_ALIGNMENT.md` 实施（覆盖 `CALENDAR_PANEL_UI_FOLLOWUP.md` / `SEARCH_AND_YEAR_NAVIGATION.md` 中冲突的控件尺寸、大日历间距与事件布局）。验收对象为构建产物 `build/Build/Products/Release/CalMon.app`；**未安装、未替换正式 App、未提交、未发布、未触发 Homebrew**。未执行项不视为通过。

## 1. 构建与测试

```sh
xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Release -derivedDataPath build build  # ** BUILD SUCCEEDED **
xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Debug  -derivedDataPath build test   # ** TEST SUCCEEDED **
```

- 全量 **106 项测试全部通过**（较上轮 104 项 +2，更新布局常量断言）：`H=max(328,64+56n)`=328/344/400、上下留白 116/108/80、4 行专属 40 pt 网格前留白、5/6 行为 0、事件区 132=3×40+2×6、上半区 176、最小块高可容纳三条事件、`CalendarGridMetrics.panel` 行高 56、`CalendarInfoMetrics.panel` 卡片 40 且标签垂直居中。
- 改动：`Calendar/CalendarComponents.swift`（行高 56、卡片 40、标签居中开关）、`Calendar/CalendarPanelView.swift`（收紧节奏 + 事件底对齐 + 溢出滚动）、`Settings/SettingsView.swift`（104×24 录入框、居中值、内联 ×）、`Monitoring/MonitoringView.swift`（原生紧凑搜索框）、`App/InsetTextFieldCell.swift`（新增，原生文本内边距 cell）。

## 2. 搜索：边界与输入拥挤

- 收起仍为右对齐 24 pt 圆形放大镜（实测其 24 pt 命中框右边缘与占用条轨道右边缘同为 769 px，0 差）。
- 展开改为 **NSSearchField → 原生 `NSTextField`(roundedBezel/small) + 内联无边框清除按钮**：不再内置放大镜（规格要求有焦点/有查询时隐藏），文字左内边距 6 pt，清除命中 20 pt、尾端内边距 2 pt、与文字区至少 2 pt，清除出现不移动外框。
- 实施中发现并修复一个真实缺陷：自定义 cell 同时在 `drawingRect` 与 `edit/select` 里加内边距，导致字段编辑器宽度被二次收窄为 0，**输入文字不可见**（模型查询与筛选正确）。现只在 `drawingRect` 加内边距，文字正常显示并随长查询水平滚动。
- 截图：`37-search-collapsed.png`、`38-search-empty-focus.png`（占位“搜索”+焦点环，无清除）、`39-search-cjk.png`（输入“飞”→ 仅“飞书”）、`40-search-long-cjk.png`（`这是一个很长的中文查询` 在框内水平滚动，清除按钮不遮挡文字；结果“未找到匹配应用”）。
- 可见边框对齐：展开框 64×24 pt 位于标题行尾端，与下方占用条同为卡片内容右边界；逐像素测量换算成 pt 存在 ±1 物理像素不确定度，截图 38 中展开框与轨道右端在同一列，未越过轨道左端（轨道 642..769 px，展开框可见边框约 644..771 px，焦点环再外扩 ~2 px）。

## 3. 快捷键：紧凑录入框

- 控件 140 → **104×24 pt**，右边缘仍对齐卡片尾端内容线；已设置时组合在“除清除区外”区域内水平居中；未设置“设置快捷键”，录制中“请按键…”。
- 清除 20×20 命中、右内边距 4 pt、符号 12 pt；所有状态外框同宽；错误提示独立下一行。
- 截图：`41-hotkey-set.png`（真实用户组合 `⌘R`）、`42-hotkey-recording.png`（请按键…，× 保留）、`43-hotkey-unset.png`（设置快捷键，无 ×）、`44-hotkey-long.png`（`⌃⌥⇧⌘R` 居中且不遮挡 ×）、`45-hotkey-conflict.png`（错误行在下方，控件右边界不动）。
- 注册/冲突/取消/清除语义未改；用户组合未被改动（验证后已写回 `keyCode=15, modifiers=256`）。

## 4. 大日历：收紧节奏与事件底对齐

右栏：标题带 32、标题后 6、星期带 22、星期后 4、日期行 **56**；`H=max(328, 64+56n)`；4 行月份的 40 pt 余量放在星期带与网格之间，使真实网格贴共同底线。

左栏上半区固定 176 pt（32+6+12+56+8+20+16+6+20），时钟字号保持 48；分隔线为水平线，线后 8 pt；事件组贴共同底线。

事件：卡片目标 40 pt、间距 6 pt、三条 132 pt；≤3 条为普通静态列表（无滚动容器、无滚动条），最后一张卡可见底边与右栏最后一行日期格底边对齐；>3 条时复用同一 132 pt 高度的局部滚动区（隐藏指示条），并在分隔线上方显示低调的“共 N 条”提示；来源失败说明复用同一位置。计数包含“今天/距今天还有…”相对日期行。

- 截图：`33-panel-base-880x560.png`（5 行 + 1 条）、`34-panel-4rows.png`（4 行 + 1 条，网格前 40 pt 余量可见）、`35-panel-6rows.png`（6 行 + 1 条）、`36-panel-1100x700.png`（1.25×，全部尺寸同步放大）。
- 左右标题基线：与上一轮测量方法相同（2x 截图首行深色像素），本轮 33/34/35 均为左 0 px 差。

## 5. 未执行 / 受限项

本机 `AXIsProcessTrusted=false`（无法合成鼠标/键盘），构建产物 `access=notDetermined`（未授予日历权限）。以下**未执行**：

- **真实鼠标拖动**窗口边缘/角观察拖动过程中内容连续等比缩放；本轮仅用 `CALMON_PANEL_SIZE` 程序设置 880×560 / 1100×700（及 990×630）验证同一“真实容器尺寸→比例”通路。
- **真实点击/键入**：点击圆形入口展开并键入（含中文候选）、点击 × 清除、点击四个导航按钮、点击录入框录入/取消。第 2/3 节的输入与清除态由环境钩子注入状态截图（布局与真实一致），未实测点击/键入路径。
- **1/2/3 条事件与 >3 条溢出**：本机无日历授权，面板只有相对日期 1 条；三条完整显示、底对齐与溢出滚动区域未用真实数据验证（布局常量由测试覆盖）。`34/35` 中仍为 1 条。
- 减少透明度/增加对比度外观；多显示器拔屏；真实拖动后的比例持久化（上一轮用户实测已拖动并保存 1.3636）。

## 6. 还原与说明

- 捕获钩子均为环境变量触发，正常使用不设置、不改变产品行为；`CALMON_SEARCH_DEBUG` 等临时调试输出已移除，Release 仅保留既有 `CALMON_CAPTURE`/`CALMON_PANEL`/`CALMON_SETTINGS` 族。
- 验证期间临时改动并已还原：`calendar.panel.hotKeyCode/Modifiers`（用户 `⌘R`）、`menuBar.calendar.enabled`、`calendar.panel.scale`（用户拖动值，`defaults` 浮点写回有 1e-8 量级差异）。

## 7. 复现

```sh
# 大日历：基准/4行/6行/放大
CALMON_PANEL_SIZE=880x560  CALMON_CAPTURE=panel build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
CALMON_SELECT_DATE=2027-02-15 CALMON_CAPTURE=panel build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
CALMON_SELECT_DATE=2026-08-15 CALMON_CAPTURE=panel build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
CALMON_PANEL_SIZE=1100x700 CALMON_CAPTURE=panel build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon

# 搜索四态
CALMON_CAPTURE=monitoring build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
CALMON_SEARCH= CALMON_CAPTURE=monitoring build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
CALMON_SEARCH=飞 CALMON_CAPTURE=monitoring build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
CALMON_SEARCH=这是一个很长的中文查询 CALMON_CAPTURE=monitoring build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon

# 快捷键五态（设置窗口需前台，本机用 NSRunningApplication.activate）
CALMON_CAPTURE=settings build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
CALMON_SETTINGS_RECORD=1 CALMON_CAPTURE=settings build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
CALMON_SETTINGS_ERROR='快捷键无法注册或已被占用，请换一个' CALMON_CAPTURE=settings build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
```

## 8. 结论

- 通过：Release/Debug 构建、106 项测试、搜索收起/展开边界与输入拥挤修复（含编辑器零宽缺陷）、快捷键 104 pt 紧凑五态、大日历 32/6/22/4/56 节奏与 4/5/6 行底对齐、事件 132 pt 三条区与 >3 条溢出实现、1.25× 等比。
- 未执行：真实拖动/点击/键入、真实 1/2/3 条与 >3 条事件、可访问性外观与多屏项（见 §5）。
