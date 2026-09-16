# 第六轮独立验收（2026-09-16）

## 结论

**已完成项目通过，整体验收仍有未验证项。** 当前源码的 64/64 测试通过，独立 Release 构建成功。经用户逐项确认，R6-1 至 R6-4 均不作为本轮待修复问题；不得再据此要求修改应用。关键监控交互等独立验证范围见下文，未验证不等于功能有缺陷。本轮只检查、运行测试、构建临时产物和写报告，没有修改应用代码、安装或替换 App、重置日历授权或修改登录项。

## 1. 本轮实际执行

- 当前 XCTest：Calendar 27、Lifecycle 10、Monitoring 27，总计 64，0 failures，退出码 0。包含 60 秒、21 次真实内存读取；该测试校验有效性和公式内部一致性，不等于与活动监视器同步对照通过。
- 独立 Release 构建：退出码 0，无 Swift 编译警告；有 AppIntents 元数据提取跳过提示。
- 新 Release 的签名 entitlement 包含 calendars=true，资源清单核验不含旧节假日 CN 年度资源。
- `hdiutil verify dist/CalMon-1.0.dmg`：校验和 VALID，仅证明镜像完整，不等于安装、授权继承或包内版本一致性全部通过。
- 启动检查前未检测到 CalMon 正常实例；通过完整路径启动现有 `build/Build/Products/Release/CalMon.app`。工具重试读到设置为日历已授权、周一起始。工具关闭设置操作没有得到预期界面变化，无法继续可靠操作菜单栏；没有以该工具异常认定软件关闭按钮有缺陷。
- 查看上一轮提交的 `07-material-monitoring.png`、`08-material-calendar.png`、`04-calendar-detail.png`。前两张显示浅色原生外壳观感已接近，不能从平均亮度或静态截图推导首次真实点击交互通过。

首次受限沙箱运行出现 Swift 宏插件异常，退出 133；随后使用隔离测试宿主配置重跑成功，环境失败不记为产品编译缺陷。测试宿主 `CALMON_TEST_HOST=1` 在初始化用户设置与菜单栏前返回。

### 可复现命令与日志

```sh
xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Debug -derivedDataPath /private/tmp/CalMon-independent-round6 -destination 'platform=macOS' test
xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Release -derivedDataPath /private/tmp/CalMon-independent-round6-release build
hdiutil verify dist/CalMon-1.0.dmg
```

- 成功测试日志：`/private/tmp/CalMon-round6-tests-retry.log`
- 构建日志：`/private/tmp/CalMon-round6-release.log`
- 测试结果：`/private/tmp/CalMon-independent-round6/Logs/Test/Test-CalMon-2026.09.16_10-00-32-+0800.xcresult`

## 2. 用户确认后的问题处置

以下保留代码检查依据与最终处置。四项均已移出本轮待修复清单；其中边界场景未实机复现，不列为当前已发生的故障。用户最新确认优先于旧规格中相应的强制验收要求。

### R6-1 · 已撤销 · 节日事件与休息事件分别展示正常

位置：`CalMon/Calendar/HolidayProvider.swift:495`，`CalMon/Calendar/CalendarModel.swift:251`。

用户已结合实际截图确认：“中秋节”是节日事件，“中秋节（休）”是休息事件，两条分别展示没有问题。此前将其列为重复展示缺陷的判定撤销，不计入待修复项。

验收要求：保留两类事件及其各自含义，不合并或删除；休息事件可保留“休息”标签。后续休假日无普通节日事件时仍显示休息事件。相关规格已同步修正，其他问题与未验证项不受影响。

### R6-2 · 本轮不要求修复 · 系统时区变化

位置：`CalendarModel.swift:352`；`HolidayProvider.swift` 的 `private let calendar`、`loadEvents` 和 `dayKey` 查询。

CalendarModel 会将自身 calendar 更新为 `.current`；HolidayProvider 保存初始化时的 Calendar，之后不更新。切换时区后，网格日期与节日/节气查询使用不同的日键转换：例如从上海切到东京，新时区零点对应旧时区前一天 23:00，可能查到前一天的数据。旧 loadedRange 缓存也没有随时区变化统一失效。

