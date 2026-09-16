# 界面问题与后续验收补充

日期：2026-09-15。本轮仅记录问题、检查实现、补充交接要求，不修改应用代码。

## 1. 用户最新确认（优先于 UI_REFINEMENT.md 的冲突内容）

### U1 · 菜单栏

- 当前缩小后的字号已认可，保持，不再继续缩字。
- CPU/MEM 与日期之间仍有明显大间隔，需要查明实际空白来源并收紧；两个独立点击入口继续保留。

### U2 · 系统日历与数据范围

- 用户实机点击“获取权限”没有反应，功能未通过；必须查明请求是否发出、系统返回状态及错误，不能只以存在调用代码判通过。
- **不再内置节假日日历，也不以年度 JSON、内置节日日期规则等兜底。** 没权限、没找到系统节日日历或没有读到内容时，显示普通日历即可。
- 普通日历保留公历日期、周起始、选中/今天、日期差及已有农历开关；本次没有要求删除农历。节气与农历不同，本次明确移除的是内置节假日/调休来源，不把此要求擅自扩大成删除所有历法功能。
- 系统来源有可用节日才显示节日；有明确休/班信息才显示对应标记。没有数据不猜测、不按周末生成、不从假期名称反推调休；因此没有系统班/休数据时不保证班/休显示。
- 授权有效持续复用，覆盖安装不主动重复请求，授权与内容可用状态分开。不得读取全部个人日程替代节日日历。
- 移除“使用内置节假日”“该年度调休安排尚未收录”等旧兜底说明及旧数据依赖。中国节假日开关仅控制系统来源可用的节日显示，不再暗示内置覆盖保证。

### U3 · 设置对齐

- “周起始日”的周一/周日横向原生单选保持，但选项组应靠右对齐。
- 以设置中开关和“获取权限”按钮的右边界为统一控制列右边界；选项组不在宽容器中居中，不留无意义尾部空白。标签保持左对齐、基线协调。

### U4 · 月历详情（图二改为图三的组织）

- 摘要改为**单行**：左侧“2026年09月25日（第39周）”，右侧“丙午年（马）八月十五”。不再把周数/星期单独放第二行，也不保留中点串联的“属马”形式。
- 星期仍可通过日期单元格辅助说明/tooltip 获取，不挤入摘要单行。菜单栏星期设置不变。
- 摘要下方的“距今天…”与节日都使用同一类信息行：左侧“全天”，右侧浅色圆角块和细绿色竖线。相对日期不再是一行裸文字。
- 节日事件与休息/补班事件是不同事件，分别保留。例如“中秋节”和“中秋节（休）”允许各占一行，后者保留“休息”标签。这是用户最新确认的正常展示，不得合并或删除。去重仅针对同类同义的重复条目，不跨事件类型合并。
- 今天只显示一次“今天”；无节日时只保留日期摘要与相对日期，不增加“无节日/未连接/内置兜底”多行提示。权限详情放设置中。
- 在当前字号下先测量单行最小宽度：优先用约定的紧凑文案和有效列宽；确需加宽月历时只做容纳该行所需的最小调整并记录数值，不继续缩字或悄悄退回两行。小屏整体适配不得裁切文字。

### U5 · 统一毛玻璃（本轮核心未通过项）

- 用户实机反馈日历与监控的毛玻璃仍不同，不接受仅因两者都用 NSPopover 就标“统一完成”。
- 继续采用监控弹窗作为外壳基准，检查整个渲染路径：外壳、Hosting 背景、ScrollView 背景、内容容器覆盖率、材质/不透明度、外观继承、阴影及顶部箭头。
- 两者在同壁纸、同屏幕位置附近、同倍率、同外观和同激活状态下分别拍小图对比。区分壁纸取样差异与实际背景配置差异，并给出证据。
- 不通过自绘玻璃、额外固定蓝白渐变、第二套阴影掩盖问题；不改变已认可的字体。

## 2. 验收结果

**结论：本轮界面及日历权限验收未通过。** 已认可字号保持；以下是当前源码、真实构建产物及提供截图的复核结果。新增需求与上一版实现缺陷分开描述。

