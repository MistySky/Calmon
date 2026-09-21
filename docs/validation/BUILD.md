# BUILD — 构建与运行

本文件记录从干净检出构建、测试和运行 CalMon 的确切步骤，以及本次验收使用的工具链和签名配置。

## 1. 工具链与环境

| 项目 | 值 |
|---|---|
| Mac 型号 | MacBookPro18,1 |
| 芯片 | Apple M1 Pro |
| 逻辑核心 | 10（8 性能核 + 2 能效核） |
| 物理内存 | 34359738368 bytes = 32 GiB |
| 系统页大小 | 16384 bytes |
| macOS | 27.0 (build 26A428) |
| Xcode | 27.0 (build 27A266a) |
| Swift | 6.4 (swiftlang-6.4.0.34.1, clang-2100.3.34.1) |
| SDK | macOS 27.0 |
| 架构 | arm64（thin） |
| 部署目标 | macOS 27.0 |
| 显示 | 内置 3456×2234 Retina（主屏，2x）；外接 3840×2160 |
| 活动监视器刷新间隔 | 系统默认 |

## 2. 目录与工程

- 单一 App target `CalMon`，加一个单元测试 target `CalMonTests`。没有 framework、Swift Package 或第三方二进制。
- 工程文件 `CalMon.xcodeproj/project.pbxproj` 使用显式文件清单（objectVersion 56），构建时会随文件变动同步。
- 共享 scheme：`CalMon`（`CalMon.xcodeproj/xcshareddata/xcschemes/CalMon.xcscheme`），包含 `CalMon` 与 `CalMonTests`。
- 关键构建设置：
  - 全局快捷键使用系统框架 Carbon/HIToolbox 的 `RegisterEventHotKey`/`UnregisterEventHotKey` + `InstallEventHandler`（`kEventHotKeyExclusive`）；Carbon 随系统提供，不是第三方依赖，未链接自定义二进制。
  - `GENERATE_INFOPLIST_FILE = YES`，`INFOPLIST_KEY_LSUIElement = YES`
  - `PRODUCT_BUNDLE_IDENTIFIER = com.calmon.CalMon`，`MARKETING_VERSION = 2.0`，`CURRENT_PROJECT_VERSION = 10`
  - `MACOSX_DEPLOYMENT_TARGET = 27.0`，`SWIFT_VERSION = 5.0`，`SWIFT_STRICT_CONCURRENCY = minimal`
  - Debug：`ENABLE_HARDENED_RUNTIME = NO`；Release：`ENABLE_HARDENED_RUNTIME = YES`
  - 签名：应用 target `CODE_SIGN_STYLE = Manual`、`CODE_SIGN_IDENTITY = "CalMon Self-Signed"`（自签名证书，稳定身份）；entitlement 声明 `com.apple.security.app-sandbox = false` 与 `com.apple.security.personal-information.calendars = true`（Hardened Runtime 下访问日历所需）。详见 [SIGNING.md](SIGNING.md)。

## 3. 从干净检出构建

前置：安装 Xcode 27（含 macOS 27 SDK），命令行工具指向该 Xcode。

```sh
cd /Users/wangqing/code/CalMon

# Debug（含单元测试）
xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Debug \
  -derivedDataPath build test

# Release
xcodebuild -project CalMon.xcodeproj -scheme CalMon -configuration Release \
  -derivedDataPath build build
```

两者都应输出 `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **`。本次执行前先确认 `CalMon.xcodeproj` 与 `CalMon/`、`CalMonTests/` 均在版本库内容中，无本地未跟踪依赖。

## 4. 运行

用户交付流程为 DMG 手动安装和手动启动；构建命令不自动安装或运行。以下是开发诊断的显式运行方式，不是构建后的自动步骤。本轮修复未执行这些启动命令。

Release 产物：

```
build/Build/Products/Release/CalMon.app
```

常规运行（脱离调试器）：

```sh
open build/Build/Products/Release/CalMon.app
```

或直接启动可执行文件（本次性能测量使用该方式，便于读取 PID）：

```sh
build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
```

退出：点击任一状态栏项目右键 → “退出”。App 为 `LSUIElement`（无 Dock 图标、无主窗口）。

## 5. 验收专用捕获钩子

在无法合成鼠标点击的机器上（本次 `AXIsProcessTrusted=false`），通过环境变量一次性打开目标界面以便截图/测量。该变量正常使用时不设置，默认完全不触发。

**Release 保留的最小 UI 捕获钩子**（截图与弹窗测量必需）：

```sh
CALMON_CAPTURE=monitoring        build/Build/Products/Release/CalMon.app/Contents/MacOS/CalMon
```

可用取值：`monitoring`、`calendar`、`calendar-festival`、`settings`、`panel`、`panel-scaled`、`menu-monitoring`、`menu-calendar`。启动后约 1.5 秒在 stderr 打印 `CALMON_CAPTURE appearance=... monitorFrame=... calendarFrame=...`。`calendar-festival` 可用 `CALMON_SELECT_DATE=yyyy-MM-dd` 指定日期。

