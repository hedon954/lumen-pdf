---
version: v1.0.23
date: 2026-08-15
tdd: tdd/tdd-2026-08-15-settings-usage-overlay.md
predecessor:
  - prd/prd-2026-08-14-ai-settings-notes.md
  - prd/prd-2026-08-09-selection-overlay-placement.md
  - prd/prd-2026-08-05-viewport-restore-overlay-drag.md
successor:
  - prd/prd-2026-08-19-markup-diagnostics.md
  - prd/prd-2026-08-21-llm-call-log-http-request.md
  - prd/prd-2026-09-01-native-translation-popover.md
---

# LumenPDF — 用量统计、设置打磨与根层浮窗 PRD

## 1. 产品结论

v1.0.23 打磨设置可用性，并把翻译浮窗提升到阅读窗口根层，使其可以跨越 PDF、目录和 Inspector 拖动，而不被分栏裁切。Token 与费用页增加按天、按模型的用量热点图。后续修订：翻译继续在根层锚定选区并允许手动拖动，外观改为 Look Up 式实色浮窗，见 [prd-2026-09-01-native-translation-popover.md](prd-2026-09-01-native-translation-popover.md)。

## 2. 功能需求

### F1 — Token 热点图与调用日志

- 最近 26 周按日汇总调用次数、Token 与估算费用，可按模型筛选。
- 调用日志改为更易扫描的状态列表和请求/响应详情。后续修订：详情增加可展开的完整 HTTP 请求，见 [prd-2026-08-21-llm-call-log-http-request.md](prd-2026-08-21-llm-call-log-http-request.md)。
- 内部图片能力探测不得出现在用户可见日志里。

### F2 — 设置反馈

- 每个内置服务商提供官方 API Key 申请入口。
- 压缩顶部留白、去掉重复标题；提示词验证结果显示在变量说明与编辑器之间。
- 验证按钮用进度、成功、失败状态给出明确反馈。

### F3 — 翻译浮窗根层

- 翻译浮窗从 PDF 列提升到阅读窗口根层，可跨越侧栏拖动。后续修订：根层继续直接承载翻译浮层，以实色箭头锚定黄色选区并保留自定义拖动，见 [prd-2026-09-01-native-translation-popover.md](prd-2026-09-01-native-translation-popover.md)。
- 保存到单词本/笔记、删除、关闭的既有联动保持不变。
- 手动拖动可到达窗口四周，不受自动避让安全边距限制。

### F4 — 下划线外观

- PDFKit 下划线统一为 sRGB 红色，新建、恢复、撤销或重建后不得变成黑色。

## 3. 验收标准

1. Token 页能按模型过滤，并看到按日色块与汇总数字。
2. 调用日志没有图片探测产生的无意义条目。
3. 翻译浮窗可拖到左侧目录或右侧 Inspector 上方，仍能保存、删除和关闭。
4. 手动拖动可贴到窗口边缘。
5. 下划线在撤销/重做后仍为红色。