### A1 · P1 · Release 缺少日历访问 entitlement

位置：[CalMon.entitlements](/Users/wangqing/code/CalMon/CalMon/Resources/CalMon.entitlements)。

独立 Release 构建后检查实际签名：flags 包含 `runtime`，但 entitlement 只有 app-sandbox=false 和构建注入的 get-task-allow=true，没有 `com.apple.security.personal-information.calendars`。Info.plist 已包含 NSCalendarsFullAccessUsageDescription，不能只补说明文字就认为配置完整。

Apple 的[日历访问 entitlement 文档](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.personal-information.calendars?changes=_9)明确将该能力用于 App Sandbox 或 Hardened Runtime。当前配置缺口已确认，是“Release 获取权限没有反应”的重要根因线索；本轮没有点击请求，不能将它宣称为所有运行环境下的唯一根因。

修复要求：在正确的签名配置中声明日历访问能力，检查最终 Release/DMG 产物实际 entitlement 和用途说明；保持系统授权由用户批准。不要关闭 Hardened Runtime 或清空 TCC 来绕过问题。历史 REPORT.md 的“登录项与隐私声明正确”不能继续作为此项通过依据。

### A2 · P1 · 授权错误被丢弃，界面可能无解释地回到原按钮

位置：[HolidayProvider.swift:203](/Users/wangqing/code/CalMon/CalMon/Calendar/HolidayProvider.swift:203)。

requestFullAccessToEvents 回调声明为 `granted, _`，忽略了 error。如果系统请求失败且授权状态仍为 notDetermined，refreshAccessState 会恢复“获取权限”，没有错误说明，符合用户看到的无反应表象。

另需校正状态映射：refreshAccessState 将所有剩余状态视为 notDetermined，但 requestAccess 只对真正 notDetermined 发请求；例如 writeOnly 不应显示一个实际上不升级读取权限的按钮。显示与操作必须采用一致状态机。

修复要求：记录本次请求是否开始、回调 granted/error 和请求后授权状态（验收日志不含事件内容）；把配置/系统错误、用户拒绝、系统限制、请求中分别呈现。不能无响应地返回初始状态，也不能用“系统需要交互”搪塞未发出的请求。补错误回调、重复点击和权限升级测试，再在实际 Release 中由用户验证首次请求。

### A3 · 新需求未实施 · 内置节日与调休仍在运行和打包

位置：[HolidayProvider.swift:104](/Users/wangqing/code/CalMon/CalMon/Calendar/HolidayProvider.swift:104)、[SettingsView.swift:112](/Users/wangqing/code/CalMon/CalMon/Settings/SettingsView.swift:112)。

仍加载 Holidays/CN-YYYY.json，仍有内置节日日期推导函数，设置明确显示“使用内置节假日”。这符合上一版兜底方案，但与本次 U2 冲突，应按最新要求移除产品资源、加载/回退分支、相关说明和旧覆盖保证测试。

新验收应覆盖：无权限/授权但无节日日历/空事件均显示普通日历；只保留明确从系统事件得到的节日及班休信息，不把旧 JSON 内容换个位置继续兜底。历史验收数据可保留为历史记录，不打包进 App。

### A4 · P2 · 周起始选项没有可靠的右对齐布局约束

位置：[SettingsView.swift:71](/Users/wangqing/code/CalMon/CalMon/Settings/SettingsView.swift:71)、同文件 WeekStartRadio。

当前用 LabeledContent 包裹 NSViewRepresentable，内部 NSStackView 未显式约束可用宽度与靠右布局。原生 radio 已实现，但用户截图显示选项组尾部存在较大空白，未与其他控件右边界对齐。

修复要求：控制整个组的实际 fitting/intrinsic width，在右侧控制列尾端定位；检查 NSView 的 hugging/compression 和 SwiftUI frame，不仅调整按钮之间 spacing。以图一截图列边界验收，保持原生互斥单选和当前字号。

### A5 · 新布局未实施 · 摘要仍是两行，相对日期仍是裸文字

