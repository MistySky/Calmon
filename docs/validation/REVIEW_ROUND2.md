# 第二轮功能复验

日期：2026-09-15。结论：**多数修复已落地，仍不能判定功能全部通过。内存准确性是首要阻塞项。**

## 本次验证

- 阅读修订后的应用代码、测试及监控说明，对照第一轮 R1–R9。
- 独立 Release 构建成功，退出码 0，无 Swift 编译警告；存在一条 AppIntents 元数据提取跳过提示，非 Swift 警告。
- 命令：`xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Release -derivedDataPath /private/tmp/CalMon-review2-20260915 build CODE_SIGN_IDENTITY=-`。
- 日志：`/private/tmp/CalMon-review2-build.log`。
- 未安装或启动应用，未改变用户偏好、登录项、日历授权；未执行会启动 CalMon 测试宿主的 XCTest。48/48 是实施方报告，本次仅审查其测试源码，未独立重跑。
- 本次只新增复验文档，不修改应用代码或实施方报告。

## 原问题的复核状态

“代码修复确认”只表示原缺陷对应路径已修正，不等于实机行为和性能全部验收。

| 编号 | 复核结果 |
|---|---|
| R1 | 重复除以 4 已删除，已有缓冲扩容；代码修复确认。仍需完整应用组 PID/内存对照和修复后的性能测量。 |
| R2 | 偏好观察已调用 syncMonitoringLifecycle，连接 start/stop；代码修复确认。 |
| R3 | 普通样本的组成一致性改善，但重新定义 used 后不满足原 Memory Used 准确性要求，未通过。 |
| R4 | 已有独立 requestAccess 和连接按钮；入口代码修复确认，真实首次授权/拒绝待验。 |
| R5 | 已授权的保存来源在模型创建前恢复；代码修复确认，权限变化和来源删除尚有问题，见下。 |
| R6 | 结果发布已校验 generation/isRunning；主状态过期回写路径已修正，但新增测试没有覆盖所声称的应用采样竞态，缓存回填也尚未阻断。 |
| R7 | 三类观察分别注册、分别续订；代码修复确认。 |
| R8 | CPU nil 清空、磁盘 diskAttempted 区分已落实；代码修复确认，缺少先成功后失败的直接回归测试。 |
| R9 | CalendarModel 观察偏好并重建，详情受 showsLunarInDetail 控制；代码修复确认。 |

## 仍需处理的问题

### F1 · P1 · 单位修改正确，但内存统计目标被改了

位置：[SystemMonitor.swift:321](/Users/wangqing/code/CalMon/CalMon/Monitoring/SystemMonitor.swift:321)、[METRICS.md:39](/Users/wangqing/code/CalMon/docs/validation/METRICS.md:39)。

内存显示从十进制 34.4 GB 改成二进制 32 GB，磁盘保留十进制，符合当前确认的单位方案。这与 used 的计算是两个独立问题。

新 METRICS 表给出 CalMon used=24.20 GiB，活动监视器 Memory Used=25.54 GiB。两者差 1.34 GiB；在 32 GiB 上为 **4.1875 个百分点**，超过原 ACCEPTANCE.md 的 1 个百分点门槛。文档把比较对象改成“活动监视器三项之和”，不能据此宣称完成了与 Memory Used 对齐的需求。