`panel` 打开快捷键面板并打印 `CALMON_PANEL frame=... contentView=... safeArea=... storedScale=...`；`panel-scaled` 先写入 1.25 比例再打开（会持久化 `calendar.panel.scale`，测量后应还原/删除该键）。`settings` 会额外打印一行 `CALMON_SETTINGS calendar=... hotKey=... access=...`。

面板捕获附加变量：

| 变量 | 作用 |
|---|---|
| `CALMON_PANEL_HOLD=1` | 长时间测量时保持面板可见（该诊断路径同时关闭“失焦即关”），正常使用不设置 |
| `CALMON_PANEL_SIZE=WxH` | 应用精确内容尺寸（含非基准中间尺寸），不写偏好 |
| `CALMON_SELECT_DATE=yyyy-MM-dd` | 捕获前选中指定日期 |
| `CALMON_YEAR_JUMP=+1/-2/...` | 调用与年份按钮相同的模型入口，跳转后捕获 |
| `CALMON_SEARCH=<text>` | 监控面板捕获时展开搜索并填入查询 |
| `CALMON_SETTINGS_RECORD=1` | 设置捕获时进入“请按快捷键…”录制态 |
| `CALMON_SETTINGS_ERROR=<text>` | 设置捕获时注入错误说明行文案 |

Debug 构建另打印 `CALMON_PANEL_GEOMETRY container=... scale=...`，用于核对内容比例由真实容器尺寸推导。

注意：快捷键面板是 `.floating` 层级，`screencapture` 可直接截到；设置窗口是普通层级，本机 `NSApp.activate` 受限（macOS 14+ 不再支持忽略前台应用激活），自动截图可能拍到未活动态外观，需人工复核活动态。

**仅 Debug 的诊断钩子**（已用 `#if DEBUG` 收拢，Release 不包含）：

- `CALMON_CAPTURE=toggle-stress`（50 次开关 + 两轮足迹）
- `CALMON_CAPTURE=monitoring-toggle`（监控开关生命周期）
- `CALMON_CAPTURE=outside-close-check`（失活关闭 + 采样停止）
- `CALMON_CAPTURE` 后的 `CALMON_STATE` 状态行，以及 `CALMON_DUMP_CALENDAR=1` 的来源元数据/事件转储

验证：Release 二进制 `strings` 中不再出现 `CALMON_DUMP`、`CALMON_STATE`、`STRESS`、`MONTOGGLE`、`OUTSIDE`；仅保留 `CALMON_CAPTURE`。面板/设置诊断只在 `CALMON_CAPTURE` 分支内执行，纯输出、不改变产品行为。（注意 Swift 会把 ≤15 字节的字面量内联，`CALMON_PANEL ` 等短前缀不一定出现在 `strings` 输出中，不能据此判断缺失。）

## 5.1 打包 DMG（发布步骤）

```sh
rm -rf /tmp/calmon-2.0 && mkdir -p /tmp/calmon-2.0
cp -R build/Build/Products/Release/CalMon.app /tmp/calmon-2.0/
xattr -cr /tmp/calmon-2.0/CalMon.app
codesign --verify --deep --strict /tmp/calmon-2.0/CalMon.app
hdiutil create -volname "CalMon 2.0" -srcfolder /tmp/calmon-2.0 -ov -format UDZO dist/CalMon-2.0.dmg
shasum -a 256 dist/CalMon-2.0.dmg
hdiutil verify dist/CalMon-2.0.dmg
```

DMG 内只含 `CalMon.app`。`dist/CalMon-2.0.dmg` sha256 = `3b50964d1ede4660f5d4b86fce84537af0243b81cc39bdd61f399a37e2740a6e`，并同步到 GitHub Release 与 Homebrew Cask。

## 6. 产物核验

- `build/Build/Products/Release/CalMon.app/Contents/Info.plist`：`LSUIElement = true`、`CFBundleIdentifier = com.calmon.CalMon`、`CFBundleIconName = AppIcon`、`CFBundleShortVersionString = 2.0`、`CFBundleVersion = 10`、`LSMinimumSystemVersion = 27.0`。
- `Contents/Resources/` 仅含：`AppIcon.icns`、`Assets.car`、`2025/2026/2027.json`（节气）、`PrivacyInfo.xcprivacy`。不再包含 `CN-*.json`（内置节假日已移除）。没有 `docs/`、原型图或验收日志。
- `codesign -dvvv --entitlements -`：自签名证书 `CalMon Self-Signed` 签名（`flags=0x10000(runtime)`，Release 启用 Hardened Runtime），日历 entitlement 存在；`codesign -d -r-` 输出 `designated => identifier "com.calmon.CalMon" and certificate leaf = H"349e8a9ea8645dfefc587ef5ddaa1fb23b447473"`，与 1.6 相同。该证书未加入系统信任，`codesign --verify --deep --strict` 会返回 `CSSMERR_TP_NOT_TRUSTED`，属于现有自签名分发限制，不写作严格信任校验通过。详见 [SIGNING.md](SIGNING.md)。
- `lipo -archs`：`arm64`。
