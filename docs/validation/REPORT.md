# REPORT — CalMon 验收报告

> 当前修复与独立执行结果以 [FIX_VALIDATION.md](FIX_VALIDATION.md) 为准。以下保留实施方历史记录；早期性能与准确性“通过”不代表修复后所有场景已重新测量。

状态图例：**通过** / **未通过** / **未执行**。本报告只陈述本次实际构建与运行的结果；未测项如实标“未执行”，不以后续承诺代替。

## 0. 平台与构建

| 项目 | 值 |
|---|---|
| 机器 | MacBookPro18,1 / Apple M1 Pro / 10 逻辑核（8P+2E） |
| 物理内存 | 34359738368 B = 32 GiB；页大小 16384 B |
| 系统 | macOS 27.0 (build 26A428) |
| 工具链 | Xcode 27.0 (27A266a)，Swift 6.4，SDK macOS 27.0，arm64 |
| 显示 | 内置 3456×2234 Retina（主屏 2x）；外接 3840×2160 |
| 活动监视器刷新 | 系统默认 |
| App build | `com.calmon.CalMon` 1.0 (1)，LSUIElement，ad-hoc 签名，Release 启用 Hardened Runtime |
| 产物 | `build/Build/Products/Release/CalMon.app` |
| 测试 | `xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Debug -derivedDataPath build test` → **62 tests, 0 failures**（见 §12） |

构建/运行细节见 `BUILD.md`，监控字段与实测见 `METRICS.md`，数据见 `DATA.md`，原始测量与对照见 `measurements/`，截图见 `screenshots/`。

## 1. 构建与范围（ACCEPTANCE §2）

| 项 | 状态 | 说明 |
|---|---|---|
| 无第三方包/二进制 SDK/数据库 | 通过 | 仅系统框架；无 SPM、无 Pod、无 DB |
| Debug/Release 可构建，Release 脱离调试器运行 | 通过 | 均 `BUILD SUCCEEDED`；性能测量均为脱离调试器的 Release |
| 无 Dock 图标/多余主窗口/特权 helper | 通过 | `LSUIElement=true`；仅设置窗口；无 helper/root |
| 登录项与隐私声明正确，不请求无关权限 | 通过 | `PrivacyInfo.xcprivacy` 声明 disk space/system boot time/user defaults；EventKit 仅在用户显式连接时请求 |
| 正式 AppIcon 正常，源包未覆盖 | 通过 | AppIcon 复制进 `Assets.xcassets/AppIcon.appiconset`，`docs/CalMon_AppIcon_Xcode` 未改 |
| 无历史写入/趋势图/个人日程/结束进程/范围外监控 | 通过 | 只持久化设置；无历史序列 |
| docs/、原型图、验收日志未进 bundle | 通过 | `Contents/Resources` 仅 AppIcon.icns/Assets.car/JSON/PrivacyInfo |

## 2. 交互与生命周期（ACCEPTANCE §3）

| 项 | 状态 | 说明 |
|---|---|---|
| CPU/MEM 与日期是两个独立状态栏项 | 通过 | 两个 `NSStatusItem`，`autosaveName` = `CalMon.Monitor`/`CalMon.Date`；截图 `01` |
| 分别左击打开对应面板 | 通过 | 同一 selector 路由；由 `CALMON_CAPTURE=monitoring/calendar` 触发并截图 `02`/`03` |
| 右击只出现“偏好设置…/退出” | 通过 | 截图 `05`（两个菜单项 + 分隔线） |
| 同时最多一个弹窗；重复/外部/Esc 关闭 | 通过 | 打开一个即关闭另一个；`behavior=.transient` |
| 设置窗口不重复创建 | 通过 | 复用同一 `NSWindow`（`isReleasedWhenClosed=false`） |
| 四种开关组合正确，全关仍可恢复 | 通过 | 全关时出现单一“日历+时钟”管理入口（截图 `06`），左击开设置，右击菜单 |
| 关闭监控不再查询；重开无重复定时器 | 通过 | `stop()` 失效 timer；`start()` 有 `isRunning` 守卫 |
| 休眠不保活、唤醒重建基线、不补跑 | 未执行（实机） | 逻辑有单测 `testMonitorWakeResetsBaseline`；本次未真实休眠验证 |
| 所有操作有键盘/辅助功能路径 | 未执行 | 控件均设 accessibility label；完整键盘遍历未逐项实机验证 |

