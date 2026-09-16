# CalMon 独立验收

日期：2026-09-15。结论：**未通过，先修功能与数据正确性，再进行外观细调。**

依据：AGENTS.md、SPEC.md、UI_SPEC.md、MONITORING.md、ACCEPTANCE.md，以及用户手动安装 DMG 的交付偏好。本次新增本报告，未修改应用代码或原实施报告。

## 1. 本次实际验证范围

- 检查应用源码、工程配置、测试源码、现有验收报告和测量记录；查看已提交的监控、月历、设置截图。
- 独立执行 Release 构建，成功，退出码 0。环境为 macOS 27.0 (26A428)、Xcode 27.0 (27A266a)、Swift 6.4、arm64。
- 构建命令：`xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Release -derivedDataPath /private/tmp/CalMon-independent-review-20260915 build CODE_SIGN_IDENTITY=-`。
- 首次沙箱内构建被 Swift 宏插件运行限制阻断；获准在沙箱外重试后成功，不将沙箱报错归为源码错误。
- 构建日志：`/private/tmp/CalMon-independent-review-build-unrestricted.log`。产物位于临时目录，未安装、替换或启动 CalMon，未改变设置、日历授权或登录项。
- 独立用 libproc 只读调用验证进程枚举返回值；未读取日历事件内容。
- 本次未运行 hosted XCTest：测试配置的 TEST_HOST 是 CalMon.app，执行会启动应用。原报告的“43 tests, 0 failures”属于实施方记录，不作为本次独立执行结果。
- 未重做长时间性能测量、真实鼠标/键盘交互、睡眠唤醒、首次授权及手动安装；下列静态结论与实测结论明确区分。

## 2. 必须修复的问题

P1：影响核心功能、准确性或资源控制。P2：生命周期、异常处理及界面行为缺陷。以下均未在本次修改。

### R1 · P1 · 进程枚举重复换算，遗漏约四分之三的条目

位置：[AppMemoryReader.swift:164](/Users/wangqing/code/CalMon/CalMon/Monitoring/AppMemoryReader.swift:164)。

`proc_listallpids` 返回 PID 数量，代码将结果命名为 bytes，随后再次除以 `MemoryLayout<pid_t>.size`。Apple 实现内部已做过字节数到数量的转换，见 [Apple libproc 源码](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.c)。

本机只读调用：返回 994，缓冲区非零条目 993，当前实现仅保留 248。非零数量与返回量的一项差异不影响重复除以 4 的结论。此结果是进程枚举诊断，不是 CalMon UI 实跑截图。

影响：遗漏应用或 helper、低估应用总内存、把缺失误标为“不可读取”，甚至将不完整总量标为正常。三个单 PID 的 footprint 对照不能证明应用组完整性。

修复验收：正确解释返回值；处理缓冲区不足；比较完整 PID 集合；对浏览器等多进程应用列出归属 PID、逐项值及合计，明确缺失/不可读状态。修复后重测面板性能，原来少读进程时的性能不能直接沿用。

### R2 · P1 · 监控设置没有连接采样生命周期

位置：[MenuBarController.swift:171](/Users/wangqing/code/CalMon/CalMon/App/MenuBarController.swift:171)、[MenuBarController.swift:428](/Users/wangqing/code/CalMon/CalMon/App/MenuBarController.swift:428)。

设置变化仅调用 `syncStatusItems()`；它只控制项目可见性和关闭面板。产品代码中 `monitor.start()` 仅在启动时调用，没有调用 `monitor.stop()` 的路径。

影响：启动时监控开启，随后关闭开关，仍保持 3 秒采样；启动时监控关闭，随后打开开关，采样不会开始。现有测试直接调用 SystemMonitor.start/stop，未覆盖设置到控制器的实际链路。

修复验收：从设置操作覆盖开→关→开，以及以关闭状态启动后再开启；检查实际查询次数、单一定时器、重新开启 CPU 基线和全关管理入口。

### R3 · P1 · 内存总值与组成项不一致

位置：[SystemMonitor.swift:307](/Users/wangqing/code/CalMon/CalMon/Monitoring/SystemMonitor.swift:307)、[MonitoringView.swift:123](/Users/wangqing/code/CalMon/CalMon/Monitoring/MonitoringView.swift:123)。

