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
successor:
  - prd/prd-2026-08-21-llm-json-repair.md
  - prd/prd-2026-08-21-llm-extra-config.md
---

# LumenPDF — LLM 关闭 thinking PRD

## 1. 产品结论

单词翻译、整句翻译、AI 导读和模型能力探测发出的每一条 chat 请求，都必须**按服务商**关闭 thinking。用户要的是直接答案，不要先跑一轮隐藏推理。不要把各家字段一次性全塞进请求。

## 2. 问题

Qwen3、GLM、DeepSeek 等兼容 OpenAI 的接口默认会开 thinking。把 `enable_thinking`、`chat_template_kwargs`、`thinking.type` 三条一起带上，严格网关会 400；重试时若把真正管用的字段也剥掉，Qwen 就会继续思考。

## 3. 功能需求

### F1 — 按服务商带关闭字段

- 单词翻译、句子翻译、AI 导读（含图片追问）、图片能力探测都关闭 thinking。
- 只带当前 Base URL / 模型对应的那一套字段：
  - 阿里云百炼、硅基流动、以及阿里内部 OpenAI 兼容网关（如 IdeaLab / `alibaba-inc.com`）：`enable_thinking: false`
  - 自建 vLLM / SGLang 上的 Qwen：`chat_template_kwargs.enable_thinking: false`
  - DeepSeek、智谱、火山方舟：`thinking.type: disabled`
  - OpenRouter：`reasoning.enabled: false`
  - OpenAI、Gemini：不带扩展字段
- Qwen 系模型额外在最后一条用户消息末尾加 `/no_think`，避免只认模板软开关的网关漏关。
- 不提供 thinking 开关。后续修订：用户可通过 Extra Config 自行补厂商字段（含覆盖 `enable_thinking`），见 [prd-2026-08-21-llm-extra-config.md](prd-2026-08-21-llm-extra-config.md)。
- 拉取 `/models` 列表不属于生成调用，不带这些字段。

### F2 — 不认这些字段时仍能调用

- 若服务端因未知字段返回 400，去掉 thinking 相关字段后再试一次，避免 OpenAI 一类严格网关完全不可用。

## 4. 非目标

- 不在界面展示 thinking 开关。
- 不解析或渲染模型的 thinking 过程。
- 不改 MyMemory 兜底翻译。
- 不保证 thinking-only 模型（无法关闭推理的型号）也能关掉。

后续修订：期望 JSON 的模型输出在解析前做 json repair，见 [prd-2026-08-21-llm-json-repair.md](prd-2026-08-21-llm-json-repair.md)。

## 5. 验收标准

1. 百炼或 IdeaLab + Qwen 的请求 JSON 只有 `enable_thinking: false`，没有另外两条 thinking 字段，用户消息以 `/no_think` 结尾。
2. 用默认会思考的 Qwen 时，回复不再先空等一段 thinking。
3. 对不接受这些字段的 OpenAI 兼容接口，请求仍能成功，而不是一直 400。