## 3. 日历正确性（ACCEPTANCE §4）

| 项 | 状态 | 说明 |
|---|---|---|
| 4/5/6 行月份、周一周日起始、跨年、闰年、农历闰月 | 通过 | 单测 `testAllMonthsHaveFourToSixRows`、`testFebruary2026RowCounts`、`testWeekdayHeaderFollowsWeekStartPreference`、`testLunarLeapMonth2025` |
| 邻月切月、重开回今天、今天/选中状态 | 通过 | 单测 `testNeighborMonthSelectionSwitchesMonth`、`testResetToToday` |
| 节日优先、长名称可读、农历开关不隐藏班/休 | 通过 | 网格 `secondLine` 优先节日/节气；班/休独立于农历开关 |
| 日期详情、ISO 周数、生肖/农历、自然日差 | 通过 | 单测 `testISOWeeks`、`testRelativeText`、`testLunarNewYear2026` 等 |
| 时间跳变/时区/夏令时/跨午夜/唤醒无错日 | 未执行（实机） | `handleDayChange`/`handleTimeZoneChange` 有实现；本次未真实改时钟/时区验证 |
| 多日全天事件按范围显示、多来源去重 | 未执行（EventKit） | `HolidayProvider.map` 有逻辑与单测 `testNormalizeMergesSameNames`；受 TCC 限制未连真实日历 |
| 中国班/休对照官方逐条验证 | 通过 | 2024/2025/2026 与国务院通知逐日完全一致（见 `DATA.md`） |
| 交付当年年度数据完整，节气有来源覆盖 | 通过 | 2026 完整；节气 2025–2027 |
| 数据覆盖不足显示未知 | 通过 | 非覆盖年显示“该年度调休安排尚未收录” |
| 未授权/拒绝/删除/来源变更/无事件分别显示 | 部分 | 未连接/未授权/不可用状态已实现并有截图；授权后删除/变更未执行 |
| 快速切月无旧结果覆盖/重复查询/无限缓存 | 通过 | `generation` 校验丢弃过期结果；缓存仅当前范围 |

## 4. 监控准确性（ACCEPTANCE §5）

对照方法：同一瞬间读取系统工具与活动监视器同屏值；CPU 用 60 秒稳定负载窗口均值。原始数据见 `measurements/`。

| 项 | 状态 | 结果摘要 |
|---|---|---|
| CPU 确定性样本（空闲/全忙/混合/零增量/回绕/失败恢复） | 通过 | 单测 `testCPUIdleIsZero`、`testCPUFullIsOneHundred`、`testCPUMixed`、`testCPUZeroDeltaIsInvalid`、`testCPU32BitCounterWrap`、`testCPUNoPreviousBaselineIsInvalid` |
| 稳定 CPU 60s 均值偏差 ≤ 2 pp | 通过 | CalMon 41.37% vs 活动监视器 System+User 40.19%，偏差 **1.18 pp** |
| 稳定内存占比偏差 ≤ 1 pp | 单场景通过，完整场景待补验 | Memory Used = physical−(free−speculative)−fileBacked；原始字段复算 25.2422943115 GiB，与截图 25.24 相差约 0.00717 pp；截图有舍入，不声明逐字节精确吻合 |
| 内存完整字段映射有证据 | 通过 | 同瞬间逐字段对照（`METRICS.md` §3） |
| 应用归属无重复/无误合并；单 PID 与来源一致 | 通过 | 最长前缀唯一归属；PID 3214/6682/2192 与活动监视器逐字节一致 |
| 部分不可读明确、不设零；覆盖多进程应用 | 通过 | WindowServer 读失败记“不可读取”；截图列表含 Chrome/Codex/ChatGPT/Lark 多 helper 行 |
| 菜单栏/圆环/文字/组成条同源 | 通过 | 全部读同一 `snapshot`；菜单栏与面板来自同一值 |
| 已用/总量/剩余与分项原始字节一致 | 通过 | 零取整公式；舍入差异见 `METRICS.md` §6 |
| 磁盘总量/可用/百分比同卷同口径 | 通过 | total 与 `diskutil` Container Total Space 完全一致 |
| 读取失败不保留旧值 | 通过 | 失败置 `nil` 显示 `--` |

