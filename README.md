# CalMon 开发交接

原生 macOS 27 菜单栏日历与系统监控工具。本仓库提供可执行的产品、技术、UI 和验收规范，以及正式 AppIcon 资源。

## 安装

需要 Apple Silicon Mac 与 macOS 27 或更新版本。

从 [GitHub Releases](https://github.com/MistySky/Calmon/releases) 下载 DMG 后手动安装，或使用 Homebrew：

```sh
brew install --cask mistysky/cnapps/calmon
```

后续更新：`brew update && brew upgrade --cask calmon`。

当前发布采用 ad-hoc 签名，尚未经过 Apple 公证；首次启动可能被 macOS 拦截，需由用户在系统设置中审核允许。安装配置不关闭 Gatekeeper，也不自动移除隔离属性。

## 实施入口

最新问题与验收补充：[UI_REVIEW_FOLLOWUP.md](docs/UI_REVIEW_FOLLOWUP.md)。保留已认可字号；无系统节日数据时显示普通日历，取消内置节假日/调休兜底。先处理该文档的权限和界面未通过项。

本轮首先阅读 [界面调整与功能收敛交接](docs/UI_REFINEMENT.md)：移除内存组成、按软件聚合应用内存、统一弹窗风格、收紧菜单栏与日历布局、改系统日历授权入口。与以下旧规格冲突的部分以该交接为准；该轮及后续修复已实施，见 docs/validation/。

1. 阅读 [AGENTS.md](AGENTS.md)。
2. 按 [产品与技术规格](docs/SPEC.md) 实现功能和模块边界。
3. 按 [UI 规范](docs/UI_SPEC.md) 实现一致的界面。
4. 按 [监控数据规范](docs/MONITORING.md) 实现、校准指标。
5. 按 [验收清单](docs/ACCEPTANCE.md) 提交代码、构建与验证证据。

文档为实施依据，不依赖原型图片、聊天记录或旧方案。应用代码由接手的实施 AI 在用户授权后编写，验收由独立评审执行。交接文档本身不代表实现已完成。

## 产品范围

- 两个独立菜单栏项目：CPU/MEM、日期；左击分别展开监控和月历，右击打开设置菜单。
- 月历包含农历、节气、日期详情；节日与休/班来自系统日历（需授权），无系统数据时显示普通公历/农历月历，不内置节假日/调休。
- 监控包含实时 CPU/内存/启动磁盘容量概况、当前占用圆环和应用内存列表（应用按软件聚合）。
- 无历史监控、趋势图、数据库或第三方依赖；无 Dock 图标。
- CPU/内存每 3 秒更新；逐应用采样仅在监控面板打开时运行。

## 正式资源

[AppIcon 资源包](docs/CalMon_AppIcon_Xcode/README.txt) 包含 macOS AppIcon.appiconset。此资源作为静态应用图标使用，不代表实时监控数值。原型与过程图片不随项目交付。
