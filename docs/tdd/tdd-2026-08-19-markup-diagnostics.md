---
version: v1.0.24
date: 2026-08-19
prd: prd/prd-2026-08-19-markup-diagnostics.md
predecessor:
  - tdd/tdd-2026-08-15-settings-usage-overlay.md
successor:
  - tdd/tdd-2026-08-20-library-cover-translation-retry.md
  - tdd/tdd-2026-08-21-selection-settings-feedback.md
  - tdd/tdd-2026-08-21-markup-interval-merge.md
---

# LumenPDF — 跨页划线与失败诊断 TDD

## 1. 技术结论

跨页标注几何、页眉页脚识别和叠字折叠都放在 UI 无关的 Swift 类型中，便于单测。LLM 空响应分类在翻译错误格式化与 Rust 流式解析两侧对齐用户文案。

## 2. 模块

| 模块 | 职责 |
| --- | --- |
| `PDFSelectionMarkupGeometry.swift` | 按页拆分选区矩形并生成每页 markup。 |
| `SelectionTextOverflowDetector` / 页眉页脚启发式 | 识别相邻页重复出现的页眉页脚（允许页码递增）。 |
| `PDFExtractedTextCollapser.swift` | 把重复叠字折叠成一句再送模型和写日志。 |
| `TranslationErrorFormatter.swift` / LLM translator | 空 body、流式协议、未生成等错误文案。 |
| `GuideConversationPolicy` | 追问串行：进行中禁止发送；空回复记为失败。 |
| `LumenPDFApp.swift` 设置窗口 | 边角缩放、最小尺寸、frame 记忆。 |
| `LLMCallLogStore.swift` | 列表展示截断，按需展开原文。 |

## 3. 关键行为

- 跨页 markup 以 PDF 页为落笔单位，不能把第一页的 bounds 画到第二页。
- 页眉页脚过滤不得误伤页顶正文：必须满足「相邻页相近位置重复」而不是「y 很小」。后续修订：同页小节标题回声过滤见 [tdd-2026-08-21-selection-settings-feedback.md](tdd-2026-08-21-selection-settings-feedback.md)。
- `GuideConversationPolicy` 以会话状态而不是按钮本地 flag 作为发送门闩，避免多入口绕过。

## 4. 验证

- `PDFSelectionMarkupGeometryTests`
- `PDFExtractedTextCollapserTests`
- `GuideConversationPolicyTests`
- 跨页划线、设置窗口缩放需在运行中的 App 验收
