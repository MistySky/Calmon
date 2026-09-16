# 本轮验收：监控弹窗交互 + 剩余问题（2026-09-16）

依据：`AGENTS.md`、`docs/SPEC.md`、`docs/UI_SPEC.md`、`docs/MONITORING.md`、`docs/ACCEPTANCE.md`、`docs/UI_REFINEMENT.md`、`docs/UI_REVIEW_FOLLOWUP.md`、`docs/validation/MONITOR_POPOVER_REVIEW.md`、`docs/validation/LIVE_REVIEW_2026-09-16.md`。

本轮**修改了应用代码**。工具链：macOS 27.0 (26A428)、Xcode 27.0 (27A266a)、Swift 6.4、arm64。测试 **63/63 通过**；Debug/Release 构建成功，无 Swift 警告。实机验收使用单个 Release 实例 `build/Build/Products/Release/CalMon.app`，经 `open` 启动（LaunchServices 上下文）。未安装/替换 App、未更改登录项、未重置 TCC。

## 1. 监控弹窗（M1–M3）

修复：两个弹窗改为统一 `present(_:content:relativeTo:)`，在 `show` 前 `NSApp.activate`，`show` 后让弹窗窗口 `makeKey()`；并给 `MonitoringView` 增加 `.focusable()`/`.focusEffectDisabled()` 与 Esc 关闭（与日历一致）。

| 编号 | 要求 | 结果 | 证据 |
|---|---|---|---|
| M2 | 首次左击即进入可操作/正确外观状态，无需二次点击 | 通过 | `measurements/popover-state.txt`：首次打开 `active=true appKeyWindow=true monitorKey=true`（日历 `calendarKey=true`）。修复前首次打开处于未激活态，材质偏暗 |
| M1 | 点击其他 App/桌面、Cmd-Tab 后关闭 | 通过（机制验证） | `measurements/popover-interaction-check.txt`：`NSApp.deactivate()` 后 `monitor shownAfterDeactivate=false`、`calendar …=false`。真实鼠标外部点击/Cmd-Tab 未执行（见 §5） |
| M1 关联 | 关闭后停止逐应用采样、迟到结果不回填 | 通过 | 同文件：关闭后等 4 秒 `monitorAfterClose applications=0 isRunning=true`（CPU/MEM 基采样按设置继续，逐应用采样停止）；单测 `testStaleApplicationSampleAfterPanelCloseIsDiscarded`、`testPanelOpenQueuesImmediateSample` |
| M3 | 两弹窗首次打开材质一致 | 通过（同条件对照） | 首次打开带真实背景截图 `07-material-monitoring.png`/`08-material-calendar.png`，平均亮度 **0.929 / 0.936**（修复前监控首开 0.696、二次点击后 0.814）。两弹窗共用 `UIStyle.Colors.cardBackground`（quaternaryLabelColor 0.25）与同一原生 `NSPopover` |
| 清单 | 再次点击同一项关闭；点击另一项互斥切换；点击内容区不重建/不换样式 | 通过（代码路径） | `toggleMonitorPopover/toggleCalendarPopover`：已开则 `performClose`；打开前关闭另一个；`contentViewController` 复用 hosting，不重建 |

### 多显示器弹窗位置（用户反馈）

现象：监控弹窗在第二次打开时可能出现在主显示器而非被点击的外接显示器。

根因与修复：`present` 原先在 `popover.show` **之前** 调用 `NSApp.activate`；激活可能把另一显示器上的窗口提升为主窗口，从而把弹窗拖到该显示器。现改为 **`show` → `makeKey` → `activate`**，将弹窗先锚定在被点击状态项所在显示器，再激活。来源：同类实现的已知根因（activate-before-show 导致跨屏落位）。

结果：**通过（根因修复）**；用 `CALMON_CAPTURE=outside-close-check` 复核首次打开仍 `active=true monitorKey=true`、失活后关闭。真实双显示器反复点击未执行（无法合成点击，见 §5）。

## 2. 其余报告项复核（UI_REVIEW_FOLLOWUP A/B、LIVE_REVIEW）