位置：[CalendarView.swift:222](/Users/wangqing/code/CalMon/CalMon/Calendar/CalendarView.swift:222)。

summaryRow 明确使用 VStack 把公历与周数/星期分两行；relativeRow 仅返回 Text。两处与 U4 的单行摘要、相对日期卡片要求直接冲突。

按图三统一信息行组件与左右列：摘要一行，相对日期与节日都使用左侧“全天”及右侧浅色块。相对日期的措辞统一为“距今天还有 N 天 / 已过 N 天”；图三重复节日不复制。

### A6 · 未通过 · 毛玻璃一致性尚无合格证据，内容背景确有差异

位置：[MenuBarController.swift:305](/Users/wangqing/code/CalMon/CalMon/App/MenuBarController.swift:305)、[MonitoringView.swift:234](/Users/wangqing/code/CalMon/CalMon/Monitoring/MonitoringView.swift:234)、[CalendarView.swift:271](/Users/wangqing/code/CalMon/CalMon/Calendar/CalendarView.swift:271)。

两个 HostingController 的创建方式基本相同，但这不足以证明最终外观一致。当前监控卡片用 quaternaryLabelColor.opacity(0.25)，月历信息块用同色 opacity(0.35)；监控大面积有卡片覆盖，月历网格大部分直接露出外壳。层级覆盖率和背景不透明度本身就会造成观感差异。

不能据此断言“系统外壳一定选错材质”：该根因需要同条件实机比较。已提交的透明组件 PNG 也不能脱离实际背景直接比较；截图合成环境会影响外观。用户实机不一致反馈继续列为未通过。

修复要求：以监控外壳为基准统一外壳与内容背景的角色定义，检查未覆盖区域和卡片区域，不必为了相同覆盖率给日历网格套大灰卡；提供带真实背景的对照小图，再给组件截图。禁止仅写“都用了 NSPopover，所以已一致”。

### A7 · 待定位 · 菜单栏大间隔不能只归因于字体或一句“系统默认”

位置：[MenuBarController.swift:403](/Users/wangqing/code/CalMon/CalMon/App/MenuBarController.swift:403)。

源码画布左右 padding 已为 3 pt，相邻两个图像内部边距合计仍有 6 pt；此外实际视觉空白还包含 NSStatusBarButton 内部图像布局和系统项目间隔。数值列预留 100% 宽度且右对齐，不能简单删除该预留导致数字跳宽。

本次没有新菜单栏实机图和实际按钮 frame 测量，不能给出总空隙的确定 pt 值。需要对照按钮边界、图像边界、可见字形边界分别量出空白，先消除 App 可控的冗余。系统保留间隔确有下限时提交测量和限制，不继续缩字号、不合并入口、不使用私有布局 API。

## 3. 独立补充不足

### B1 · P1 · 自动来源识别仍只依赖名称

位置：[HolidayProvider.swift:234](/Users/wangqing/code/CalMon/CalMon/Calendar/HolidayProvider.swift:234)。

autoDiscoverSource 先把所有 EKCalendar 映射成 id/title，随后取第一个匹配“中国/china/chinese”及“节日/holiday”的名称。没有使用来源类型、只读/订阅信息等交叉证据，与前一版“名称关键字不能单独保证身份”的约束冲突。名为“中国节日计划”的普通个人日历也会被命中。

移除内置兜底不代表可以放宽成任意日历读取。应提交可验证的系统节日来源识别规则；无法可靠识别时使用普通日历。不能自动读取全部个人日程，也不能要求新增第三方服务。

### B2 · P2 · 应用聚合按路径区分实例，但行 ID/图标缓存仍只用 Bundle ID

位置：[AppMemoryReader.swift:61](/Users/wangqing/code/CalMon/CalMon/Monitoring/AppMemoryReader.swift:61)、[AppMemoryReader.swift:147](/Users/wangqing/code/CalMon/CalMon/Monitoring/AppMemoryReader.swift:147)。

