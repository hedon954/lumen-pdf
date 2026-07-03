# Changelog

LumenPDF 的版本记录由人工/AI 维护。每个版本只记录对用户或后续开发有意义的变化，并为具体变更附上对应的 GitHub commit URL。

---
## [Unreleased](https://github.com/hedon954/lumen-pdf/compare/v1.0.14..HEAD)

### 工程与发布

- 发布收尾流程改为手写维护：移除 git-cliff 配置和自动 changelog 回写，GitHub Release 改为读取 `CHANGELOG.md` 中对应版本段落，并新增 `.cursor/skills/lumenpdf-release-wrapup` 作为版本收尾指南（[d033dd2](https://github.com/hedon954/lumen-pdf/commit/d033dd22af97588eaae317d9df42a476319a9ee3)）。

---
## [1.0.14](https://github.com/hedon954/lumen-pdf/compare/v1.0.13..v1.0.14) - 2026-07-03

### 主要变化

- 精简阅读器和验证流程，为后续 Swift/Rust 重构后的维护留出更清楚的边界（[f5d8d01](https://github.com/hedon954/lumen-pdf/commit/f5d8d0126e834145d92d4bb71d88c88338dc2aa7)，[c49a91f](https://github.com/hedon954/lumen-pdf/commit/c49a91f2c73ea6fb1f20413c4d64c403afc8694c)）。

### 工程与文档

- 删除临时重构报告，避免计划文档继续污染正式发布资料（[793a18a](https://github.com/hedon954/lumen-pdf/commit/793a18ad8e25ffc23454adb2accfc9eb3243a850)）。

---
## [1.0.13](https://github.com/hedon954/lumen-pdf/compare/v1.0.12..v1.0.13) - 2026-07-03

### 主要变化

- 将阅读导读移入右侧 Reading Inspector，让上下文、笔记和 AI 导读成为阅读器内的稳定工作区（[3cf1cf7](https://github.com/hedon954/lumen-pdf/commit/3cf1cf7f41a4bc478174eabfc68a9e9e89abc851)，[96ce3f7](https://github.com/hedon954/lumen-pdf/commit/96ce3f7b4609151bb56d5baae83f0707fc2022c3)）。

### 修复

- 优化导读失败状态，并让 LLM 配置修改后立即生效（[d4427fd](https://github.com/hedon954/lumen-pdf/commit/d4427fd12d41ebeebe2a4450ee72f02f370fe652)，[a12ff08](https://github.com/hedon954/lumen-pdf/commit/a12ff081e2cf2f87e6681f694fdc176341bcc74c)）。

### 工程与文档

- 补充 Reading Inspector PRD/TDD、实现原则和仓库级工程设计约束（[66998b7](https://github.com/hedon954/lumen-pdf/commit/66998b748080355767e978284274d7301405ce74)，[91a9643](https://github.com/hedon954/lumen-pdf/commit/91a964338f3ead04c2d6f1604f80806623fe9d76)，[ab520b9](https://github.com/hedon954/lumen-pdf/commit/ab520b92ec10b422ff88b1de0b217ad61fc3b461)）。

---
## [1.0.12](https://github.com/hedon954/lumen-pdf/compare/v1.0.11..v1.0.12) - 2026-07-03

### 主要变化

- 增加阅读上下文侧栏，把单词、笔记和 AI 导读串成阅读时可回看的上下文工作流（[59ec108](https://github.com/hedon954/lumen-pdf/commit/59ec1088fdfef0b6cf76584c07d34f412ec70fe2)，[87a7c7f](https://github.com/hedon954/lumen-pdf/commit/87a7c7f329c37f5d031f2139709734612dd3ad94)）。
- 增加划线笔记输入、追加笔记列表，并按选区聚合笔记，保留列表跳转和时间线语义（[b645862](https://github.com/hedon954/lumen-pdf/commit/b645862b9603feb0f6068c948648dfbb37a748c0)，[b4d971b](https://github.com/hedon954/lumen-pdf/commit/b4d971bf2aee7cac822ec538a6ee98a51f3a593d)，[f30e0f5](https://github.com/hedon954/lumen-pdf/commit/f30e0f58d4ceb0fea5ef973670cf37e75a837577)）。
- 支持多轮 AI 追问、聊天式渲染、流式消息跟踪和单条 AI 回复保存（[872e36b](https://github.com/hedon954/lumen-pdf/commit/872e36b8a99c2b2c3103a0fc13b05d40ccfe608c)，[5fc5e40](https://github.com/hedon954/lumen-pdf/commit/5fc5e4012e524bfc13f33f48454740737568aaf0)，[a475e2b](https://github.com/hedon954/lumen-pdf/commit/a475e2b639028c24aa9e426a34a253afb8bb948d)，[40576b0](https://github.com/hedon954/lumen-pdf/commit/40576b0bf8a641e6c6178fae89a8f2663a227af4)）。

### 修复

- 恢复划线合并语义，分离划线和笔记动作，并同步侧栏滚动和精确追加笔记（[7d5c4a0](https://github.com/hedon954/lumen-pdf/commit/7d5c4a08c6ffafcd8c15cb2ef0752f188c82cd40)，[2e271f5](https://github.com/hedon954/lumen-pdf/commit/2e271f52b55afe059c263a8492f8d588da7fdd26)，[fd095a6](https://github.com/hedon954/lumen-pdf/commit/fd095a6e66f44041e8148a7a08876dafaa13ebd4)）。
- 改进导读聊天窗口、内容对比度、输入框聚焦、删除按钮和 resize 热区（[6093651](https://github.com/hedon954/lumen-pdf/commit/60936515e61a8e86507ac80f4de6a64720bb606b)，[e027467](https://github.com/hedon954/lumen-pdf/commit/e0274672f268c3570ae6fb4b6f399b377b8ff1c5)，[ebd0886](https://github.com/hedon954/lumen-pdf/commit/ebd08865cc49002ed522d5a92b2acf7175353f5a)，[afc80ba](https://github.com/hedon954/lumen-pdf/commit/afc80baa54ccfe4c413eb2667b213c30f4bf15ae)）。
- Keychain 存储改为跨安装稳定，并避免重装后无意义的访问授权提示（[00af93a](https://github.com/hedon954/lumen-pdf/commit/00af93ae4026bf74e480ec3f591be31e6952e68c)，[8056757](https://github.com/hedon954/lumen-pdf/commit/80567574cc1eebd06cb23a3ef4da76775f542936)）。

### 工程与文档

- 更新 README、阅读上下文文档和提交信息规范，并发布 1.0.12 版本号（[131493a](https://github.com/hedon954/lumen-pdf/commit/131493ab64c17ec86d628fc15d14f1e628b0a43d)，[a685722](https://github.com/hedon954/lumen-pdf/commit/a685722942886ad7afd9e4f39206c96c3278f2bf)，[fbff3b6](https://github.com/hedon954/lumen-pdf/commit/fbff3b6cdd1d0870b5ddb3e13b87c2822bfaedd4)，[350f687](https://github.com/hedon954/lumen-pdf/commit/350f6873468208cccedb0e07e135da72b5ebc60d)）。

---
## [1.0.11](https://github.com/hedon954/lumen-pdf/compare/v1.0.10..v1.0.11) - 2026-07-01

### 主要变化

- 解释浮窗支持更稳的尺寸约束、聚焦提示、语言提示词模板和提交流程（[c991aa6](https://github.com/hedon954/lumen-pdf/commit/c991aa6b219baf7876e4944db75ecde203680531)，[a39e2e9](https://github.com/hedon954/lumen-pdf/commit/a39e2e9c9fad843e356925a6a11f4f4e3ab7a8c0)，[d739bd6](https://github.com/hedon954/lumen-pdf/commit/d739bd696a0c72c36b6ff3fe5d87491860652191)，[781be42](https://github.com/hedon954/lumen-pdf/commit/781be42f6e3f0b741505dc09871a1452c2c45106)，[6824c27](https://github.com/hedon954/lumen-pdf/commit/6824c27e5650c08c1716362d15d55703eb21087d)）。

### 修复

- 修复语言提示词切换，并同步目标语言与范围翻译缓存，避免跨语言或跨范围复用错误结果（[d15d56e](https://github.com/hedon954/lumen-pdf/commit/d15d56e737cb2292a37f097e931455a6a1f87513)，[8dda856](https://github.com/hedon954/lumen-pdf/commit/8dda8567ce6c9a2936ddb174f4fd3154f79c11c3)）。

### 工程与文档

- 汇总 v1.0.11 PR，记录动态窗口尺寸控制和解释流程调整（[8922340](https://github.com/hedon954/lumen-pdf/commit/8922340845d901948c0427066d3c25e7ac88c63d)，[9252f4b](https://github.com/hedon954/lumen-pdf/commit/9252f4b51a3674c085807fe987fb147e09a984f3)）。

---
## [1.0.10](https://github.com/hedon954/lumen-pdf/compare/v1.0.9..v1.0.10) - 2026-06-25

### 主要变化

- 打磨翻译/解释浮窗尺寸和 README，使本地升级、阅读浮窗和笔记体验更清楚（[6e1be22](https://github.com/hedon954/lumen-pdf/commit/6e1be222511fc3739cf2aaddebb1464a549b23f6)，[2934d53](https://github.com/hedon954/lumen-pdf/commit/2934d531a66cc05b1196ea3cc59d529110358466)）。

### 文档

- 简化 README，保留产品入口和关键使用说明（[383e7b1](https://github.com/hedon954/lumen-pdf/commit/383e7b14fc34968fafba210af0164b6bd511bedd)）。

---
## [1.0.9](https://github.com/hedon954/lumen-pdf/compare/v1.0.8..v1.0.9) - 2026-06-25

### 主要变化

- 解释体验升级为可流式输出、可配置提示词并支持 Markdown 渲染，逐步切换到 Textual 渲染栈（[58a1f91](https://github.com/hedon954/lumen-pdf/commit/58a1f91564f47a29ec7694f1beaf26aad57f1d0b)，[a6678e4](https://github.com/hedon954/lumen-pdf/commit/a6678e41408908c9dffde6508f7d0c7edd3e6a1e)，[d8135c6](https://github.com/hedon954/lumen-pdf/commit/d8135c61969dbea1d54b3d105f5675717a081800)，[dec4786](https://github.com/hedon954/lumen-pdf/commit/dec4786d7e59919d219093ac42d755eaa31e2a98)，[4d30090](https://github.com/hedon954/lumen-pdf/commit/4d300907478ba4efe8f3170cd5635eed0e54de69)）。
- 发布本地升级和笔记打磨版本，并对齐 Textual 的部署目标要求（[95ff230](https://github.com/hedon954/lumen-pdf/commit/95ff230b0754225f4a40f8f7a6f666f844f1e0ad)，[bb8255b](https://github.com/hedon954/lumen-pdf/commit/bb8255b20c5a06c7338c96417a0949963f058ae2)）。

### 修复

- 保留解释 Markdown 间距，并继续优化翻译浮窗尺寸（[ece0e6c](https://github.com/hedon954/lumen-pdf/commit/ece0e6c08e9b4dd43128058e938a916636790598)，[51ae378](https://github.com/hedon954/lumen-pdf/commit/51ae3784a02e245bc6ebf3bde5f8626a13871147)）。

---
## [1.0.8](https://github.com/hedon954/lumen-pdf/compare/v1.0.7..v1.0.8) - 2026-06-08

### 修复

- 修复原生高亮颜色、开关、持久化和已保存词汇识别，解决重开 PDF 后高亮恢复和词汇去重问题（[aa3679a](https://github.com/hedon954/lumen-pdf/commit/aa3679ad4e6d0f99c2730f9c9b76cd1edc0836a7)，[102d083](https://github.com/hedon954/lumen-pdf/commit/102d083728950d67f0c72a76a4cbcfe3962bedf5)）。

---
## [1.0.7](https://github.com/hedon954/lumen-pdf/compare/v1.0.6..v1.0.7) - 2026-06-08

### 修复

- 高亮标注改用 macOS 原生 PDF markup 语义，改善和 Preview 的显示一致性（[12edb5e](https://github.com/hedon954/lumen-pdf/commit/12edb5edc0a0705c4bddcf330b5d82651b1ffd31)）。

---
## [1.0.6](https://github.com/hedon954/lumen-pdf/compare/v1.0.5..v1.0.6) - 2026-06-08

### 主要变化

- 单词音标接入免费 Dictionary API，为单词翻译补充更可靠的美式 IPA 来源（[3efc761](https://github.com/hedon954/lumen-pdf/commit/3efc76160572a0b1f0ecd3d7c852a9a3b827b7ec)，[e0eef29](https://github.com/hedon954/lumen-pdf/commit/e0eef29abf2081cc9e329db6e77fc4941745ee05)，[f5e3ac8](https://github.com/hedon954/lumen-pdf/commit/f5e3ac8ef96b7c4470e025c1329557a7acfde0e3)）。

---
## [1.0.5](https://github.com/hedon954/lumen-pdf/compare/v1.0.4..v1.0.5) - 2026-05-06

### 主要变化

- 在 v1.0.4 的流式翻译基础上，细化句子流式输出和结构分析，帮助用户理解长句翻译过程（[a61e6ce](https://github.com/hedon954/lumen-pdf/commit/a61e6ce38091f94a24626a21d8fd3e26f399e672)）。

### 文档

- 增加 v1.0.4 流式翻译 PRD/TDD，为后续句子流式 refinement 提供设计上下文（[c664dcc](https://github.com/hedon954/lumen-pdf/commit/c664dcccaed86705a9f016384351b5157177e94d)）。

---
## [1.0.4](https://github.com/hedon954/lumen-pdf/compare/v1.0.3..v1.0.4) - 2026-05-06

### 主要变化

- 实现单词和句子翻译的流式输出，让翻译结果可以更早呈现在气泡中（[1c8c868](https://github.com/hedon954/lumen-pdf/commit/1c8c8683cdee67494db479deb666f370691f128c)）。

### 工程

- 复用翻译器 HTTP client，并更新相关文档，减少连接开销和重复实现（[3d196e5](https://github.com/hedon954/lumen-pdf/commit/3d196e55a5abec626b45584ad6ccedd3598c782c)）。

---
## [1.0.3](https://github.com/hedon954/lumen-pdf/compare/v1.0.2..v1.0.3) - 2026-03-31

### 主要变化

- 增加划线笔记合并和撤销支持，让重叠选区可以合并为一条更稳定的笔记记录（[7f7195a](https://github.com/hedon954/lumen-pdf/commit/7f7195a0a1f835b1cd2228a650b705b8866c4167)）。
- 增加数据库 schema 迁移指南，优化划线颜色，并支持将句子翻译保存到笔记（[fae8d6d](https://github.com/hedon954/lumen-pdf/commit/fae8d6d8f2b6442ae095c04b778c7fdaad9668d9)）。

### 修复

- 持续调校划线颜色和开关逻辑，使划线笔记更易识别，也能点击同一选区取消（[fcb261a](https://github.com/hedon954/lumen-pdf/commit/fcb261ab60eac22b9fe460a84d136a56f145013e)，[fc6ae1e](https://github.com/hedon954/lumen-pdf/commit/fc6ae1e17da5cadb4d785ca2a48ccf8a7e86bc42)，[c3c2989](https://github.com/hedon954/lumen-pdf/commit/c3c29892aedbc3741906ce66a2dfb7729a1d047b)，[dc5dd89](https://github.com/hedon954/lumen-pdf/commit/dc5dd89922402f33bb302750d04751629dadc6f4)）。

---
## [1.0.2](https://github.com/hedon954/lumen-pdf/compare/v1.0.1..v1.0.2) - 2026-03-30

### 主要变化

- 增加笔记、句子翻译和多项阅读体验优化，包括 LLM 错误展示、PDF annotation 持久化、划线笔记和句子翻译模式（[5bcf1fa](https://github.com/hedon954/lumen-pdf/commit/5bcf1fa01413ae1076f41c2a59a59efbfb86d864)）。

---
## [1.0.1](https://github.com/hedon954/lumen-pdf/compare/v1.0.0..v1.0.1) - 2026-03-29

### 工程

- 更新应用图标并重新生成 Xcode 项目引用，为后续正式打包准备资源（[6e85b14](https://github.com/hedon954/lumen-pdf/commit/6e85b143b068f6612324220abc26c403082f71d7)）。

---
## [1.0.0] - 2026-03-27

### 主要变化

- 初始化项目并实现 Rust DDD 后端、SwiftUI/PDFKit 前端和 UniFFI 桥接的 MVP（[f375e05](https://github.com/hedon954/lumen-pdf/commit/f375e0513c9fa2106f262c5be38805aa2b8073fa)，[7632b8e](https://github.com/hedon954/lumen-pdf/commit/7632b8eab0a6c64c9657d92723fb4c0d60a20910)，[54ca7ca](https://github.com/hedon954/lumen-pdf/commit/54ca7ca1454236851d89fb4296d1338ff9aae2b3)，[a8e3170](https://github.com/hedon954/lumen-pdf/commit/a8e31700154ea6d7cbdbf8921f838dda0564cf8b)）。
- 完成早期 PDF 阅读、选区操作、词汇管理、上下文句子翻译、标注、阅读位置持久化和 LLM 热更新能力（[0b758e2](https://github.com/hedon954/lumen-pdf/commit/0b758e2faf815c2cedf37c8543e7f2bf08f190c6)，[44d03c3](https://github.com/hedon954/lumen-pdf/commit/44d03c3eef44a2b8fa85f5ff641a81df98a09bbd)，[1083c30](https://github.com/hedon954/lumen-pdf/commit/1083c3055efb498ca4a8cd7c9be81260c080d630)，[3aa9776](https://github.com/hedon954/lumen-pdf/commit/3aa9776a6aca5c524903bcbd3a9128402eabfded)，[8c50cff](https://github.com/hedon954/lumen-pdf/commit/8c50cff6549bd4ba735c1cce729e7a1fec9cd26d)）。
- 增加 DMG 打包、应用图标、CI 发布流程和 pre-commit 基础设施，并将项目从 ReflectPDF 重命名为 LumenPDF（[03a9cb6](https://github.com/hedon954/lumen-pdf/commit/03a9cb67b6b232df5fa3c0a6db860546acd9d4d3)，[78808ea](https://github.com/hedon954/lumen-pdf/commit/78808ea044bc432acc0e4e122d7ab755804ac4eb)，[9d977a7](https://github.com/hedon954/lumen-pdf/commit/9d977a784739897e0b791daadb729f943905aaff)，[350b648](https://github.com/hedon954/lumen-pdf/commit/350b648a5fc03da450608a4214eb66de7654de48)，[76ef48f](https://github.com/hedon954/lumen-pdf/commit/76ef48f220d59517f19d0eca8600e360785b27c6)）。

### 修复

- 修复 Rust dylib 打包、翻译错误状态刷新、Gatekeeper 说明和 CI 打包细节，保证早期 DMG 能在其他机器上运行并输出可调试日志（[68207dd](https://github.com/hedon954/lumen-pdf/commit/68207dd2e3eba6a67cb05ef818c4855a7a002354)，[7370f0f](https://github.com/hedon954/lumen-pdf/commit/7370f0f0033305a640084248a342693b3c309c9e)，[5b966a4](https://github.com/hedon954/lumen-pdf/commit/5b966a4bb9660e239061ee858e46a626f2758c53)，[a114225](https://github.com/hedon954/lumen-pdf/commit/a1142257994bea666be0ba6a416963bc4f5129a3)）。
