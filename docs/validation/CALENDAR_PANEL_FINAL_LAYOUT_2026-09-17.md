# 大日历最终布局：四边等距、事件顶部排列 — 实施与验证记录（2026-09-17）

> 本文保留 2026-09-17 旧版布局的验收过程和证据，不再代表现行尺寸。当前实现与验收以 `docs/CALENDAR_PANEL_FINAL_LAYOUT.md` 和 `docs/validation/CALENDAR_PANEL_VISUAL_REFINEMENT_2026-09-18.md` 为准：四边 50 pt、固定 6 行网格、窗口基准内容区 1013.70×580 pt、最多三条事件顶部排列。

本文当时的验收对象为构建产物 `build/Build/Products/Release/CalMon.app`；未安装或替换正式 App。未执行项不视为通过。

## 1. 构建与测试

```sh
xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Release -derivedDataPath build build  # ** BUILD SUCCEEDED **
xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Debug  -derivedDataPath build test   # ** TEST SUCCEEDED **
```

- 全量 **108 项测试全部通过**。覆盖：`H=max(左栏 437.38, 102.83+72.59n)+100`、4/5/6 行尺寸 900×537.38/565.76/638.34、四边等距自洽（`baseWidth = 2×50 + 280 + 24 + 496 = 900`）、小日历比例放大（网格系数 496/328 = 1.5122、日期行 72.59、单元比例与 48/(328/7) 一致）、事件区 = 3×51.85+2×7.78 = 171.09、比例推导与屏幕适配按行数。
- 改动文件：`Calendar/CalendarPanelView.swift`（`PanelLayout`、四边等距、顶部对齐、事件顶部排列）、`Calendar/CalendarPanelController.swift`（按行数的高度与宽高比、观察月份行数变化、保留顶部中心、平移回屏、只在用户拖动结束保存比例）、`Calendar/CalendarComponents.swift`（网格与事件卡度量取自 `PanelLayout`）。

## 2. 当前几何与截图

面板固定绘制 6 行（`model.gridWeeks(minimumRows: 6)`，多出的邻月日期淡化），窗口尺寸与位置不再随月份变化；4/5/6 行月份实测内容尺寸完全一致：

| 场景 | 自然行数 | 面板行数 | 比例 | 实测内容尺寸 | 截图 |
|---|---:|---:|---:|---|---|
| 4 行月（2027-02） | 4 | 6（+2 周邻月） | 1.0 | 1082×638 | `57-fixed6-4rows-900x638.png`（旧 496 宽版本，留档） |
| 5 行月（2026-09） | 5 | 6（+1 周邻月） | 1.0 | 1082×638 | `60-cell4x3-5rows-1082x638.png` |
| 6 行月（2026-08） | 6 | 6 | 1.0 | 1082×638 | `59-fixed6-6rows-900x638.png`（旧 496 宽版本，留档） |

三次运行 `CALMON_PANEL` 日志完全一致（frame `{{548, 205}, {900, 638}}`），见 `measurements/panel-fixed6-2026-09-17.txt`。

- 四边等距：宽 1081.46 = 50+280+24+677.46+50；高 = 块高 + 100 = 638.34。
- 两栏顶部对齐、左右标题同用 48.39 pt 标题带 28 pt medium。
- 格子 96.78×72.59（4:3，x 轴更长，不再是近方形）；日期行距均匀，不拉伸。
- 事件区 230.72 pt（4 卡，卡 51.85、间距 7.78），单条从事件区顶部排列，余量在下方；四条时贴住日期网格底边。

## 3. 已确认与未确认

已确认（本轮复核）：

- 事件顶部排列；三条以内无滚动容器、无滚动条。
- 108 项测试通过、Release 构建成功。

**已记录偏差（当前保留，未改；现由弹性间隔吸收）**：左栏文字容器与时钟后间隔沿用未随字号放大的旧值（当前时间 12、时钟 56、间隔 8、星期 20、周数 16），字号已按 1.2962 放大（14.26 / 57.03 / 20.74 / 15.55）。按代码字面量计算，左栏渲染上半区比设计值短 **33.17 pt**（206.19 vs 239.36）。该差额现由**分隔线上方的弹性间隔**吸收：渲染后左栏 = 上半区 + 弹性间隔 + 分隔线 + 4 卡事件区 = **538.34 pt**，事件区底边与日期网格底边重合，左栏末尾不再留空；可观察到的唯一差别是分隔线的实际高度位置比声明公式低约 27 pt（弹性间隔 87.47 pt 对声明最小值 12.96 pt）。截图 `57–59` 中事件卡顶部约 300 pt、事件区底与网格底同为 588.34 pt，与上述计算一致。本节不做“通过”判定。

未执行：

- **真实鼠标拖动**窗口边缘/角验证实时等比缩放；本轮只有程序设置尺寸（`CALMON_PANEL_SIZE`）与几何日志（`liveScale=1.0 / 1.25`）。
- **真实点击/键入**（搜索入口、清除、四个导航按钮）；界面工具本轮超时未完成。
- **真实 1/2/3 条与 >3 条事件**：构建产物 `access=notDetermined`（未授予日历权限），面板目前只有相对日期 1 条；三条完整显示与溢出滚动仅由布局常量与单元测试覆盖。
- 减少透明度 / 增加对比度外观；多显示器拔屏与跨屏适配。

## 4. 缩放与切月（实现与日志）

- 统一比例 s，内容尺寸 880→900 基准的 `900s × H(n)s`；当月拖动锁定该比例，实时同步所有度量。
- 切月/切年行数变化时保留 s 与窗口顶部中心，只更新高度（Debug 日志 `EVENT panel resize rows=… old=… new=…`，midX 与顶边不变），不重新居中、不加动画。
- 超出屏幕先平移回可用区域，仍放不下才临时降低 s，且不写回偏好；`windowDidEndLiveResize` 只在用户拖动结束时保存比例（`windowWillStartLiveResize` 标记）。

## 5. 复现

```sh
CALMON_PANEL_SIZE=900x538 CALMON_SELECT_DATE=2027-02-15 CALMON_CAPTURE=panel build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
CALMON_PANEL_SIZE=900x566 CALMON_CAPTURE=panel build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
CALMON_PANEL_SIZE=900x639 CALMON_SELECT_DATE=2026-08-15 CALMON_CAPTURE=panel build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
CALMON_PANEL_SIZE=1125x708 CALMON_CAPTURE=panel build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
```

## 6. 结论

- 通过：Release/Debug 构建、108 项测试、四边 50 pt 等距、小日历比例放大与均匀行距、固定 6 行网格（4/5/6 行月份窗口恒为 900×638.34、切月不浮动）、事件四卡容量与顶部排列、4 条时事件区底与日期网格底对齐。
- 未通过/未执行：第 3 节的左栏容器高度偏差（已记录、未修）、真实拖动/点击/键入、真实多条事件。以上均不计入通过。