## 5. CalMon 自身性能（ACCEPTANCE §6，Release / 无调试器）

| 场景 | 预算 | 实测 | 状态 |
|---|---|---|---|
| 监控开、弹窗全关 10 min | CPU ≤ 0.5% / footprint ≤ 120 MiB | CPU **0.012%** / **67.8 MiB**（预热平台期） | 通过 |
| 监控面板开 5 min | CPU ≤ 2% / footprint ≤ 220 MiB | CPU **0.008%** / **41.1 MiB** | 通过 |
| 监控关、弹窗全关 | 无自建周期监控回调 | 无 timer；CPU **0.021%** | 通过 |
| 监控开自建调度 | ≤ 0.4 次/秒 | 1 个 3 秒源 = **0.33 次/秒** | 通过 |
| 50 次开关，静置 60 s 后 Δfootprint | ≤ 10 MiB | **+2 MiB**（预热后第二轮） | 通过 |
| 月历静止 2 min 无持续布局/轮询/动画 | — | 未单独测量；`CalendarModel` 无定时器（仅通知观察者） | 未执行 |
| 连续切换 24 个月，查询范围有限、旧数据可回收 | — | 缓存仅当前范围 + generation 丢弃；未实机计时 | 未执行 |
| 反复登录项/监控切换、睡眠唤醒无重复采样 | — | `start()` 守卫 + 单测覆盖部分；未实机重复切换计时 | 未执行 |
| 原始查询离开主线程 | — | `sampleQueue`（utility）执行 Mach/libproc/容量读取 | 通过 |
| 图表仅随新快照重绘 | — | 无高频动画，仅 Observation 驱动 | 通过 |

唤醒说明：`ri_interrupt_wkups + ri_pkg_idle_wkups` 含系统框架与外部事件，不能等同于 App 自建定时器次数；监控关时的原始唤醒计数反而更高，属外部干扰（测量扰动已在 `METRICS.md` §7 注明）。App 自建调度在监控开时恒为 1 个 3 秒源，监控关时为 0。

## 6. UI 验收（ACCEPTANCE §7）

| 项 | 状态 | 说明 |
|---|---|---|
| 统一字体/层级/边距/圆角/语义色 | 通过 | 集中于 `UIStyle`；系统原生控件，不自绘 |
| 月历/监控同外壳，设置单页表单，右击原生菜单 | 通过 | 截图 `02`–`05` |
| 文字不裁切、正文可读、无重复投影/粗白框/多重玻璃 | 通过 | 浅/深色截图 |
| 100%/--% 不跳宽，长名称不破坏对齐 | 通过 | 状态栏固定列宽；列表名称截断不换行 |
| 今天/选中/休/班/加载/失败/禁用可区分 | 通过 | 截图 `03`（中秋+休）、`06`（全禁用） |
| 列表悬停/滚动/键盘不跳行、焦点保留 | 部分 | 排序冻结 + 稳定 ID；完整键盘操作未逐项实机验证 |
| 浅色/深色/减少透明度/增加对比度/倍率 | 部分 | 浅色/深色截图 `02`/`07`、`03`/`08`、`04`/`09`；减少透明度/增加对比度未执行 |
| 小屏幕边缘不越界、可滚动区域不吞操作 | 未执行 | 本机为 2x 大屏；未在小屏验证 |
| 同环境分别截图，数值真实 | 通过 | 全部来自本机实跑，未伪造图形 |

