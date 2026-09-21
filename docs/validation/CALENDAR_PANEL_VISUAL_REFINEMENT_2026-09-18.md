# 快捷键大日历视觉收敛验收（2026-09-18）

验收对象：`/private/tmp/CalMon-layout-release/Build/Products/Release/CalMon.app`。未安装、未替换正式 App。

## 实施结果

- 窗口基准内容区：1013.70×580 pt，固定六行，切月不改变尺寸。
- 四边 50 pt；左栏 280、栏间距 24、右栏布局区 609.70。
- 月历网格收紧到 560×384，列宽 80、行高 64，并在右栏水平居中。
- 标题带统一为 44 pt；月份导航标题固定 170 pt 并保持绝对居中，左右 92 pt 导航组分别对齐网格两端，四个按钮命中区 44×44 pt。
- 左栏文字容器全部改用 PanelLayout 常量，事件区顶部 261 pt；事件卡 48 pt、间距 8 pt、三条容量 160 pt。
- 0–3 条使用普通顶部列表；超过三条才进入隐藏指示条的局部滚动区。

## 构建与测试

- Release：`** BUILD SUCCEEDED **`。
- Debug 测试：110/110 通过，0 失败。
- Release 无 Swift 编译警告；工具链输出一次 AppIntents 元数据跳过提示。测试期间仍有既有 QoS 优先级反转警告，与本轮布局无关。
- `git diff --check` 通过。

## 运行检查

- 使用 Release 捕获钩子以 1013.70×580、三条事件启动，确认三条均从事件区顶部排列，无滚动条。
- 可访问性树确认四个年月导航按钮、42 个日期按钮和三条事件均存在，选中日语义正确。
- 视觉检查确认左右标题同一水平带、星期与网格同轴、日期列距较上一版收紧，左侧日期/时间/附加信息/事件之间没有弹性空档。
- 另以已保存比例约 1.4057 打开，字体、日期格、事件卡与间距使用同一比例，未出现裁切或错位。

## 未执行

- 自动化工具无法把指针拖出目标窗口完成真实放大，实际鼠标连续拖动仍需人工复验。程序化 1×与已保存 1.4057×只能验证两种稳定尺寸，不能替代拖动过程验收。
- 本轮未重新检查深色、减少透明度、多屏拔插和超过三条真实 EventKit 数据。

## 后续调整（2026-09-21，随 1.8 发布）

在上文 1.7 布局之上追加，几何参数（1013.70×580、cellWidth 80、dateRowHeight 64、560 网格等）不变：

- **高亮形状与尺寸**：今天/选中由「54 pt 圆形」改为 **60 pt 圆角方块**（圆角 = 尺寸 × 28%）；`dayDotArea` 改为按行高反推（64−60 = 4），提示点直径 5 会有 0.5 pt 溢出，肉眼不可见；相邻两天同时高亮仍留 4 pt 间隔。截图 `screenshots/68-highlight-rounded-square-1014x604.png`、`69-highlight-large-square-1014x604.png`。
- **周末/休数字配色**（两处日历共用）：周六/周日或法定「休」→ 红色；周末遇调休「班」→ 正常色；普通工作日 → 正常色；今天 → 白字红块；邻月周末/休 → 45% 淡化红，邻月其余 → 淡化灰；表头周六/周日 → 红色。截图 `screenshots/66-weekend-red-1014x604.png`、`67-weekend-red-adjacent-dimmed-1014x604.png`。
- **监控三卡增加未使用**：副行改为两行且左对齐（`已使用` / `未使用` 三字对齐、数值上下对齐），圆环与文字之间额外 6 pt 间距；未使用量与已使用来自同一快照（内存/磁盘 `total - used`，无法读数时显示 `--` 而非 0；CPU 由取整后的已用推导，两行恒加 100%）。截图 `screenshots/70-monitoring-unused-426x644.png`。
- 测试：Debug 全量 **115/115 通过**（新增周末判定、表头周末列、数字配色分支、内存/磁盘未使用量口径）；Release 构建通过。
- 仍未执行：真实调休「班」数据的截图、真实鼠标拖动过程、深色/减少透明度/多屏拔插、超过三条真实 EventKit 事件。

## 后续调整（2026-09-21 第二次，随下一版发布）

### 监控图标来源修正

- 现象：ChatGPT Classic 一行显示系统通用 exec 图标。
- 根因：`runningApplications()` 在构造候选时就按 `rootPath` 缓存图标；嵌套 helper `ChatGPT Classic.app/Contents/Resources/ChatGPTHelper`（无 bundle id）先被枚举到，其 exec 图标占用了该 root 的缓存键，之后顶层 App 顶上名字但图标仍是缓存里的 helper 图标。
- 修法：行图标改为按根 bundle 取（`NSWorkspace.icon(forFile: root)` 再降采样），与枚举顺序无关。
- 复核：对 22 个用户可见 App 根 bundle 逐一比对「行图标」与「bundle 图标」哈希，修复前仅 ChatGPT Classic 不一致（52f679bc vs ad8fb588），修复后界面确认显示 GPT 花标；其余 21 个本来就一致。证据 `screenshots/71-monitoring-chatgpt-classic-icon-426x644.png`。

### 关闭后释放视图树（A）

- 监控/日历弹窗在 `popoverDidClose` 置空 `contentViewController`；快捷键面板在 `close()` 里释放内容（窗口、比例与已保存 scale 保留，`show()` 时重建）。
- 验证：关闭后 `heap` 中 `CalendarPanelView/PanelContentController/CalendarInfoRow` 对象数为 0（释放前 40），确认视图树确实被释放；弹窗/面板打开均正常，50 次开关压力测试 `delta=3MiB`（预算 ≤10 MiB），118/118 测试通过。
- **读数修正**：释放视图树对 footprint 的实际收益约 **2–6 MB**（面板 35→33，监控弹窗 41→35），而不是最初估计的 ~26 MB。原因：关闭后剩余的大头是 **进程级框架缓存**（SwiftUI/AppKit 首次使用后常驻的布局/玻璃/无障碍机制、ObjC method cache）以及 NSPopover/NSPanel 保留的窗口与其背衬（`IOSurface` 约 4.4 MB），这些不随视图树释放。pristine 基线（从未打开过面板）仍为 18 MB。

### 复核口径

- RSS（约 76 MiB 空闲）包含大量共享框架常驻页，不代表真实压力；判断应看 footprint，即活动监视器“内存”列。
- 未执行：真实鼠标拖动与真实调休数据截图等前文未执行项不变。
