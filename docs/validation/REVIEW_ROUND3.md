# 第三轮功能复验：F1–F4

日期：2026-09-15。结论：**主要修复已落地，单场景内存对照得到支持；异常样本处理和证据记录仍需收尾，暂不宣布整体验收通过。**

## 本次实际验证

- 检查 SystemMonitor、HolidayProvider、相关测试和新内存对照材料；实际查看英文活动监视器截图。
- 用独立算术复算提供的原始页计数，未启动 CalMon 或读取用户日历。
- 独立 Release 构建成功，退出码 0，无 Swift 编译警告；仅有 AppIntents 元数据提取跳过提示。
- 命令：`xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Release -derivedDataPath /private/tmp/CalMon-review3-20260915 build CODE_SIGN_IDENTITY=-`。
- 日志：`/private/tmp/CalMon-review3-build.log`。未自动安装、替换或启动 App，未改变登录项、授权及偏好。
- 58/58 为实施方报告，本次没有独立运行会启动 App 宿主的 XCTest。源码审查、算术复算和构建结果不代替真实交互验收。

## F1–F4 复核结果

| 项目 | 结果 |
|---|---|
| F1 | 英文截图确实显示 Memory Used 25.24 GB，App 16.31、Wired 3.08、Compressed 4.91、Cached 6.60。该时刻总值与分项的差额确实可见。原始计数复算后与 Memory Used 接近，支持此场景的准确性；不能据一帧宣称所有场景精确吻合。证据算术仍需更正，见 T2。 |
| F2 | 分项大于物理量、分项合计超过物理量的拒绝逻辑已增加；但其他矛盾样本仍被强制配平，未完全通过，见 T1。 |
| F3 | invalidateEvents 统一清空并递增版本；结果发布检查版本、所选来源和授权。上一轮所列主要代码路径已有修复。真实首次授权、撤销、删除和恢复仍待实机测试，不据此声明授权复用已通过。 |
| F4 | GatedReader 测试先等待初始采样结束，再确认真实应用采样进入后台后关闭面板，原测试没有触发应用采样的问题已修正。生产逻辑在丢弃旧应用结果时再次清缓存。缓存测试断言仍不够严格，见 T3。 |

## T1 · P2 · 内存矛盾样本仍会自动抬高 used

位置：[SystemMonitor.swift:357](/Users/wangqing/code/CalMon/CalMon/Monitoring/SystemMonitor.swift:357)、[MonitoringTests.swift:121](/Users/wangqing/code/CalMon/CalMonTests/MonitoringTests.swift:121)。

当前先截断 effectiveFree/fileBacked，再用 `max(measuredUsed, componentSum)` 提高已用量。因此业务 used 并非总是文档声称的测量公式结果；组成条能铺满不能证明原始统计有效。

现有测试 `testMemoryUsedClampsWhenFreeExceedsPhysical` 明确把 physical=1000、free=2000 的样本视为有效，并期望 used=550。还有分项本身没有超总量、但与公式冲突的情形：physical=1000、free=100、speculative=0、external=700、internal=300、purgeable=0、wired=100、compressor=100，公式 used=200，代码却返回 500。

要求：对无法解释的矛盾字段返回无效，不抬高 used 或截断字段来配平。测试覆盖 effectiveFree 超物理量、effectiveFree+external 超物理量、componentSum 超 measuredUsed 等关系；若某关系在有效系统统计中确实可能发生，先给出其语义和实测证据，再定义处理方式。保持正常样本测量公式与文档一致。

## T2 · P2 · 新证据存在页数减法错误，“其他”成分仍未经证明

位置：[memory-vs-activity-monitor.txt](/Users/wangqing/code/CalMon/docs/validation/measurements/memory-vs-activity-monitor.txt)。

按记录的 free_count=34593、speculative_count=3665 复算，差值为 **30928**，不是 30938。应由同一组原始计数生成所有派生值：

| 字段 | 独立复算结果 |
|---|---:|
| effectiveFree | 506724352 B |
| used | 27103707136 B = 25.2422943115 GiB |
| app | 17526030336 B |
| wired | 3303718912 B |
| compressed | 5274763264 B |
| other | 999194624 B |
| remaining | 7256031232 B |

修正后的 used 与截图 25.24 之差约 0.00717 个百分点（截图本身有舍入），仍小于 1 个百分点。这是证据一致性修正，不表示该场景准确性失败，也不能描述为逐字节“精确吻合”。

截图实际文件是 [activity-monitor-memory-en.png](/Users/wangqing/code/CalMon/docs/validation/measurements/activity-monitor-memory-en.png)。后续报告引用该实际路径。

“其他”目前只能证明是测量 used 减三个已列分项的统计差额；本证据没有证明它具体由 purgeable、speculative 和哪些内核页组成。UI 可按当前方案单列“其他”，说明应写“未细分的统计差额”，删除未经证明的确定性成分归因。同步修正 MONITORING.md、METRICS.md 及证据中的派生值。

## T3 · 测试补强 · 缓存断言不能区分关闭前清理与旧任务完成后清理

位置：[LifecycleTests.swift:150](/Users/wangqing/code/CalMon/CalMonTests/LifecycleTests.swift:150)。

`trimCount >= 1` 在调用 setPanelVisible(false) 时已经成立，即使删掉旧任务完成后的 trimCache，测试仍可能通过。生产代码已有第二次清理，本项是回归测试的证明范围不足。

在释放阻塞查询之前记录计数，完成后断言计数再次增加；更直接的方式是让测试替身模拟采样结束时写入缓存，并断言最终缓存为空。保持已经改好的真实采样门控，不退回固定 sleep。

## 下一步

1. 修复 T1，修正 T2 的计算和表述，补强 T3；不再更换正常样本统计目标。
2. 补充缓存增长/释放、压缩等场景对照，以及完整 PID 枚举版本的应用组准确性和 Release 性能证据，不能沿用少读进程版本的性能结论。
3. 签名与 DMG 方案可以开始做设计，实际签名身份、证书条件和双版本覆盖安装的授权继承必须验证。此前第二轮报告中的系统日历授权约束继续有效。
4. 手动安装和真实交互项目仍未执行；未通过这些项目之前，不标记最终交付完成。

本次仅新增本报告，未修改应用代码、实现测试或实施方证据。