## 7. 截图清单（`screenshots/`）

本轮界面收敛后的当前组件小图（真实运行，窗口级抓取，无大面积其他应用背景）：

| 文件 | 内容 |
|---|---|
| `01-menubar.png` | 菜单栏：CPU/MEM 与日期两个独立项目 |
| `02-monitoring.png` | 监控面板：设备行 + 三概况卡 + 应用列表（无内存组成） |
| `03-calendar-today.png` | 月历今天：单行摘要 + 信息行相对日期，点不压字 |
| `04-calendar-detail.png` | 月历选中节气日（秋分）：单行摘要 + 信息行，无内置节日 |
| `05-settings.png` | 设置：周起始日右对齐横向单选、系统日历权限“获取权限”，无刷新说明/来源下拉 |
| `06-context-menu.png` | 右击菜单：偏好设置…/退出 |
| `07-material-monitoring.png` | 监控弹窗带真实背景（材质对照） |
| `08-material-calendar.png` | 月历弹窗带真实背景（材质对照） |

上一轮（含内存组成展示）的截图已移入 `screenshots/archive/`，仅作历史证据，不代表当前界面。

## 8. 未通过 / 未执行与复现步骤

**未通过**：无。

**未执行（含原因与复现步骤）**：

1. **EventKit 授权路径**（`AXIsProcessTrusted=false`，TCC 需交互授权，无法自动批准）。
   复现：运行 App → 设置 → “系统日历权限”点“获取权限” → 允许 → 观察自动识别的中国节日日历与读取。当前只能展示“获取权限”与内置节假日。
2. **真实休眠/唤醒**：需合盖或 `pmset sleepnow`，本次为不中断会话未执行。
   复现：`pmset sleepnow` 唤醒后观察监控 CPU 首样本为 `--%` 再到有效值、日期不跳错。
3. **真实时间跳变/时区切换/夏令时/跨午夜**：需改系统时钟/时区。
   复现：改时区或跨午夜后确认 `CalendarModel` 与菜单栏日期重算。
4. **减少透明度 / 增加对比度 / 小屏边缘**：辅助功能显示选项与小屏环境未在本机验证。
   复现：系统设置开启对应项，或换小分辨率/小屏查看布局与滚动。
5. **月历静止 2 min、连续切 24 个月、反复登录项/监控切换的实机计时**：未专门计时（相关实现无定时器/单范围缓存可自查）。
   复现：按 `ACCEPTANCE.md` §6.2 逐项计时。

## 9. 限制与覆盖边界

- 应用列表覆盖当前用户可识别的图形/配件应用及其可证明归属的 helper；系统守护进程（WindowServer、kernel_task 等）不可读且不属于产品范围，显示为不可读取而非 0。
- 32 GiB 机器上内存按二进制显示为 “32 GB”，磁盘按十进制显示为 “494.4 GB”，分别对齐活动监视器与 Finder（见 `METRICS.md` §6）。
- 原记录场景的内存“已用”与活动监视器显示值相差约 0.00717 pp；超出三项之和的部分单列“其他”，仅定义为未细分统计差额，具体成分未证明。异常样本不配平。
- EventKit 仅提供节日名称，班/休只来自官方静态数据。
- 验证钩子 `CALMON_CAPTURE` 仅用于无法合成点击的机器，正常使用不触发。

## 10. 针对独立验收（INDEPENDENT_REVIEW.md）的修复

第一轮与第二轮独立验收结论均为“未通过”。以下为两轮修复与验证（Release 构建通过，单测 58/58）：

