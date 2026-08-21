---
version: unreleased
date: 2026-08-21
tdd: tdd/tdd-2026-08-21-llm-disable-thinking.md
predecessor:
  - prd/prd-2026-03-22.md
  - prd/prd-2026-07-16-llm-configuration-discovery.md
  - prd/prd-2026-08-20-llm-settings-persistence.md
related:
  - prd/prd-2026-08-21-workspace-search.md
---

# LumenPDF — LLM 关闭 thinking PRD

## 1. 产品结论

单词翻译、整句翻译、AI 导读和模型能力探测发出的每一条 chat 请求，都必须**显式关闭 thinking**。用户要的是直接答案，不要先跑一轮隐藏推理。

## 2. 问题

Qwen3、GLM、DeepSeek 等兼容 OpenAI 的接口默认会开 thinking。不关的话，翻译和导读更慢，还可能把推理过程掺进正文或失败诊断。

## 3. 功能需求

### F1 — 所有 LLM 调用都带关闭 thinking

- 单词翻译、句子翻译、AI 导读（含图片追问）、图片能力探测，请求体都显式声明 thinking 关闭。
- 不提供设置项；不能按模型再打开。
- 拉取 `/models` 列表不属于生成调用，不带这些字段。

### F2 — 不认这些字段时仍能调用

- 若服务端因未知字段返回 400，去掉 thinking 相关字段后再试一次，避免 OpenAI 一类严格网关完全不可用。

## 4. 非目标

- 不在界面展示 thinking 开关。
- 不解析或渲染模型的 thinking 过程。
- 不改 MyMemory 兜底翻译。

## 5. 验收标准

1. 抓一条翻译或导读请求，JSON 里能看到 thinking 被关闭。
2. 用默认会思考的模型时，回复不再先空等一段 thinking。
3. 对不接受这些字段的 OpenAI 兼容接口，请求仍能成功，而不是一直 400。
