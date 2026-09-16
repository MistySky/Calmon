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
  - `GENERATE_INFOPLIST_FILE = YES`，`INFOPLIST_KEY_LSUIElement = YES`
  - `PRODUCT_BUNDLE_IDENTIFIER = com.calmon.CalMon`，`MARKETING_VERSION = 1.3`，`CURRENT_PROJECT_VERSION = 4`
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

可用取值：`monitoring`、`calendar`、`calendar-festival`、`settings`、`menu-monitoring`、`menu-calendar`。启动后约 1.5 秒在 stderr 打印 `CALMON_CAPTURE appearance=... monitorFrame=... calendarFrame=...`。`calendar-festival` 可用 `CALMON_SELECT_DATE=yyyy-MM-dd` 指定日期。

**仅 Debug 的诊断钩子**（已用 `#if DEBUG` 收拢，Release 不包含）：

- `CALMON_CAPTURE=toggle-stress`（50 次开关 + 两轮足迹）
- `CALMON_CAPTURE=monitoring-toggle`（监控开关生命周期）
- `CALMON_CAPTURE=outside-close-check`（失活关闭 + 采样停止）
- `CALMON_CAPTURE` 后的 `CALMON_STATE` 状态行，以及 `CALMON_DUMP_CALENDAR=1` 的来源元数据/事件转储

验证：Release 二进制 `strings` 中不再出现 `CALMON_DUMP`、`CALMON_STATE`、`STRESS`、`MONTOGGLE`、`OUTSIDE`；仅保留 `CALMON_CAPTURE`。

## 6. 产物核验

- `build/Build/Products/Release/CalMon.app/Contents/Info.plist`：`LSUIElement = true`、`CFBundleIdentifier = com.calmon.CalMon`、`CFBundleIconName = AppIcon`、`CFBundleShortVersionString = 1.3`、`LSMinimumSystemVersion = 27.0`。
- `Contents/Resources/` 仅含：`AppIcon.icns`、`Assets.car`、`2025/2026/2027.json`（节气）、`PrivacyInfo.xcprivacy`。不再包含 `CN-*.json`（内置节假日已移除）。没有 `docs/`、原型图或验收日志。
- `codesign -dv`：ad-hoc 签名，`flags=0x10002(adhoc,runtime)`，Release 启用 Hardened Runtime。
- `lipo -archs`：`arm64`。
