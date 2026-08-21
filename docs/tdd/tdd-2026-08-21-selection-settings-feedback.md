---
version: unreleased
date: 2026-08-21
prd: prd/prd-2026-08-21-selection-settings-feedback.md
predecessor:
  - tdd/tdd-2026-08-19-markup-diagnostics.md
  - tdd/tdd-2026-08-20-llm-settings-persistence.md
---

# LumenPDF — 选区标题误入与设置保存反馈 TDD

## 1. 技术结论

PDFKit 的 `selection.string` 和按行子串匹配会把附近小节标题收进选区，尤其当标题词组又出现在正文里。用 UI 无关的 `PDFSelectionHeadingLeakFilter` 在 markup 与句子提取之后去掉这类回声标题。设置保存成败只更新设置页保存栏；Keychain 失败文案由 `KeychainSaveFailureMessage` 映射，不再 `showToast`。

## 2. 模块

| 模块 | 职责 |
| --- | --- |
| `PDFSelectionHeadingLeakFilter` | 去掉标题行/标题前缀，当其规范化文本已出现在同一次选中的正文中。 |
| `PDFSelectionTextMatcher.matchingLines` | 子串匹配之后再跑上述过滤，避免标题因正文复述而被标成选中。 |
| `PDFSelectionMarkupGeometry.make` | chrome 过滤之后、拼接选区文本之前去掉回声标题。 |
| `PDFKitView` 选区/`extractSentence` | 折叠叠字后再过滤，避免上下文句子吞进上一节标题。 |
| `KeychainSaveFailureMessage` | 把常见 `OSStatus` 映射成可读中文，不输出状态码。 |
| `SettingsSaveFeedback` | 统一设置保存失败文案。 |
| `SettingsView.saveBar` | 成功/失败都只显示在底部保存栏。 |

## 3. 选区过滤

```text
selectionsByLine / matchingLines
  → 页眉页脚 chrome 过滤
  → stripEchoedHeadings（标题词组已在其余行中出现则丢弃）
  → 拼接文本后再 stripEchoedPrefix（同一行粘连的标题前缀）
```

只删除「像标题」且被其余正文复述的片段：无句末标点、不超过 8 个词、以字母开头。正文未复述该标题时保留。

## 4. 设置保存反馈

```text
保存设置失败
  → SettingsSaveFeedback.message
  → saveErrorMessage 显示在保存栏
  → 提示词错误时切到提示词分页
  → 不调用 AppState.showToast
```

`errSecMissingEntitlement`（`-34018`）映射为无法访问钥匙串、建议重新安装；解锁相关状态映射为先解锁 Mac。成功路径同样不再 toast「LLM 配置已生效」。

## 5. 验证

- `PDFSelectionMarkupGeometryTests`：正文复述标题词组时不匹配标题行；粘连前缀被去掉；未复述的标题保留。
- `KeychainItemQueryTests`：`-34018` 文案不含状态码；`SettingsSaveFeedback` 使用钥匙串/校验文案。

本环境无法运行 macOS App。选区高亮与设置窗口保存栏的观感、点击路径必须在运行中的 App 验收；编译不能代替这项验收。
