# 监控应用名称搜索：实施与验证（2026-09-16）

依据 `docs/MONITORING_APP_SEARCH.md`（本轮冲突以该搜索规格为准）。已实现代码、运行测试与 Release 构建；真实交互项在本机受限，逐项标注。

## 1. 改动范围

| 文件 | 改动 |
|---|---|
| `CalMon/Monitoring/MonitoringView.swift` | 列表标题行右侧“按内存降序”文字 → 原生 `NSSearchField`（`SearchField` 轻量包装，small、宽 130、占位“搜索应用”、带放大镜/清除按钮、`setAccessibilityLabel("搜索应用")`）；新增 `@MainActor @Observable AppSearchModel` 保存临时查询；搜索时用 `AppMemoryReader.filter` 过滤、展示全部匹配（可滚动）并隐藏“查看更多/收起”，无结果显示“未找到匹配应用”；Esc 在搜索框内：有查询清空、无查询回调关窗，组合输入（marked text）交给输入法；空查询沿用原展开/收起与冻结顺序逻辑 |
| `CalMon/Monitoring/AppMemoryReader.swift` | 新增 `nonisolated static func filter(_:query:)`：仅按 `AppUsage.name` 做大小写不敏感连续子串匹配；查询去首尾空白，空白视作无查询 |
| `CalMon/App/MenuBarController.swift` | 持有 `AppSearchModel` 并传入 `MonitoringView`；打开监控弹窗时清空查询、`popoverDidClose` 再清空（hosting 复用下仍不保留旧查询）；另加仅验证用的 `CALMON_SEARCH` 环境变量（默认不触发） |
| `CalMon/App/UIStyle.swift` | 新增 `Metrics.searchFieldWidth = 130` |

未新增采样、定时器、依赖、网络、持久化或搜索历史；未改统计口径、CPU/MEM 字体、设备行、圆环、月历、设置、右击菜单。

## 2. 测试

`xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Debug -derivedDataPath build test` → **74/74 通过**。新增 5 项（`CalMonTests/MonitoringTests.swift`）：

- `testSearchMatchesChineseSubstring`：“飞”“飞书”→“飞书”。
- `testSearchIgnoresEnglishCase`：“chat”“CHAT”→ChatGPT、ChatGPT Classic。
- `testSearchTrimsWhitespaceAndBlankReturnsAll`：“  飞  ”等价“飞”；空白/空串返回全部。
- `testSearchDoesNotMatchPinyinOrBundleID`：“feishu”“tencent”均不命中。
- `testSearchCoversFullListBeyondFirstEight`：第 9 个应用可被搜到。

Release 构建成功，无 Swift 警告。

## 3. 实机（单个 Release 实例，经 `open` 启动）

组件截图（`docs/validation/screenshots/`）：
- `02-monitoring.png`：默认态——标题右侧为搜索框（占位“搜索应用”），底部仍显示“查看更多…”。
- `09-monitoring-search-match.png`：查询 `chat`——列出 ChatGPT 等匹配项，无“查看更多/收起”。
- `10-monitoring-search-empty.png`：查询 `zzz`——显示“未找到匹配应用”。

| 验收项 | 结果 | 证据 |
|---|---|---|
| 中文连续子串（“飞”→“飞书”） | 通过 | 单测 |
| 英文忽略大小写（chat/CHAT） | 通过 | 单测 |
| 空白查询恢复普通列表 | 通过 | 单测 |
| 不匹配拼音/bundle ID/PID | 通过 | 单测 |
| 搜索覆盖完整列表（含第 9 行） | 通过 | 单测 |
| 搜索框替换“按内存降序”、保留左侧标题 | 通过 | 截图 02/09/10 |
| 无结果状态“未找到匹配应用” | 通过 | 截图 10 |
| 搜索时隐藏“查看更多/收起”、全部匹配可滚动 | 通过 | 截图 09（代码路径） |
| 清空恢复原展开状态 | 通过（代码路径） | `query` 为空时回到 `orderedRows`+`isExpanded` |
| 关闭弹窗清空查询 | 通过（代码路径） | `toggleMonitorPopover` 打开时置空 + `popoverDidClose` 置空 |
| 数值随既有 3 秒采样刷新、无额外采样 | 通过（代码） | 仅过滤现有 `monitor.applications`，未新增采样 |

## 4. 人工交互验收（用户实机）

实施方工具受 `AXIsProcessTrusted=false` 限制无法合成点击/键盘；**用户于 2026-09-16 在构建产物上自行实机操作并确认无问题**。以下项目为**用户人工确认**（非实施方工具复现）：

- 真实鼠标点击搜索框聚焦、点击清除按钮、点击“查看更多/滚动”。
- **中文输入法**实际组合输入“飞”、候选选择/取消。
- **Esc** 实测：有查询清空、空查询关窗、组合输入优先。
- **Tab** 聚焦顺序与采样刷新后焦点保持。
- 外部点击关闭、切到日历再打开、再次点击监控菜单栏关闭后再打开后搜索框确为空。
- 应用启动/退出随采样进出搜索结果。

用户结论：自行验证无问题。实施方工具未独立复现，保留上述说明以区分证据来源。

`CALMON_SEARCH` 仅用于在无点击环境下截图；正常使用不设置、不触发。

## 5. 结论

- 通过：名称匹配规则、搜索覆盖完整列表、界面替换、无结果/滚动/隐藏“查看更多”、清空与关闭重置的代码路径、单测与 Release 构建。
- 人工交互（中文输入法、Esc、Tab、清除按钮、点击关闭/重开）由用户在实机确认无问题（见 §4；非工具复现）。
- 未发布 DMG、未安装/替换本机 App。
