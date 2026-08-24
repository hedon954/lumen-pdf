---
version: unreleased
date: 2026-08-24
tdd: tdd/tdd-2026-08-24-codebase-simplification.md
predecessor:
  - prd/prd-2026-03-31.md
  - prd/prd-2026-07-04-v1014-refactor-automation.md
---

# LumenPDF — 内部去重与死代码清理 PRD

## 1. 产品结论

阅读、翻译、笔记、单词、设置与调用日志的用户可感知行为不变。本迭代只删除未使用的实现、合并重复辅助逻辑，让后续改动落在更少的入口上。

## 2. 问题

代码量主要来自平行封装和已弃用路径：未调用的 PDF 文件标注写入、bounds 解析两套实现、删除笔记/单词时重复的数据库 + 标注通知、设置里 Extra Config 与提示词校验的复制粘贴。这些不会改变产品能力，但会让下一次迭代同时改好几处。

## 3. 用户可感知行为

无变化。打开 PDF、划线笔记、翻译浮窗、设置保存、调用日志状态展示仍按既有规则工作。

## 4. 非目标

- 不重写阅读窗口、Inspector 或 Swift/Rust 分层。
- 不合并 Extra Config 的 Swift/Rust 双端规则。
- 不删除仍被 Swift 使用的 UniFFI 导出。
- 不把 `ReaderPersistence` 并入 `BridgeService`。

## 5. 验收标准

- 笔记删除仍会去掉对应下划线；单词删除仍会去掉对应高亮。
- 从笔记列表或单词本跳转到原文，仍先打开对应文档再定位页码。
- Extra Config 为空时，运行时仍使用当前服务商的关 thinking 默认值；用户写了 JSON 对象则按原样使用。
- 设置页提示词校验仍同时检查 User Prompt 与 System Prompt。