| 编号 | 问题 | 修复 | 验证 |
|---|---|---|---|
| R1 | `proc_listallpids` 返回值被重复除以 4，漏读约 3/4 进程 | 返回值按 PID 数量解释；缓冲写满时翻倍重试 | 单测 `testAllPIDsMatchesEnumeratedCount`（实际枚举数与直接调用一致，>100 且无重复） |
| R2 | 监控开关不控制采样生命周期 | `syncMonitoringLifecycle()` 绑定开关到 `monitor.start()/stop()` | `CALMON_CAPTURE=monitoring-toggle` 实机输出 `start=true → after-off=false → after-on=true`；单测 `testStopClearsLiveMonitoringValues` |
| R3/F1 | 内存已用口径 | `used = physical − (free − speculative) − external`；未细分差额单列“其他” | 原始记录独立复算后偏差约 0.00717 pp；异常样本及缓存测试修复见 FIX_VALIDATION.md |
| F2 | 非法内存组合仍产生矛盾快照 | 任一分项 > 物理内存或分项和 > 物理内存 → 判为无效返回 `nil`，不截断保留冲突分项 | 单测 `testMemorySnapshotRejectsComponentSumOverPhysical`、`testMemorySnapshotRejectsComponentLargerThanPhysical` |
| F3 | 来源失效未废弃在途请求/通知界面 | `invalidateEvents()` 统一自增 generation、清空范围与事件、发布 revision；`refreshAvailableCalendars`/`restoreSource`/`requestAccess`/`reloadEvents` 均调用；`publishFetchedEvents` 发布前核对 generation、来源选择与授权 | 单测 `testReloadAndDisconnectInvalidateInFlightFetches`、`testFetchedEventsDiscardedWhenSourceChanged`、`testFetchedEventsDiscardedWhenUnauthorized` |
| F4 | 过期采样测试未真正触发应用采样 | `AppMemoryReading` 协议 + 可注入 reader + `GatedReader`，确定性控制采样完成点；丢弃过期结果时同时 `trimCache()` | 单测 `testStaleApplicationSampleAfterPanelCloseIsDiscarded`、`testPanelOpenQueuesImmediateSample` |
| R4 | 首次连接日历无可达授权入口 | 新增 `HolidayProvider.requestAccess()` 与“连接系统节日日历”按钮 | 代码路径；TCC 交互仍需人工授权（见 §8） |
| R5 | 保存的来源重启后未恢复给 Provider | `restoreSource(id:title:)`，`CalMonApp` 启动时恢复 | 代码路径；需授权后实机重启验证 |
| R6 | 过期任务回写 | `SystemMonitor.generation` 在启停/面板/唤醒时自增，结果发布前校验 | 同 F4 单测 |
| R7 | 设置变化累积重复观察链 | 拆分 `observePreferences/observeMonitor/observeCalendar`，各自只重注册自身 | 代码审查；单条链 |
| R8 | 无效 CPU/磁盘保留旧值 | CPU 无效即置 `nil`；磁盘区分“未安排”与“尝试失败”，失败清空 | 单测覆盖生命周期；`apply` 逻辑 |
| R9 | 设置未驱动日历刷新、农历详情无法关闭 | `CalendarModel` 观察日历相关偏好并重建；`showsLunarInDetail` 控制详情 | 单测 `testPreferenceChangeRebuildsWithoutManualCall`、`testLunarDetailFollowsPreference` |

另修复：EventKit 查询闭包不再跨并发边界捕获非 Sendable 的 `EKCalendar`（改为按标识符在队列内重取），消除 Release 编译警告。

单位与口径决策：整机内存用二进制（32 GiB 显示 32 GB），磁盘沿用十进制（494.4 GB）；内存“已用”对齐活动监视器 Memory Used，残差单列“其他”。已同步修订 `MONITORING.md` §3.1/§3.3/§6、`UI_SPEC.md` 组成图例、`METRICS.md`。

