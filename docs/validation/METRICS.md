# METRICS — 监控字段、公式、归属与实测

本文件记录 CalMon 最终使用的每个字段、单位、换算与公式，进程归属规则，容量口径，与活动监视器的对照证据，以及 CalMon 自身的资源实测。原始对照数据见同目录 `measurements/`。

## 1. 采样与调度

- 唯一周期源：`SystemMonitor.start()` 里的一个 `Timer`，`timeInterval = 3`，`tolerance = 0.3`，加入 `RunLoop.main` `.common`。整机 CPU/内存、菜单栏、圆环、组成条、容量文字全部读取同一份 `snapshot`。
- 磁盘复用该源：面板可见时用单调时钟 `DispatchTime` 判断，每 30 秒才真正调用一次容量 API。
- 逐应用数据只在监控面板可见时读取；面板关闭即 `trimCache()` 并清空列表，没有独立定时器。
- 监控禁用时 `start()` 从不调用，不存在周期回调；休眠不保活，唤醒 `handleWake()` 重建 CPU 基线、丢弃积压周期。
- 采样在 `sampleQueue`（qos .utility）执行，结果回主执行器一次性发布。

## 2. CPU

- 来源：`host_statistics(HOST_CPU_LOAD_INFO)`，字段 `cpu_ticks.{user,system,idle,nice}`（`host_cpu_load_info_data_t`）。
- 公式：`usage = 100 × (总增量 − idle增量) / 总增量`，总增量含 user+system+idle+nice，全部逻辑核心归一化到 0–100%。
- 计数器按 32 位（`UInt32.max`）处理回绕；`delta = now>=prev ? now-prev : (mask-prev)+now+1`。
- 无效条件：无前一份基线（首次/重新开启/唤醒后）、总增量为 0、`host_statistics` 失败 → `usage = nil` → 显示 `--%`，不伪造 0%。
- 显示整数四舍五入，不叠加移动平均；不按固定墙钟伪造增量（用实际计数区间）。

对照证据（`measurements/cpu-60s-activity-monitor.txt`）：同一 60 秒稳定负载窗口，CalMon 公式 20 个 3 秒样本均值 **41.37%**，活动监视器底部 System+User 5 次采样均值 **40.19%**，偏差 **1.18 个百分点**（要求 ≤ 2 pp）。

## 3. 整机内存

- 来源：`host_statistics64(HOST_VM_INFO64)` + `host_page_size` + `sysctlbyname("hw.memsize")`。页大小动态读取，未硬编码；比例在原始字节上计算，未先转 GB。
- 公式（全部原始字节，零取整；页字段先乘 pageSize 转字节）：

```
effectiveFree = free_count - speculative_count
used          = physical - effectiveFree - external_page_count     (对齐活动监视器 Memory Used)
usedPercent   = used / physical × 100
```

- 语义：`used` 对齐活动监视器 Memory Used；文件缓存不计入；压缩按占用物理空间计；swap 不计入物理使用量；不使用“总内存 − 空闲页”或进程 RSS 合计替代。
- 已删除内存组成展示（应用/联动/压缩/其他/剩余）与其专属颜色、常量和公开字段；底层采样字段与合法性检查保留在采样模块内部。
- 无效快照：`host_statistics64` 失败、physical=0，或字段越界 / 分项和超过物理内存 / 分项合计超过公式 used（矛盾样本）→ `memory = nil` → 显示 `--%`，不截断字段、不抬高 used 配平。

对照证据（同一瞬间 `host_statistics64` 全字段与活动监视器内存标签页英文界面，原始记录见 `measurements/memory-vs-activity-monitor.txt`，同步截图 `measurements/activity-monitor-memory-en.png`）：

| 字段 | CalMon（GiB） | 活动监视器 | 差值 |
|---|---|---|---|
| Physical | 32.000 | 32.00 | 0.000 |
| **Memory Used** | **25.2421** | **25.24** | **+0.002（约 0.007 个百分点）** |