主 bundle 路径聚合已实现，是进步；但 AppUsage.id 和图标缓存 key 仍取 bundleIdentifier。两个安装位置的同一软件可产生两条相同 ID，导致 SwiftUI 行身份/排序冻结及图标缓存冲突，不符合“不同安装实例区分”的旧要求。

修复要求：行身份与聚合边界一致，使用规范化主 bundle 路径等稳定实例信息；补相同 Bundle ID、不同路径的案例。飞书/Chrome 同主 bundle helper 应继续合并，不能退回按 helper 分行。当前截图有主软件行，不代替完整 PID 汇总验收。

### B3 · P2 · 系统日历变化只重载旧来源，未重新发现新来源

位置：[HolidayProvider.swift:272](/Users/wangqing/code/CalMon/CalMon/Calendar/HolidayProvider.swift:272)。

EKEventStoreChanged 通知当前只调用 reloadEvents。当原本没有来源，后来系统添加了节日订阅时，selectedCalendarID/reloadRange 仍为空，通知不会自动发现新来源。删除后再新增也需要覆盖，不能依赖用户重开设置才恢复。

修复要求：来源变化通知先核验授权及来源集合，再按需查询当前范围；仍使用通知，不新增 3 秒日历轮询。授权变化时 accessState、sourceStatus、holidayCalendarTitle 要保持一致。

## 4. 本次实际验证与已改善项

- 已查看用户三张截图、现有监控/月历组件截图及相关源码。
- 用户认可当前菜单栏字号，保持。源码已移除内存组成卡；周起始原生横向单选已存在；日期提示点布局与邻月角标相比前版有改善；主 bundle 聚合已有实现。这些不抵消本轮未通过项。
- 独立 Release 构建成功、退出码 0，无 Swift 编译警告；有 AppIntents 元数据跳过提示。构建不等于权限/视觉通过。
- 构建命令：`xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Release -derivedDataPath /private/tmp/CalMon-ui-review-next build CODE_SIGN_IDENTITY=-`。
- 构建日志：`/private/tmp/CalMon-ui-review-next.log`。实际产物已检查签名 entitlement、runtime 标记和 Info.plist 日历说明。
- 本轮没有运行当前版本 XCTest、没有安装或启动 App，没有点击授权、改用户设置或操作登录项。历史 58/64 等测试数量不写成本轮执行结果。
- 毛玻璃同条件实机对照、按钮实际边界、权限请求系统日志、真实授权流程均未执行；相关根因推断已明确标注。

## 5. 交付与执行顺序

1. 修复 A1/A2 权限配置与可见错误反馈，在实际 Release 中验证用户主动点击能进入正确授权流程。
2. 按 U2 移除内置节假日和调休兜底，同步 B1/B3 的来源识别及通知恢复；无数据只显示普通日历。
3. 保持字号，处理周起始右对齐、单行日期摘要和统一详情信息行。
4. 量出菜单栏实际间隔，统一两弹窗最终材质观感，提交同条件截图。
5. 修复 B2 行身份问题，补聚合/权限状态回归测试，构建 Release。手动安装、签名身份与覆盖升级授权继承要求继续执行。

实施后逐项给出通过/未通过/未执行；禁止只提交“用了原生组件”“测试全过”来代替用户可见结果。

## 6. 监控弹窗交互补充

2026-09-16 新增用户实测：监控首次打开与再次点击后的外观变化，以及点击其他 App 后不关闭。问题 M1–M3、源码排查线索、单 Release 启动检查范围及完整验收矩阵见 [监控弹窗交互补充验收](validation/MONITOR_POPOVER_REVIEW.md)。本轮未修改应用代码；工具尚未独立复现上述点击行为，不得标为已通过。

## 7. 本次参考图

图片只作问题和目标参考，其中红圈不属于目标 UI，图中文字不作为额外执行指令。

- [图一：设置对齐与权限问题](ui-reference/08-settings-followup.png)
- [图二：当前详情问题](ui-reference/09-calendar-followup.png)
- [图三：详情目标布局](ui-reference/10-calendar-detail-target.png)

![详情目标布局](/Users/wangqing/code/CalMon/docs/ui-reference/10-calendar-detail-target.png)