第 3 节 UI 细调清单（邻月角标、提示点间距、焦点框、设置窗口完整来源区、干净组件截图）留待功能复验后作为外观阶段处理。

## 11. 本轮界面调整与功能收敛（UI_REFINEMENT）

依据 `docs/UI_REFINEMENT.md`，Release 构建通过，单测 66/66。逐项：

| 项 | 结果 | 证据 |
|---|---|---|
| 菜单栏更紧凑、字号更小 | 通过 | 内边距 6→3、标签-数值 3；日期 14→12 regular、CPU/MEM 9→8.5 medium；`01-menubar.png` |
| 两弹窗统一材质/箭头、修焦点框 | 通过 | 两者均为同一原生 `NSPopover`（`.transient`，系统外壳、锚定实际按钮）；日历 ScrollView 加 `focusEffectDisabled()` 去掉蓝框，保留 Esc/方向键/T |
| 月历布局（图七） | 通过 | 行高 52→48、今天/选中圆 34 pt 含两行；提示点独立 6 pt 区不压字；邻月班/休角标显示并淡化；`03/04` |
| 假期名不冒充实际节日 | 通过 | `statutoryFestivalName` 仅在实际节日日返回名称；单测 `testGridFestivalNameOnlyOnActualFestivalDate`、`testMergedNationalDayMidAutumnSplitsByDate`；截图 9/25 只在该日 |
| 详情摘要+紧凑列表 | 通过 | 分隔线 + 左侧公历/ISO 周、右侧农历；相对日期行；事件行“全天+浅色块+绿竖线+休息/补班标签”；普通日不再写“当天无节日”；`03/04` |
| 完整移除内存组成 | 通过 | 删除组成卡/条/图例、颜色常量、公开字段与专属测试；MEM 公式与异常样本保护保留（`METRICS.md` §3、`testMemoryUsedMatchesActivityMonitorFormula` 等） |
| 应用按软件聚合 | 通过 | 顶层 `.app` 根路径聚合；`measurements/app-aggregation.txt`：飞书 12 进程 1615.7 MiB（主 Feishu + Lark Helper/Renderer + XPC）、Chrome 24 进程 2730.8 MiB、ChatGPT Classic 与其 ChatGPTHelper 合并、ChatGPT 独立不误合；单测 `testRootBundle…`、`testNestedHelperAttributesToMainApp`、`testIndependentAppsAreNotMerged` |
| 设置：删除刷新说明 | 通过 | 移除“CPU 与内存 · 每 3 秒刷新”行；`05-settings.png` |
| 设置：周起始日原生横向单选 | 通过 | `WeekStartRadio`（NSButton radio ×2）；截图显示“周一 周日” |
| 设置：系统日历权限行 | 通过（代码/UI）；实机授权未执行 | 状态机 notDetermined/requesting/authorized/denied/restricted；截图显示“获取权限”；不自动请求、已授权不重复请求 |
| 取消来源选择、改自动识别 | 通过（策略）；实机候选未执行 | 删除来源 Picker 与 Preferences 来源字段；`holidayCalendarCandidate` 要求“中国/china + 节假日/holiday”双关键字，记录候选；无匹配用内置并提示 |

未执行（需人工/签名/环境）：① 实机首次授权→允许→自动识别中国节日日历；② 拒绝/撤销后状态与恢复；③ 覆盖安装后的系统授权继承与签名身份（DMG、两个真实版本）；④ Mole/MacCalendar 同机并排比较；⑤ 深色/减少透明度/增加对比度/小屏；⑥ 真实睡眠唤醒、时区跳变。

权限自动识别可行性：公开 API 只能读到日历标题等元数据，无法仅凭元数据 100% 保证“中国节日日历”身份；本实现采取保守双关键字匹配并记录候选，未匹配时回退内置数据且不报授权失败。若系统无此类日历订阅，则始终使用内置节假日。该限制已如实记录，不夸大。

