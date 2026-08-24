---
version: v1.0.23
date: 2026-08-15
prd: prd/prd-2026-08-15-settings-usage-overlay.md
predecessor:
  - tdd/tdd-2026-08-14-ai-settings-notes.md
  - tdd/tdd-2026-08-09-selection-overlay-placement.md
successor:
  - tdd/tdd-2026-08-19-markup-diagnostics.md
  - tdd/tdd-2026-08-21-llm-call-log-http-request.md
---

# LumenPDF — 用量统计、设置打磨与根层浮窗 TDD

## 1. 技术结论

用量展示和设置反馈留在 Swift。翻译浮窗的展示所有权从 `PDFReaderView` 局部 overlay 提升到 `ContentView` 的阅读窗口根层，与选区操作栏同一坐标空间，避免 `NavigationSplitView` 裁切。

## 2. 模块

| 模块 | 职责 |
| --- | --- |
| `LLMUsageHeatmap.swift` / `LLMCallLogStore.swift` | 26 周日聚合、模型筛选、探测记录过滤。 |
| `LLMConfigurationSection.swift` / `SettingsPages.swift` | 申请入口、验证状态动画、版式压缩。 |
| `ContentView.swift` + `TranslationOverlayModel` | 根层承载 `TranslationBubble`。 |
| `ReadingOverlayWindow` | 手动拖动使用较小安全边距，可到达容器边缘。 |
| `PDFMarkupAppearance` | 下划线颜色固定为 sRGB 红。 |

## 3. 关键行为

- 根层浮窗的 `availableSize` 是阅读窗口，不是 PDF 列；锚点需从 reader 局部转换到根坐标，规则与操作栏相同。
- 调用日志写入时标记请求来源；图片能力探测使用独立来源，列表查询时排除。
- 下划线 appearance 不依赖系统 accent，避免 Dark Mode 或主题变化改成黑色。

## 4. 验证

- `LLMCallLogStoreTests`、`LLMUsageHeatmap` 相关计算若有纯函数测试则覆盖聚合与过滤
- `PDFMarkupAppearanceTests`
- 根层拖动、跨越侧栏、点外关闭必须在运行中的 App 验收
