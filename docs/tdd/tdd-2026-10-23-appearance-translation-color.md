---
version: unreleased
date: 2026-10-23
prd: prd/prd-2026-10-23-appearance-translation-color.md
---

# 主题切换、PDF 深色阅读与翻译颜色设置

## 模块边界

| 模块 | 职责 |
| --- | --- |
| `AppearanceSettings` | 定义浅色、深色、跟随系统三种模式，使用 `UserDefaults` 持久化，并把模式映射到 SwiftUI 的 `ColorScheme` |
| `LumenPDFApp` | 在应用根视图注入外观环境，使主窗口和设置页共享同一套主题状态 |
| `PDFKitView` | 根据当前外观在 PDFKit 页面上添加或移除深色覆盖层；覆盖层使用 `differenceBlendMode` 反色，避免重新绘制 PDF 文本而损失清晰度 |
| `SettingsPages` / `SettingsView` | 提供外观选择与翻译颜色选择器，并复用持久化设置 |
| `TranslationBubble` / `TranslationPopoverChrome` | 读取翻译颜色设置，统一应用到翻译标签、译文和朗读按钮 |

## 状态与持久化

- 外观模式使用一个版本稳定的 `UserDefaults` 键保存，未找到值时默认跟随系统。
- 翻译颜色保存为十六进制 RGBA 字符串；读取失败时回退到系统强调色，首次使用时默认粉色。
- 视图只观察设置对象，不直接修改 PDF 文件或调用外部服务。

## PDF 深色覆盖层

`PDFKitView` 在 PDF 页面视图上方维护一个覆盖层。进入深色外观时，覆盖层填充白色并使用 `differenceBlendMode` 进行反色；退出深色外观时移除覆盖层。覆盖层跟随页面视图尺寸更新，不参与 PDF 文本选择、缩放或标注命中测试。

这样可以保留 PDFKit 原有的矢量文字和选区坐标，同时让白色页面与深色文字转换为适合深色阅读的配色。图片和已有彩色内容仍由 PDFKit 绘制，必要时通过混合模式保持可见。

## 验证

- 使用 `xcodebuild` 构建 `LumenPDF` scheme，确认 Swift 编译和 Xcode 工程文件完整。
- 手动检查浅色、深色和跟随系统三种模式的设置保存与重启恢复。
- 打开包含文本、图片和标注的 PDF，检查深色模式下文字清晰度、缩放、滚动、选区和标注交互。
- 修改翻译颜色后重新打开翻译浮层，检查标签、译文和朗读按钮的颜色及深色背景下的对比度。