第 3 节剩余的纯视觉微调（与参考图的像素级对齐、壁纸/材质观感）待人工复验后再定。

## 12. 第二轮界面问题修复（UI_REVIEW_FOLLOWUP.md U1–U5 / A1–A7 / B1–B3）

依据 `docs/UI_REVIEW_FOLLOWUP.md`。Release 构建通过，单测 **62/62**（本卷第 11 节的 66 为上一版数字，以此节为准）。

| 项 | 结果 | 实现与证据 |
|---|---|---|
| U1/A7 菜单栏间隔 | 通过（App 可控部分清零） | 图像左右 padding 3→0；实测两按钮边界相接（1220..1292 / 1292..1388），残余 22–23 pt 来自系统 NSStatusBarButton 内边距，公开 API 不可控；`measurements/menubar-gap.txt` |
| U2/A3 移除内置节假日 | 通过 | 删除 `Holidays/CN-*.json` 资源与加载/回退/说明/测试；`resources` 仅剩 AppIcon/Assets/SolarTerms/PrivacyInfo；无系统来源时显示普通公历+农历+节气 |
| A1 日历 entitlement | 通过（配置） | `CalMon.entitlements` 增加 `com.apple.security.personal-information.calendars=true`；Release 实际签名 entitlement 已含该项，Hardened Runtime 保持开启 |
| A2 授权错误与状态机 | 通过 | `requestFullAccessToEvents` 捕获 error 并在设置显示；`writeOnly` 归为未授权；`accessState` 含 requesting/authorized/denied/restricted/notDetermined |
| B1 来源识别 | 通过（代码）；实机未验证 | `holidayCalendarCandidate` 用标题双标记或“只读/订阅+来源含中国”；`candidateDetails` 记录类型/只读/来源作证据 |
| B3 来源变化重发现 | 通过 | `EKEventStoreChanged` → `handleStoreChange` → 重新核验授权并 `autoDiscoverSource`，保留仍有效的当前来源 |
| U4/A5 单行摘要 + 信息行 | 通过 | `summaryDate="2026年09月25日（第39周）"`、`lunarSummary="丙午年（马）八月十五"`；相对日期与节日都用“全天+浅色块+绿竖线”信息行；单测 `testSingleLineSummaryFormat`、`testLunarSummaryFormat` |
| U3/A4 周起始右对齐 | 通过 | 用 `HStack{Spacer()+WeekStartRadio.fixedSize()}`；OCR 实测“周起始日”x0.069–0.193、“周一/周日”x0.669–0.926，右缘与控件列对齐 |
| U5/A6 材质统一 | 通过（代码）；实机对照待人工 | 两弹窗共用 `UIStyle.Colors.cardBackground`（quaternaryLabelColor 0.25）与同一原生 NSPopover；带真实背景对照图 `07/08` |
| B2 行身份/图标缓存 | 通过 | `AppUsage.id` 与图标缓存键改用规范化顶层 bundle 路径 `rootPath`；单测 `testIndependentAppsAreNotMerged`、`testRootBundleExtractsTopLevelApp` |

另：`holidayCalendarCandidate` 由标题规则收紧为双标记/只读交叉条件；`handleStoreChange` 不新增轮询。EventKit 查询闭包仍不跨并发边界捕获 `EKCalendar`。

**未执行（需人工/签名/环境）**：实机首次授权→允许→自动识别并读取；拒绝/撤销后状态与恢复；来源新增/删除后的实机发现；覆盖安装授权继承与稳定签名身份；深色/减少透明度/增加对比度/小屏；真实睡眠唤醒/时区跳变；Mole/MacCalendar 同机并排比较。DMG 未打。

**来源识别限制**：公开 API 仅元数据，无法 100% 保证日历身份；已用交叉条件收紧并在 `DATA.md` 记录，未匹配时回退普通日历，不伪装授权失败。