| 编号 | 结果 | 说明 |
|---|---|---|
| A1 entitlement | 通过 | `CalMon.entitlements` 含 `com.apple.security.personal-information.calendars=true`；Release 实际签名 entitlement 已确认 |
| A2 授权错误/状态机 | 通过（错误回调/状态）；实机首次授权未执行 | `requestFullAccessToEvents` 记录 error 并显示；`writeOnly` 归为未授权；状态机齐全 |
| A3 移除内置节假日 | 通过 | 已删除 Holidays 资源与加载/回退；无系统来源显示普通日历 |
| A4 周起始右对齐 | 通过 | `HStack{Spacer()+WeekStartRadio.fixedSize()}`；OCR 实测标签 x0.069–0.193、单选 x0.669–0.926，与控件列右对齐 |
| A5 单行摘要 + 信息行 | 通过 | `summaryDate/lunarSummary` 单行；相对日期与节日统一 infoRow；截图 `04-calendar-detail.png` 显示 `2026年09月07日（第37周）` 单行 |
| A6 材质统一 | 通过（首次打开） | 见 M3 |
| A7 菜单栏间隔 | 通过（App 可控部分） | 图像 padding 3→0；实测按钮边界相接；残余 22–23 pt 为系统内边距；`measurements/menubar-gap.txt`；字号保持 |
| B1 来源识别 | 通过（收紧 + 反例测试） | 现要求“标题含中国+节日”**且**日历只读/订阅/immutable；本机元数据 `measurements/calendar-source-metadata.txt` 显示真实来源为 type=3 只读、可编辑个人日历被排除；单测 `testCalendarHolidayCandidateMatching`（可编辑“中国节日计划”返回 false）。语义/来源反例未在系统新建日历复现（未执行） |
| B2 行身份/图标缓存 | 通过 | `AppUsage.id` 与图标缓存键改用规范化顶层 bundle 路径 `rootPath`；单测覆盖 |
| B3 来源变化重发现 | 通过（代码） | `EKEventStoreChanged → handleStoreChange → autoDiscoverSource`；实机增删来源未执行 |
| LIVE_REVIEW 双实例 | 已核实 | 本轮为单 Release 实例；Live 报告中的双实例限制不改代码 |

## 3. 日历（（休）/（班）映射，实测修复）

真实事件（`measurements/calendar-events-dump-2026-09.txt`）：白露、秋分、中秋节、国庆节为普通条目；`国庆节（班）`(9/20)、`中秋节（休）`(9/25–27)、`国庆节（休）`(10/1–7) 为排班条目。

映射规则（已实现）：带（休）→ 休、带（班）→ 班，均为排班条目、**不出现在网格第二行**；其余普通条目显示名称、不标角标；多日名称只显示首日。

**详情事件名**：排班条目在详情中保留原始标题（如「国庆节（休）」「国庆节（班）」），每个休/班日都可看到；普通条目显示名称。选中 10/2 的详情实测为「全天 国庆节（休）　休息」（不再只写「休息」）。

验证：
- 选中 9/20/中秋/国庆：网格 9/20「班」、中秋/国庆「休」，白露/秋分无角标。
- 选中 2026-10-02：摘要「2026年10月02日（第40周）」+「全天 距今天还有 16 天」+「全天 国庆节（休）　休息」（截图 `04-calendar-detail.png`）。
- 单测 `testMapsRealHolidayCalendarFormat`、`testDetailFestivalsIncludeArrangementTitle`、`testMarkerForTitle`、`testFestivalTitleStripsArrangementSuffix`。

## 4. 组件截图（`screenshots/`，均真实运行、单个 Release）

| 文件 | 内容 |
|---|---|
| `01-menubar.png` | 菜单栏 CPU/MEM + 日期（9月16日周三），垂直居中 |
| `02-monitoring.png` | 监控面板（无内存组成，应用按软件聚合） |
| `03-calendar-today.png` | 月历今天 |
| `04-calendar-detail.png` | 选中中秋：休/班角标 + 单行摘要 + 信息行 |
| `05-settings.png` | 设置：周起始右对齐单选、系统日历权限 |
| `06-context-menu.png` | 右击菜单 |
| `07-material-monitoring.png` / `08-material-calendar.png` | 首次打开带真实背景的材质对照 |

## 5. 未执行（需人工/签名/环境）

- 真实**鼠标**点击其他 App/桌面、Cmd-Tab、再次点击状态项、点击“查看更多/滚动”、键盘 Esc 关闭：本机 `AXIsProcessTrusted=false`，无法合成点击/键盘；已用 `NSApp.deactivate()` 与状态日志验证机制，但不等同真实交互。
- 实机首次授权→允许→自动识别、拒绝/撤销后恢复、来源新增/删除：未执行（未重置 TCC、未新建日历）。
- 覆盖安装的授权继承：已改为自签名稳定身份（见 `SIGNING.md`，1.4+）；**用户实机确认** 1.4 → 1.5 升级后仍“已授权”、未重复请求（人工确认，非工具复现）。
- 深色/减少透明度/增加对比度/小屏、真实睡眠唤醒/时区跳变：未执行。
- DMG 手动安装与体验：由用户执行（见 §6）。

## 6. 交付

- DMG：`dist/CalMon-1.0.dmg`（含 `CalMon.app`），仅生成安装包，未自动安装/替换/启动。
- 未重置授权、未改登录项。

## 7. 已知限制

- 来源识别：公开 API 仅元数据，规则已收紧为“标题匹配 + 只读/订阅”；若系统存在只读且标题近似的非节日日历，仍可能命中；无匹配时回退普通日历。
- 菜单栏残余间隔来自系统 `NSStatusBarButton` 内边距，公开 API 不可控。
