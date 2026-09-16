# 本轮修复与独立验证结果

日期：2026-09-15。用户授权直接实施后完成。**本轮 T1–T3 代码/证据问题已处理，新增日历权限回归缺陷已修复；64 项测试全部通过，Release 构建成功。**

## 修复内容

| 项目 | 实际改动 | 验证 |
|---|---|---|
| T1 异常内存配平 | 删除字段 clamp 和 max(measuredUsed, componentSum)；used 始终来自同一公式；矛盾样本返回 nil。界限检查用减法避免相加溢出。 | 非法字段、分项超公式 used、分项溢出测试通过；正常记录字节回归通过。 |
| T2 原始证据错误 | 保留原始页计数与英文截图，将差值改为 30928 页并重算 used/other/remaining；删除“其他”具体成分的无证据归因。 | 独立复算与 testRecordedMemorySampleReproducesRawBytes 一致；原记录相对截图显示值偏差约 0.00717 个百分点。 |
| T3 缓存测试不足 | 测试替身模拟查询完成后的缓存回填；关闭前后分阶段检查 trim 次数，并断言最终缓存为空。 | 确认应用查询已进入后台后才关闭面板，释放查询后再次清理，测试通过。 |
| 日历失效边界 | 查询前检查访问权限；发现所选来源不存在时清空选择并使任务失效；reloadEvents 在无范围且权限撤销时也正确发布未授权状态。 | 注入授权检查，模拟成功发布→撤销→重载→旧结果返回；事件清空、旧结果丢弃、重复重建不循环，测试通过。 |
| 测试宿主隔离 | Debug 测试专用 CALMON_TEST_HOST=1；启动回调在读取用户偏好及创建菜单栏之前返回。共享 scheme 测试环境与普通启动环境分离。 | 实际生成的 xctestrun 包含该标记，Debug 编译条件已确认；测试仍能访问 Bundle.main 静态资源。 |

正常内存采样没有增加生产日志或历史存储。单位保持内存二进制 GB/MB、磁盘十进制 GB。未改视觉布局、签名身份或安装位置，未操作用户登录项、日历授权和正式偏好。

## 实际运行结果

环境：macOS 27.0 (26A428)，Xcode 27.0 (27A266a)，Swift 6.4，Apple M1 Pro，32 GiB，页大小 16384，arm64。

### 自动测试

```sh
xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Debug \
  -derivedDataPath /private/tmp/CalMon-fix-validation test CODE_SIGN_IDENTITY=-
```

- 64 tests，0 failures，退出码 0，`TEST SUCCEEDED`。
- 首次实跑新增日历撤销测试失败，定位到无待重载范围时未更新授权状态；修复后重新执行完整测试通过，未删除或放宽该测试。
- 一分钟真实采样：21 份，每 3 秒一次，21/21 有效。每份均核对公式和五段原始字节总和；已用占比范围 71.08883857727051%–73.36573600769043%。
- 此一分钟检查的是生产读取/计算在本机上的有效性与一致性，**不是活动监视器同步对照，也不是 Release 性能测量**。
- XCTest 日志：`/private/tmp/CalMon-fix-tests-final.log`。
- 结果包：`/private/tmp/CalMon-fix-validation/Logs/Test/Test-CalMon-2026.09.15_20-57-19-+0800.xcresult`。

### Release

```sh
xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Release \
  -derivedDataPath /private/tmp/CalMon-fix-release build CODE_SIGN_IDENTITY=-
```

- `BUILD SUCCEEDED`，退出码 0，无 Swift 编译警告。
- 有一条“未依赖 AppIntents，跳过元数据提取”的工具提示，非 Swift 警告。
- 日志：`/private/tmp/CalMon-fix-release.log`。
- 产物仅生成在临时目录，未安装、替换或启动正常产品会话。Debug 测试宿主由 XCTest 自动启动后退出，其正常 App 初始化已隔离。

简要实测输出与修复代码指纹见 `measurements/fix-validation-summary.txt`、`measurements/fix-source-sha256.txt`。临时目录的完整日志/产物可能被系统清理，工作区摘要供长期留存。

## 精度结论及后续边界

- 原证据的具体减法错误已纠正；相对截图的单场景精度满足 1 个百分点门槛，但截图有舍入，不宣称逐字节精确相等。
- 不再通过改统计目标、抬高 used、截断异常字段来让组成条铺满。无法解释的矛盾样本按无效处理。
- “其他”只表达未细分统计差额，不宣称已证明其具体组成。
- 覆盖文件缓存增长/释放和压缩变化的同步活动监视器对照，完整应用组 PID 汇总核验、修复后 Release 长时间资源预算仍需补验；早期少读进程版本的性能记录不升级为当前版本通过结论。
- 日历首次 TCC 交互、实际撤销/恢复、真实鼠标/键盘、睡眠/时区及 DMG 双版本覆盖安装授权继承仍未实机验收。当前 ad-hoc 构建不是已完成的稳定签名交付方案。
- 第二轮报告中“有效日历权限持续复用，正常覆盖安装不重复请求”的用户约束保持有效；本轮没有请求日历权限。

本报告记录本轮实际修复和验证，不将尚未执行的最终安装及交互验收标为通过。
