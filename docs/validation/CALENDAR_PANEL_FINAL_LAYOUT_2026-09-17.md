# 大日历最终布局：四边等距、事件顶部排列 — 实施与验证记录（2026-09-17）

按 `docs/CALENDAR_PANEL_FINAL_LAYOUT.md` 实施（**现行基准：四边 50 pt、内容宽 900 pt**）。验收对象为构建产物 `build/Build/Products/Release/CalMon.app`；**未安装、未替换正式 App、未提交、未发布、未触发 Homebrew**。未执行项不视为通过。

## 1. 构建与测试

```sh
xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Release -derivedDataPath build build  # ** BUILD SUCCEEDED **
xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Debug  -derivedDataPath build test   # ** TEST SUCCEEDED **
```

- 全量 **108 项测试全部通过**。覆盖：`H=max(左栏 437.38, 102.83+72.59n)+100`、4/5/6 行尺寸 900×537.38/565.76/638.34、四边等距自洽（`baseWidth = 2×50 + 280 + 24 + 496 = 900`）、小日历比例放大（网格系数 496/328 = 1.5122、日期行 72.59、单元比例与 48/(328/7) 一致）、事件区 = 3×51.85+2×7.78 = 171.09、比例推导与屏幕适配按行数。
- 改动文件：`Calendar/CalendarPanelView.swift`（`PanelLayout`、四边等距、顶部对齐、事件顶部排列）、`Calendar/CalendarPanelController.swift`（按行数的高度与宽高比、观察月份行数变化、保留顶部中心、平移回屏、只在用户拖动结束保存比例）、`Calendar/CalendarComponents.swift`（网格与事件卡度量取自 `PanelLayout`）。

## 2. 当前几何与截图

| 场景 | 行数 | 比例 | 实测内容尺寸 | 截图 |
|---|---:|---:|---|---|
| 4 行月（2027-02） | 4 | 1.0 | 900×538 | `53-current-4rows-900x538.png` |
| 5 行月（2026-09） | 5 | 1.0 | 900×566 | `54-current-5rows-900x566.png` |
| 6 行月（2026-08） | 6 | 1.0 | 900×639 | `55-current-6rows-900x639.png` |
| 5 行月放大 | 5 | 1.25 | 1125×708 | `56-current-5rows-1125x708.png` |

原始 `CALMON_PANEL` 日志见 `measurements/panel-current-2026-09-17.txt`。

- 四边等距：宽 900 = 50+280+24+496+50；高 = 块高 + 100。
- 两栏顶部对齐、左右标题同用 48.39 pt 标题带 28 pt medium。
- 网格按小日历比例放大后，单元格宽 496/7 = 70.86、高 72.59，宽高比 1.0244 与小日历（48 / 46.86）一致，近方形；日期行距均匀，不拉伸。
- 事件区 171.09 pt（卡 51.85、间距 7.78），单条从事件区顶部排列，余量在下方。

## 3. 已确认与未确认

已确认（本轮复核）：

- 事件顶部排列；三条以内无滚动容器、无滚动条。
- 108 项测试通过、Release 构建成功。

**已记录偏差（当前保留，未改）**：左栏文字容器与时钟后间隔沿用未随字号放大的旧值（当前时间 12、时钟 56、间隔 8、星期 20、周数 16），字号已按 1.2962 放大（14.26 / 57.03 / 20.74 / 15.55）。按代码字面量计算：左栏实际渲染流程 **404.21 pt**、事件区顶部 **233.11 pt**（对窗口顶部 50+233.11 = **283.11 pt**）；而 `PanelLayout` 声明的左栏高度为 **437.38 pt**、事件区顶部 266.28 pt（对窗口顶部 316.28 pt）。900×566 截图实测事件卡首行出现在约 283 pt，与代码字面量一致、比设计公式早 33.17 pt；该 33.17 pt 留在左栏末尾。窗口高度（块高 + 100）与行数驱动的 900×537.38/565.76/638.34 不受影响。文档（本文、UI_SPEC、ACCEPTANCE、FINAL_LAYOUT）已按代码实际值记录，本节不做“通过”判定。

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

- 通过：Release/Debug 构建、108 项测试、四边 50 pt 等距、小日历比例放大与均匀行距、事件顶部排列与三条容量、按行数驱动高度并保留缩放比例与顶部中心。
- 未通过/未执行：第 3 节的左栏容器高度偏差（已记录、未修）、真实拖动/点击/键入、真实多条事件。以上均不计入通过。