该记录复算后的 Memory Used 与截图显示值相差约 0.007 个百分点，小于 1 个百分点门槛。截图含舍入且系统刷新不同步，不声明逐字节吻合；单场景不代替缓存变化及压缩场景验收。


## 4. 应用内存

- 来源：`NSWorkspace.shared.runningApplications`（身份/图标）+ `proc_listallpids`/`proc_pidpath`（进程与路径）+ `proc_pid_rusage(RUSAGE_INFO_V4).ri_phys_footprint`（内存）。不使用 `ri_resident_size`、虚拟内存或地址空间。
- 进程枚举：`proc_listallpids` 的返回值是 **PID 数量**（libproc 内部已把字节数除以 `sizeof(int)`），不得再除以 `sizeof(pid_t)`；缓冲写满时翻倍重试。修正前把该数量误当字节再除以 4，本机约 994 个 PID 只保留 248 个。单测 `testAllPIDsMatchesEnumeratedCount` 直接对比枚举数量。
- 归属规则（按软件聚合）：
  - 行 = 正在运行的图形/配件应用，先归约到**顶层 `.app` bundle**（软件边界）：嵌套 helper 与主 App 共享根路径，合并为一行，使用主 App 的名称与图标。
  - 每个 PID 的可执行路径按 root bundle **最短前缀**匹配唯一软件；同一 PID 只计一次；主 App 优先于嵌套 helper，不再用“最深 bundle”产生多行。
  - 独立安装实例（如 ChatGPT 与 ChatGPT Classic）根路径不同，不按名称/签名合并；行 ID 与图标缓存键都用**规范化顶层 bundle 路径**（`rootPath`），保证同一软件不同安装实例可区分、同主 bundle helper 继续合并。
  - 行值 = 该软件归属进程组已读 footprint 合计；部分不可读标 `partial`；全不可读标 `unreadable` 且不设 0；无归属进程不猜测合并。
  - 覆盖边界：主 App 未枚举、或进程可执行文件不在任何 `.app` 内（系统守护/命令行工具）时不归属，不伪造为某软件。
- 图标只在身份出现时读取一次并降采样到 20pt 缓存，`purge()`/`trimCache()` 在关闭面板与停用监控时清空。

对照证据（`measurements/app-memory-vs-activity-monitor.txt`，同屏 OCR 配对 PID 与内存）：

| PID | 进程 | CalMon `ri_phys_footprint` | 活动监视器 | 结果 |
|---|---|---|---|---|
| 3214 | codex | 277.80 MiB | 277.8 MB | 一致 |
| 6682 | Otty | 308.14 MiB | 308.1 MB | 一致 |
| 2192 | — | 326.89 MiB | 326.9 MB | 一致 |
| 407 | WindowServer | `proc_pid_rusage` 失败 | 1.16 GB | 正确记“不可读取”，不伪造 |

覆盖边界：可读图形应用与可证明归属的 helper（含浏览器/Electron 多进程，如 Codex/ChatGPT/Lark/Chrome 各 helper 单独成行但按 bundle 归属）；系统守护进程（如 WindowServer、kernel_task）不在应用列表范围内，本就不应列入。

## 5. 启动磁盘容量

- 来源：对 `FileManager.default.homeDirectoryForCurrentUser` 的 `URLResourceValues` 读取 `volumeTotalCapacity`、`volumeAvailableCapacity`（原始字节）。
- 公式：`available = volumeAvailableCapacity`；`used = total − available`；`pct = used / total × 100`。异常（total=0、available>total、API 失败）→ `--`。
- 口径：APFS 容器；只读系统卷与数据卷同容器，不累加；仅用基础 available，不用 importantUsage/可回收空间；只读容量不遍历文件，不含外置/网络卷，不读 I/O 速率。
- 对照证据（`measurements/disk-vs-system.txt`）：CalMon total `494384795648` B 与 `diskutil` Container Total Space 完全一致；available 与 Container Free Space 差约 3 MB（时间差）；`df -H /` 同容器。