“差额来自 purgeable 和未列出内核页”尚无足够证据。Apple 的[内存说明](https://support.apple.com/guide/activity-monitor/view-memory-usage-actmntr1004/mac)描述了 Memory Used 的分项和 Cached Files，但没有提供支持此特定差额解释的内核字段公式。需核查实际字段、页面/列名、单位、采样时刻及原始记录，不能以推测写成确定事实。

新 METRICS 引用的 `measurements/memory-vs-activity-monitor.txt` 仍是旧公式、旧数据（15.95/3.12/4.30 等），不能复现新表的 16.79/3.03/4.38。应补交新原始证据及同步截图，并按 Memory Used/Physical Memory 比较；缓存变化和压缩场景仍须覆盖。暂不要求回退旧公式，也不指定未经验证的新公式。

### F2 · P2 · 非法内存组合仍会产生自相矛盾的有效快照

位置：[SystemMonitor.swift:323](/Users/wangqing/code/CalMon/CalMon/Monitoring/SystemMonitor.swift:323)。

各分项分别 clamp 到 physical，而 used 再对分项合计 clamp。例如 physical=1000、internal=900、purgeable=0、wired=100、compressor=100，输出三项合计 1100、used=1000、remaining=0。四段仍超过总量。

`testComponentsAlwaysSumToTotal` 未包含这种组合，“始终铺满且相等”未成立。修复应验证样本合法性并将不合理组合标记无效，不截断总值后保留冲突分项。添加覆盖分项合计超出物理内存的测试。

### F3 · P2 · 日历来源失效时没有完整废弃在途请求和通知界面

位置：[HolidayProvider.swift:156](/Users/wangqing/code/CalMon/CalMon/Calendar/HolidayProvider.swift:156)、[HolidayProvider.swift:263](/Users/wangqing/code/CalMon/CalMon/Calendar/HolidayProvider.swift:263)。

`refreshAvailableCalendars` 在拒绝权限时只改变 sourceStatus，没有清空已有事件/范围、增加 generation 或 revision。来源不存在时虽清空事件，却同样没有使在途任务失效或通过 revision 重建 CalendarModel 的已存详情。

`reloadEvents` 也未在入口递增 generation；当随后 loadEvents 因来源不存在提前返回，旧请求仍可通过版本检查，回填旧事件并把状态重新写成 connected。

修复：权限撤销/来源删除时统一使请求失效、清空范围和事件、发布 revision；成功结果发布前核对当前授权与来源。用可控延迟请求测试“先查询、再删除/撤销、最后旧查询返回”，再补实机 TCC 流程。不能把静态可见的失效处理遗漏归为纯人工测试事项。

### F4 · P2 · R6 新测试未真正触发面板应用采样的过期完成

位置：[LifecycleTests.swift:134](/Users/wangqing/code/CalMon/CalMonTests/LifecycleTests.swift:134)。

测试调用 start()，它立即启动 wantApps=false 的采样并设置 isSampling=true；接着 setPanelVisible(true) 的 tick 被 isSampling 守卫跳过，随后立即关面板。因而本轮没有开始 wantApps=true 的查询，等待后列表为空不能证明应用采样旧结果已被丢弃。原本存在回写缺陷的版本也可能通过此测试。

应使用可控的采样完成点，确认一轮应用查询已进入后台后再关面板/停用，然后释放查询并断言结果。不要依靠固定睡眠时间保证竞态发生。

另有缓存边界：关闭时 reader.trimCache()/purge() 在主线程清空缓存，但旧后台 reader.sample 仍可能在之后执行 icon(for:) 重新填充。主状态 generation 校验不覆盖这一写入；应同样验证缓存和资源释放，不仅断言 applications 为空。

## 用户确认：系统日历授权与覆盖安装要求

本节是用户确认的产品约束，纳入本轮修复和交付验收；目前尚未完成实机验证。

### 授权流程

- 首次连接时，用户点击“连接系统日历”，通过 EventKit 请求 macOS 系统日历访问权限。授权入口不依赖已经枚举到日历来源。
- 系统授权仍有效时持续复用：以后启动、打开月历、切月、开关日历模块及覆盖安装新版，不重复发起授权请求。
- 每次启动及需要访问时检查系统实际授权状态；检查权限不等于请求权限。不得用 UserDefaults 中的“已授权”布尔值替代系统判断。
- 只有状态尚未决定且用户主动连接时，才发起系统授权请求；拒绝、撤销或系统限制时显示准确状态，提供适用的系统设置入口，不循环请求。
- “只获取一次”指已有有效授权持续复用；用户主动撤销、重置系统隐私权限等情况按实际系统状态处理，不承诺永久授权。
- 系统访问权限与节日日历来源选择分开处理：授权后选择需要读取的节日日历并记住；不因重新选来源而重新申请已有权限，不读取未选中日历的事件、不修改事件。
- 关闭日历功能保留已选来源和设置，不主动重置系统授权；再次开启时，已有权限和来源均有效即可恢复读取。

### 安装与应用身份

- 用户通过 DMG 手动安装、覆盖升级和启动；构建/打包过程不自动安装、替换或启动应用。
- 不把每次打包或覆盖安装当成首次使用。不同版本保持固定 Bundle ID，并采用稳定、可验证的代码签名身份及签名要求；不得通过每版更换应用身份来触发新授权。
- 当前 ad-hoc 构建不能仅凭 Bundle ID 相同就宣称授权一定继承。实施方需明确实际交付签名方案，并用两个真实版本验证系统对应用身份的识别及授权复用。
- 如签名或交付条件无法满足正常覆盖升级后的授权复用，明确报告缺口，不通过清除 TCC、重置隐私权限或要求用户每次重新授权来掩盖问题。

### 新增必验项（均未执行）

1. 首次手动安装 → 主动连接 → 系统请求授权 → 允许 → 选择节日日历 → 正常读取。
2. 退出/重启、反复打开月历、切月及日历开关后，不再弹授权，保留来源选择。
3. 退出旧版 → 从新版 DMG 手动覆盖同一安装位置 → 手动启动：沿用有效系统授权和已选来源，不重复请求。
4. 拒绝或在系统设置撤销权限后，不反复弹窗；旧查询失效、旧事件清空，状态和设置入口正确。用户在系统设置恢复权限后能够恢复连接。
5. 删除所选日历只使来源失效，不错误地重新申请系统访问权限；已授权情况下可重新选择有效来源。

记录两个版本的 Bundle ID、版本号、签名身份/签名要求及实测结果。本节约束不能仅凭代码存在授权 API 判定通过。

## 后续顺序

1. 先解决 F1：明确并证明 Memory Used 字段映射，更新可复现的原始对照材料。单位显示保持已确认方案。
2. 修复 F2/F3，补足 F4 所述有意义的异步测试；更新 REPORT.md 中与新代码/证据冲突的旧通过项。
3. 在完整进程枚举版本上重测应用组准确性与 Release 性能。旧版本遗漏大量进程时的性能数据不能代表修复后的成本。
4. 按本报告新增的系统日历授权与覆盖安装要求，落实应用身份、授权复用和来源恢复，并补齐对应实测。
5. 再进入外观细调，并通过手动安装流程完成真实交互、登录项、睡眠/时区等验收。