已用量与应用/联动/压缩项由不同公式产生，没有满足规范要求的分项一致性。现有测试的默认样本给出 used=700、app=350、wired=100、compressed=100，三项合计仅 550，测试没有检查此约束。

已有真实截图 `screenshots/02-monitoring.png` 同时显示已用 26 GB，分项为 14.9+3.8+5.9=24.6 GB；加剩余 8.4 后合计 33 GB，而总量为 34.4 GB。差额明显超过显示舍入范围，组成条末端出现未说明的空段。

修复验收：调查并证明字段语义，不把残差硬塞进某一项；覆盖应用增长、释放/缓存、压缩等状态的原始字节和活动监视器对照。当前一组接近的 Memory Used 对照不足以证明公式普遍正确。

### R4 · P1 · 首次连接日历缺少可到达的授权入口

位置：[SettingsView.swift:82](/Users/wangqing/code/CalMon/CalMon/Settings/SettingsView.swift:82)、[HolidayProvider.swift:156](/Users/wangqing/code/CalMon/CalMon/Calendar/HolidayProvider.swift:156)。

唯一授权调用在 `connect(calendarID:title:)` 中；唯一 UI 调用路径要求先从 `availableCalendars` 选中一个日历。首次无授权时，界面先枚举日历，只有“刷新来源”，没有先请求访问的连接动作。未拿到可选日历时无法到达授权代码。这是调用链审查结论，尚未在干净 TCC 环境点击复现。