## 6. 单位与显示（MONITORING.md §6）

- 业务计算全用字节。
- 内存使用二进制单位（GiB/MiB 标签写作 GB/MB），与活动监视器一致：本机 32 GiB 显示 “32 GB”，应用 1.40 GiB 显示 “1.40 GB”。
- 磁盘使用十进制单位，与 Finder 一致：494,384,795,648 B 显示 “494.4 GB”。
- 应用：< 1 GB 显示整数 MB；≥ 1 GB 显示两位小数 GB；非零小于 1 MB 显示 `<1 MB`。
- 整机内存/磁盘容量：最多一位小数 GB，省略无意义 `.0`。
- CPU/MEM/磁盘百分比整数四舍五入；圆环、组成条、占用条长度用未取整值。
- 无效百分比 `--%`，无效容量 `--`。
- 组成项与总值各自独立取整，末位可能出现 ±0.1 GB 差异；条长按未取整字节比例绘制，因此组成条始终铺满。

## 7. CalMon 自身性能（Release，无调试器）

以下为实施方早期测量，不能作为本轮修复后已重新通过的资源结论；当前独立验证及范围见 FIX_VALIDATION.md。完整进程枚举后的 Release 性能需重新测量。

测量工具：自建 `foot`，通过 `proc_pid_rusage(RUSAGE_INFO_V4)` 读取 `ri_phys_footprint`（MiB）与 `ri_user_time + ri_system_time`（累计 CPU 秒）；`idlew` 用 `top` 观察。测量本身会带来少量扰动。原始日志见 `measurements/`。

| 场景 | 时长 | CPU 增量 | 平均进程 CPU | footprint | 预算 | 结果 |
|---|---|---|---|---|---|---|
| 监控开、弹窗全关（`idle-10min.txt`） | 600 s | 0.074 s | **0.012%** | 预热后稳定 67.8 MiB | ≤ 0.5% / ≤ 120 MiB | 通过 |
| 监控面板开、前八行（`panel-open-5min.txt`） | 300 s | 0.023 s | **0.008%** | 稳定 41.1 MiB | ≤ 2% / ≤ 220 MiB | 通过 |
| 监控关、弹窗全关（`monitoring-off-10min.txt`） | 600 s | 0.124 s | **0.021%** | 72 MiB | 无自建周期监控回调 | 通过（见下） |
| 50 次开关（预热后第二轮，`toggle-stress-warmed.txt`） | — | — | — | 76 → 79 MiB，**+2 MiB** | 静置 60 s 后 ≤ 10 MiB | 通过 |

- CPU 均以“累计 CPU 秒 / 墙钟秒 ÷ 1 核”折算到一个逻辑核心的 100% 口径。
- 唤醒：`foot` 的 `ri_interrupt_wkups + ri_pkg_idle_wkups` 不是 App 自建定时器次数。监控开时 App 自建调度为 1 个 3 秒源（≈0.33 次/秒）；监控关时 `start()` 从未调用，无任何 App 自建监控回调（代码可证）。原始计数包含系统框架与外部事件，故不同批次差异大，不作等价比较。
- 50 次开关：短预热（15 s）首轮 delta 曾为 14 MiB，但那是 AppKit/SwiftUI 冷启动预热（footprint 在前 2–4 分钟从 ~17 MiB 升到平台期）；预热到平台后再跑 50 次 delta 为 2 MiB，证明无持续线性增长。

## 8. 未证明 / 未执行的准确性项

- 真实休眠/唤醒后的 CPU 基线重建、时区/系统时钟跳变仅由单元测试覆盖（`testMonitorWakeResetsBaseline`、`testRelativeText` 等），未在实机触发休眠验证。
- 内存“释放后文件缓存”“发生压缩”场景未单独构造；本次为日常负载下的即时对照。
- EventKit 节日来源因无法交互授权 TCC，未验证授权后的系统事件读取。
