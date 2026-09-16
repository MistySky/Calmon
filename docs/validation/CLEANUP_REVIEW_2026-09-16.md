# 清理改动独立复核（2026-09-16）

## 结论

本轮代码清理、独立测试、Release 构建及交付包一致性核验通过，未发现由清理引入的功能回退。性能记录支持低占用的观察结果，但部分时长、根因和准确性结论的证据尚不充分，需要修正文档，不能全部照原报告判为已验证。

本轮未修改应用代码、未安装/运行交付包、未更改用户设置、未提交或推送。未重复完整的 10/5/10 分钟性能实验；性能部分为原始记录复核。此前用户认可的四项行为不重新列为问题。

## 独立执行结果

- 当前源码 XCTest：64 项，0 failures。包含一分钟真实内存采样；不等于重新与活动监视器对照。
- 独立 Release 构建成功，无 Swift 编译警告；有 AppIntents 元数据提取跳过提示。
- `git diff --check` 通过。
- 删除的 UI 常量、Snapshot.isValid、CalendarModel.revision 和 VMRaw.active/inactive 与差异说明一致。CPU/内存公式未变化，测试改动仅删除相应 fixture 字段，未删测试用例或断言。
- 压力测试、监控开关诊断、模拟失活、日历转储、状态及 EVENT 日志均受 DEBUG 条件保护。独立 Release 和 DMG 内二进制均未检出 `CALMON_DUMP|CALMON_STATE|STRESS|MONTOGGLE|OUTSIDE|EVENT monitor`。
- 最小 UI 捕获功能仍保留，包括 CALMON_CAPTURE 与 CALMON_SELECT_DATE；此项与 BUILD.md 的设计说明一致。
- DMG 只读挂载时完整性校验通过；包内 App 与 `build/Build/Products/Release/CalMon.app` 经 `diff -qr` 无差异。包内 App 的 `codesign --verify --deep --strict` 通过，含日历访问 entitlement，资源中无旧 CN 节假日 JSON。检查后已卸载本轮挂载卷。
- 包内与现有 Release 可执行文件 SHA-256 均为 `30555237f9c770de55a0e2571cd3faf42bf5230135c6de09246bdcdc7d23170b`。独立重建用于源码验证，不声称重建二进制与既有包逐字节一致。

日志：`/private/tmp/CalMon-cleanup-tests.log`、`/private/tmp/CalMon-cleanup-release.log`。独立构建目录分别为 `/private/tmp/CalMon-cleanup-review` 与 `/private/tmp/CalMon-cleanup-release`。

## 需要修正的报告内容

### 1. “监控关 10 分钟”仅有 8 分钟记录

`measurements/audit-2026-09-16/after-cleanup-off-10min.txt` 虽声明 duration=600，但最后一条是 SAMPLE 480，缺 510/540/570/600 和完成 WALL 行。现有证据可确认前 480 秒末尾稳定在 17.27 MiB，不能证明完整 600 秒测量已完成。补齐原始记录或将报告时长改为已记录的 8 分钟。

### 2. “已定位为外部交互，非应用自身泄漏”证据不足

Debug 空闲复测事件计数为 0，以及新 Release 复测稳定，支持“复测未复现异常增长”。它们未记录此前突增时刻的打开事件，不能证明原异常必然由外部交互造成，也不能据此全面排除泄漏。应改为“本次复测稳定；先前突增根因仍未直接证实”。这不是发现了新泄漏。

### 3. 性能数值需标明统计口径与构建类型

- 空闲文件覆盖 600 秒，footprint 16.77→17.39 MiB；展开文件覆盖 300 秒，40.66→60.41 MiB，均支持报告的末值和已记录期间的低占用。
- 原始文件的数值列没有单位表头或测量程序，CPU 0.0033%/0.034% 的累计量、时间窗与计算步骤不可完全追溯。若中间列是累计 CPU 秒，应使用窗口增量；若是其他单位，需附定义。唤醒也需标明具体计数器，不能与 App 自建定时器回调混用。
- 50 次循环来自 Debug，日志已明确，不算 Release 性能实测。日志以整数 MiB 输出 before/after/delta，57→57 与 delta=0 只能说明该精度未观察到增长，不能解释为逐字节零增长。

### 4. 准确性复测引用没有完整对应

AUDIT §4 的 24.707 GiB vs 24.73 GB / 0.07pp 引用 `memory-vs-activity-monitor.txt`，实际该文件仍为旧的 25.242294 GiB vs 25.24 GB 样本。新 VM 快照存在，但缺匹配的本次活动监视器读数证据。不能将旧截图作为新对照证明。

CPU 原始记录包含 CalMon 20 个采样与 top 18 个采样，报告披露了样本数差异；0.42pp 可作为这两组均值的差，不能认定两者是完全对齐的相同窗口，且参考为 top，不是活动监视器。本轮清理没有改公式，不要求因上述证据问题调整算法。

### 5. BUILD.md 仍有两处旧内容

- §2 仍写 entitlement “只声明 app-sandbox=false”，实际包含 calendars=true。
- §6 仍写打包含 CN-2024/2025/2026.json，实际包内仅有节气年度 JSON，没有旧节假日资源。

补充术语纠正：删除 active/inactive 字段减少的是已有 `host_statistics64` 返回值的转换/保存，不是减少独立 sysctl 调用；底层整份 VM 统计仍会读取。不要据此宣称少了两次系统查询。

以上为证据与文档修正项，不应扩大成新的功能重构。本次通过范围为清理改动及产物检查，不替代尚未执行的真实交互或完整性能验收。