最终处置：用户明确不会切换时区，此场景不作为本轮问题或交付阻塞项，不要求为此修改代码。上述为代码边界分析，不代表已在用户环境发生错日。

### R6-3 · 本轮不要求修复 · 月历持续打开跨月午夜

位置：`CalendarModel.swift:343`。

在今天仍被选中时，`handleDayChange` 更新 today 和 selectedDate，却不更新 visibleMonth。例如 9 月 30 日保持月历打开跨入 10 月 1 日，详情跟随到 10 月，标题/主体仍停在 9 月；在新一天不属于旧网格时还会丢失可见选中格。

最终处置：关闭后重新打开会通过 resetToToday 定位正确月份和今天，用户认可此使用方式。持续打开跨月午夜的边界场景不作为本轮问题或交付阻塞项，不要求为此修改代码。

### R6-4 · 用户实测正常 · 弹窗跨屏高度

位置：`MenuBarController.swift:371–386`。

两个 hosting controller 的 maxHeight 都在首次创建时按 `NSScreen.main` 计算并永久缓存。此实现曾被列为跨屏高度风险，但未独立复现裁切或越界；不能仅凭该实现判定实际功能故障。

最终处置：用户实际点击检查后反馈当前没有问题，按用户当前环境实测正常记录，移出待修复清单，不要求修改。此结论不扩展为所有屏幕组合均经自动化验证。

## 3. 已有修复的复核结果

| 项目 | 本轮判定 |
| --- | --- |
| 监控/日历统一 present，监控 focusable 与 Esc 回调 | 实现已确认；真实输入仍未验证 |
| 失活后关闭 | 旧日志显示 NSApp.deactivate 模拟检查通过；本轮未独立复现外部真实点击 |
| 关闭面板后丢弃迟到采样 | 当前生命周期测试通过 |
| 日历 entitlement、错误回调显示 | 实现与构建配置已确认；首次授权流程未执行 |
| 去除内置节假日兜底 | 源码与新产物资源核验通过 |
| 排除可编辑的同名个人日历 | 当前只读/订阅限制与相应测试通过；只读同名来源语义仍存在已披露限制 |
| 应用按主 bundle 聚合、按 rootPath 作为行/缓存身份 | 实现与相关测试通过；真实 PID 全量汇总准确性未重新对照 |
| 单行摘要与统一信息行 | 实现和已有截图支持；节日与休息事件分行已获用户确认，R6-1 撤销 |
| CPU/MEM 3 秒单调度源、逐应用按可见性采样 | 实现与相关测试通过；本轮未做完整能耗测试 |

## 4. 独立验证尚未覆盖的项目（不等同已发现缺陷）

- 真实首次点击、“查看更多”、滚动、再次点击关闭、点击其他 App/桌面、Cmd-Tab、Esc。代码路径与主动 `NSApp.deactivate()` 不等于这些操作已执行。跨屏高度已按用户当前环境实测正常记录，不再作为待修复项。
- 首次授权、拒绝/撤销后恢复、实机来源新增/删除、覆盖安装后的授权继承。
- 当前版本与活动监视器的同步 CPU/内存准确性对照；一分钟自校验不能代替独立参考。
- 10 分钟空闲、5 分钟展开、physical footprint、idle wakeups 与 50 次循环后的资源预算。
- 深色、减少透明度、增加对比度、小屏幕、真实睡眠唤醒。
- DMG 手动安装与升级流程。

`ACCEPTANCE_ROUND5.md` 中标为“通过（代码路径）”“通过（根因修复）”的真实交互项目应改为“实现已修订，实机未验证”，不能作为最终通过项。其测试数为历史 63，本轮实际为 64。`BUILD.md` 仍写 entitlement 仅 sandbox=false、产物含 CN 年度数据，也应更新为现状，避免交接误导。

## 5. 当前源码标识

SHA-256（便于后续确认是否为同一版）：

- MenuBarController.swift：`558c0ab8e0ff0b526a4571e8fa90c78c304023b9935eb703258d175261df9b09`
- HolidayProvider.swift：`d98d0e1e3fd7241e998ade3eb817fed8b190fae18f4aa0a452181a394989a07e`
- CalendarModel.swift：`f28efd2cde773d12d43617b7a01c407da011f4ed0326a515a35cf89249ead6ac`
