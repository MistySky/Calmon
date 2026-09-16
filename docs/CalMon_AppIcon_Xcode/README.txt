CalMon 正式应用图标资源

使用方式：
1. 复制 AppIcon.appiconset 到 CalMon/Resources/Assets.xcassets/。
2. 在 App target 中将 App Icons Source 设为 AppIcon。
3. 构建后验证 Finder、系统设置等位置的图标显示。

内容：
- CalMon-AppIcon-1024.png：1024 × 1024 主图。
- AppIcon.appiconset：macOS 16/32/128/256/512 pt 的 1x/2x PNG 和 Contents.json。
- AppIcon.iconset：供标准 macOS iconset 工作流使用的尺寸资源。

保留本目录源图，复制到应用目录使用，不覆盖源文件。
图标中的 CPU/MEM 数字和图形为静态装饰，不实时更新。
图标资源不代表菜单栏布局或监控图表样式；按 docs/UI_SPEC.md 实现界面。