修复验收：明确“连接系统节日日历”操作，用户触发后授权，再刷新可选来源；拒绝/撤销/未配置日历分别显示状态。按 [Apple EventKit 访问说明](https://developer.apple.com/documentation/eventkit/accessing-the-event-store) 验证完整路径，不把辅助功能权限 AXIsProcessTrusted 与日历授权混为一谈。

### R5 · P2 · 已保存的节日来源重启后没有恢复给 Provider

位置：[CalMonApp.swift:28](/Users/wangqing/code/CalMon/CalMon/App/CalMonApp.swift:28)、[Preferences.swift:73](/Users/wangqing/code/CalMon/CalMon/App/Preferences.swift:73)。

Preferences 读取保存的来源 ID/title，但新建 HolidayProvider 后没有恢复连接；Provider 的 selectedCalendarID 仍为 nil。Picker 读取 Preferences，实际查询读取 Provider，二者会不一致。

修复验收：已授权并选择来源后退出/重启，无需重新选择即可读取；同时覆盖来源删除、权限撤销和主动断开，启动时不要无条件弹授权。

### R6 · P2 · 已过期的监控任务仍会发布结果

位置：[SystemMonitor.swift:166](/Users/wangqing/code/CalMon/CalMon/Monitoring/SystemMonitor.swift:166)。

采样捕获旧 wantApps 和 priorTicks；完成后 apply 没有检查运行状态、面板可见性或任务版本。采样中关闭面板、停止、重新开启或唤醒，旧任务仍能写回应用列表、磁盘及 CPU 基线。

修复验收：人为延迟查询，覆盖关闭面板、停用、快速重启、唤醒；旧结果不能恢复已清空列表或污染新 CPU 时间窗，也不能在关闭后重新填充缓存。

### R7 · P2 · 修改设置会增加持续的观察链

位置：[MenuBarController.swift:428](/Users/wangqing/code/CalMon/CalMon/App/MenuBarController.swift:428)。

每次偏好变化重新调用 observeEverything，同时新增 observeMonitor/observeCalendar；原有监控/日历观察在各自回调里继续注册，没有结束。反复切换设置后，一次快照更新会触发更多 Task 和重复观察注册。

修复验收：每类观察只保留一条有效链；设置切换 50 次后测一次更新的回调数量，验证不会随切换次数增长。单看“只有一个 Timer”无法覆盖此问题。

### R8 · P2 · 无效 CPU / 磁盘样本可能继续显示旧值

位置：[SystemMonitor.swift:177](/Users/wangqing/code/CalMon/CalMon/Monitoring/SystemMonitor.swift:177)、[SystemMonitor.swift:194](/Users/wangqing/code/CalMon/CalMon/Monitoring/SystemMonitor.swift:194)。

cpuUsage 返回 nil 时没有清空先前 usage；磁盘失败返回 nil 与本轮未安排读取共用一种表示，apply 仅在非 nil 时更新磁盘。timestamp 仍会更新，导致旧数值看起来是有效实时数据。

修复验收：先成功再注入 CPU 零增量/基线无效、磁盘读取失败，显示 --；区分未安排查询与已查询失败，恢复后重新显示有效数据。

### R9 · P2 · 日历设置未完整驱动界面更新，农历详情无法关闭

位置：[CalendarModel.swift:348](/Users/wangqing/code/CalMon/CalMon/Calendar/CalendarModel.swift:348)、[CalendarView.swift:205](/Users/wangqing/code/CalMon/CalMon/Calendar/CalendarView.swift:205)。

CalendarModel 预先存储菜单栏文字、日期格和详情，却只观察 Provider revision，没有观察影响这些结果的偏好。显示星期变化只重绘旧 menuBarText，需下一次 rebuild 才会反映；其他日历偏好同样依赖之后的日期操作。详情还无条件显示 `detail.lunar.display`，即使重开月历，关闭农历后详情仍显示农历。

修复验收：星期开关立即更新菜单栏；农历、节假日、周起始设置同步更新网格和详情；关闭农历不影响班/休，且详情农历确实隐藏。

## 3. 下一轮 UI 细调清单

以下来自现有截图与对应布局源码，不代表本次实机交互已经通过。

- 月历绿色提示点压在第二行文字上；`CalendarView.dayCell` 的格底 overlay 与文字缺少独立空间，应满足至少 2 pt 分隔。
- 邻月格子的班/休被 `day.isCurrentMonth` 条件隐藏，9 月视图中的 10 月休假日没有角标。应显示已知标记并随邻月淡化。
- 月历整体 ScrollView 出现显眼的焦点框；需要检查真实键盘焦点状态并调整焦点呈现，不直接取消可访问性。
- 设置窗口高度固定 560 pt，已交截图没有完整展示节日来源；补充完整来源区域与授权/失败状态截图后再确认密度和滚动体验。
- 现有截图含大面积其他应用背景，不符合约定的组件小图交付。后续分别提交菜单栏、两个弹窗、设置、右击菜单的干净实机截图。
- 监控与月历有集中式 UIStyle、原生 NSPopover，基础方向符合约定；不据此提前判定所有字体、材质、对比度和小屏适配通过。

## 4. 尚未通过的证据与交付项目

- 原 REPORT.md 的“未通过：无”不能沿用；尤其监控开关、分项一致性、失败清空、应用完整性与当前源码相矛盾。
- 原应用准确性证据仅列三个 PID，不含完整应用组核对；原性能证据需要在进程枚举和生命周期修复后重新测量。
- 真实左右击、Esc/外部关闭、键盘与辅助功能、首次日历授权、来源删除、睡眠唤醒、跨日/时区、显示辅助选项、小屏以及登录项状态，仍需按 ACCEPTANCE.md 补验。
- 本次未独立逐条重新核验官方年度节假日和节气数据；原 DATA.md 的声明保留为实施方证据，不另行升级为本次通过。
- Release 构建存在 EKCalendar 非 Sendable 跨并发闭包捕获警告，位置 HolidayProvider.swift:266；工程仍为 Swift 5 语言模式、minimal 严格并发。应处理实际警告并明确并发边界，不仅以编译器版本新来证明采用了现代并发写法。
- 工作区未发现 DMG。现有交付是 .app；用户要求的手动 DMG 安装、退出旧版后替换、手动启动流程尚未验收。后续交付只产出安装包，不自动复制到 Applications、不自动替换或启动。

## 5. 修复与复验顺序

1. 修复 R1–R4，解决进程完整性、开关生命周期、内存一致性与授权入口。
2. 修复 R5–R9，补有意义的异步生命周期、设置集成及失败恢复测试。
3. 补齐活动监视器对照和 Release 资源实测，明确实际完整采样的成本。
4. 按第 3 节调整视觉细节并提交组件截图。
5. 交付 DMG，由用户手动安装；再核验实际点击、授权、登录项、升级替换及最终使用体验。

以上问题修复且必需项补验后，再出最终验收结论。
