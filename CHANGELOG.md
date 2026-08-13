# Changelog

LumenPDF 的版本记录由人工/AI 维护。每个版本只记录对用户或后续开发有意义的变化，并为具体变更附上对应的 GitHub commit URL。

---
## [1.0.22](https://github.com/hedon954/lumen-pdf/compare/v1.0.21..v1.0.22) - 2026-08-14

这一版把 AI 阅读、LLM 设置和笔记操作串成更可靠的完整流程：解释原文能够自然展开，失败请求可以原位重试，供应商配置会保留各自的 API Key，并新增审计、Token/费用统计与笔记快捷删除。

### 主要变化

- AI 解释中的原文改为独立卡片，只有内容超过最大高度时才显示展开/收起，展开后由正常布局为后续消息腾出空间；LLM 调用失败时会展示具体原因，并可原位重试且用成功结果覆盖失败状态（[1ba719a](https://github.com/hedon954/lumen-pdf/commit/1ba719a87822b1c83a855a45859d905782122350)）。
- 设置页改为系统风格侧边栏，提示词模板使用独立子页并解释所有动态变量；保存前可以校验缺失、未知或不适用的变量，未被用户修改的模板会自动跟随新版系统默认值（[1ba719a](https://github.com/hedon954/lumen-pdf/commit/1ba719a87822b1c83a855a45859d905782122350)）。
- 新增 LLM 调用审计日志、Token 统计和费用估算，记录请求类型、模型、耗时、输入/输出用量及失败原因，便于定位问题和了解使用成本（[1ba719a](https://github.com/hedon954/lumen-pdf/commit/1ba719a87822b1c83a855a45859d905782122350)）。
- 新增 OpenCode Zen 供应商和公开模型目录，并将不同 Base URL 的 API Key 保存在同一个受数据保护的 Keychain 凭据中；来回切换供应商时会自动恢复对应 Key，也会保留本次设置会话中尚未保存的输入（[1ba719a](https://github.com/hedon954/lumen-pdf/commit/1ba719a87822b1c83a855a45859d905782122350)）。
- 笔记弹窗支持直接删除单条笔记或清空当前选区的全部笔记，减少进入右侧笔记页处理的步骤（[1ba719a](https://github.com/hedon954/lumen-pdf/commit/1ba719a87822b1c83a855a45859d905782122350)）。

### 修复

- 修正跨行选区的笔记按钮锚点计算：按 PDF 行序重排选区矩形并使用整组选区边界定位，减少按钮落在图片边缘或错误行上的情况（[1ba719a](https://github.com/hedon954/lumen-pdf/commit/1ba719a87822b1c83a855a45859d905782122350)）。

---
## [1.0.21](https://github.com/hedon954/lumen-pdf/compare/v1.0.20..v1.0.21) - 2026-08-09

这一版统一选区操作栏和笔记等阅读浮层的定位规则，让常用操作默认贴近选区下方，并在空间不足时自动避让，减少遮挡和意外跳位。

### 修复

- 双击单词或拖选句子后，操作栏默认紧贴选区下方；下方空间不足时依次尝试上方、右侧和左侧，大选区无法完全避让时选择遮挡面积最小的位置（[87e8019](https://github.com/hedon954/lumen-pdf/commit/87e801930957fe9e406f293d0b59fe0b04aff567)）。
- 修正根层操作栏的坐标转换和笔记草稿浮层的容器原点，消除操作栏多出一整行间距、笔记窗跳向远处或被裁切的问题；内容高度变化后也会重新评估可用方向（[87e8019](https://github.com/hedon954/lumen-pdf/commit/87e801930957fe9e406f293d0b59fe0b04aff567)）。

### 工程与文档

- 增加选区浮层的方向优先级、最小遮挡、动态尺寸和根坐标转换测试，并补充对应 PRD/TDD，固化统一定位边界（[87e8019](https://github.com/hedon954/lumen-pdf/commit/87e801930957fe9e406f293d0b59fe0b04aff567)）。

---
## [1.0.20](https://github.com/hedon954/lumen-pdf/compare/v1.0.19..v1.0.20) - 2026-08-05

这一版让重新打开文档时更稳定地回到上次阅读的可见位置，并修好翻译等阅读浮层的拖动与关闭体验。

### 修复

- 阅读位置改为优先按页面坐标系中的可视锚点恢复，避免窗口尺寸、分栏宽度和自动缩放变化后，原先按文档高度比例换算出的位置漂移到前几页；布局稳定前会持续对齐，用户主动滚动或显式跳转时立即交还控制权（[b885f21](https://github.com/hedon954/lumen-pdf/commit/b885f2144a48a22508a7ccd0280502fa6efe97a0)）。
- 修复阅读浮层无法点击关闭、无法点外关闭的问题：浮层改为按卡片实际尺寸放置，不再让铺满阅读区的空点击手势吞掉事件；同时把四向箭头做成真正的拖动手柄，缩放热区下移以免盖住关闭按钮（[28e1e7c](https://github.com/hedon954/lumen-pdf/commit/28e1e7cd01e35301c2f243214285ad89ac5288a0)）。

### 主要变化

- 翻译、笔记草稿和笔记回顾浮层统一提供可按住拖动的移动手柄，遮挡正文时可直接挪开（[28e1e7c](https://github.com/hedon954/lumen-pdf/commit/28e1e7cd01e35301c2f243214285ad89ac5288a0)）。

### 工程与文档

- 补充阅读位置锚点恢复与浮层拖动/关闭的 PRD/TDD，并增加 `ReaderViewportGeometry` 与 `PDFViewport` 兼容性的单元测试（[b885f21](https://github.com/hedon954/lumen-pdf/commit/b885f2144a48a22508a7ccd0280502fa6efe97a0)，[0c9298b](https://github.com/hedon954/lumen-pdf/commit/0c9298b13ed370e5d9118094af6368d633e1ccab)）。

---
## [1.0.19](https://github.com/hedon954/lumen-pdf/compare/v1.0.18..v1.0.19) - 2026-07-16

这一版完善 AI 辅助阅读链路：单词解释增加独立词源内容，追问支持原图多模态输入，并让不同 LLM 厂商和模型的配置、发现与切换更加顺手。

### 主要变化

- 将单词解释中的词源或历史故事升级为独立、可选且可持久化的小块；内置提示词采用版本化升级，未修改的旧模板自动更新，用户自定义内容继续保留，并通过新的缓存作用域避免复用旧解释（[000f914](https://github.com/hedon954/lumen-pdf/commit/000f914188346068d20ad843fb36f2006182dc0b)）。
- AI 追问支持直接发送未经压缩的原始图片，并通过模型目录元数据和轻量探测判断多模态能力；只有明确不支持图片时才禁用上传，其他错误继续交由模型侧返回（[000f914](https://github.com/hedon954/lumen-pdf/commit/000f914188346068d20ad843fb36f2006182dc0b)）。
- 内置常见 LLM 厂商及 Base URL，可从兼容的 `/models` 接口获取、搜索和选择模型，同时记住用户使用过的自定义地址与模型，减少重复配置（[000f914](https://github.com/hedon954/lumen-pdf/commit/000f914188346068d20ad843fb36f2006182dc0b)）。

### 修复与体验

- 修复跨页或页面交界处选区无法显示操作栏的问题，并将 AI 追问输入改为最多十行的自然增长编辑器，校正光标、占位文字和附件按钮的布局（[cb99a50](https://github.com/hedon954/lumen-pdf/commit/cb99a5063db48faea4e104f486e4bf34772cc93b)）。

### 工程与文档

- 补充阅读 AI 输入与 LLM 配置发现的 PRD/TDD，并要求后续 PR 使用唯一、语义化且带时间戳的分支名，避免并行任务使用通用分支发生冲突（[000f914](https://github.com/hedon954/lumen-pdf/commit/000f914188346068d20ad843fb36f2006182dc0b)，[311f38f](https://github.com/hedon954/lumen-pdf/commit/311f38fc6a403a0066f793bf5f885534c7472e4f)）。

---
## [1.0.18](https://github.com/hedon954/lumen-pdf/compare/v1.0.17..v1.0.18) - 2026-07-14

这一版优化右侧阅读栏的开关与宽度调整体验，让正文缩放和侧栏拖拽更连贯，同时继续保持当前页和可见阅读位置。

### 修复

- 将右侧阅读栏的打开和关闭改为连续宽度过渡，并由 PDFKit 在布局变化期间统一维护完整视口，避免延迟纠偏造成正文缩放或滚动跳闪（[16e181a](https://github.com/hedon954/lumen-pdf/commit/16e181a9d3d5986f0ab940ef7f76ed910a1a3e67)）。
- 将分界线拖拽中的临时宽度与持久化状态分离，消除 Inspector 逐帧失效及 PDFKit 缩放、主动滚动之间的反馈抖动，松手后仍精确恢复阅读位置（[44301b3](https://github.com/hedon954/lumen-pdf/commit/44301b3e2652b49d2f1916a95c763e29ca101ead)）。

---
## [1.0.17](https://github.com/hedon954/lumen-pdf/compare/v1.0.16..v1.0.17) - 2026-07-14

这一版恢复非容器数据目录，升级后继续直接读取既有的 SQLite 数据库和阅读偏好，避免出现空白的新数据视图。

### 修复

- 移除发布包和 Xcode 工程的 App Sandbox 配置；最终签名不再附加 Sandbox entitlement，使应用继续使用 `~/Library/Application Support/LumenPDF` 与全局 `UserDefaults` 中的既有数据（[2344e26](https://github.com/hedon954/lumen-pdf/commit/2344e2632eb936c1231b5ddb5046f7512288f503)）。

---
## [1.0.16](https://github.com/hedon954/lumen-pdf/compare/v1.0.15..v1.0.16) - 2026-07-14

这一版聚焦阅读现场的连续性：选区操作更可靠，重新打开或最小化后尽可能恢复上次的窗口、视口和阅读工作区布局。

### 主要变化

- 重构文本选区操作栏：根据可用空间避让正文和左右侧栏、在侧栏之上显示、使用透明背景，并在点击其他位置、滚动或缩放后统一关闭，避免浮层残留或遮挡阅读内容（[392dde5](https://github.com/hedon954/lumen-pdf/commit/392dde5032a95ad9b015998d5ef429b9b77d06e1)）。
- 增加完整阅读现场恢复：记住窗口位置和尺寸、PDF 缩放与视口、左右侧栏的显示状态和实际宽度；最小化与退出后重新打开均优先还原这些状态（[4afd8e0](https://github.com/hedon954/lumen-pdf/commit/4afd8e0e7aa360602c522284a60a2fdd627624aa)，[b7b5b36](https://github.com/hedon954/lumen-pdf/commit/b7b5b36b9f33968904ee947dad0afa5043d90395)，[c24e2c9](https://github.com/hedon954/lumen-pdf/commit/c24e2c9bdec2b523e930ac7b49a96a3edab10b9b)，[f79c3b1](https://github.com/hedon954/lumen-pdf/commit/f79c3b13f835bc7d82ac776e9b95febecf4d5517)，[acf4bbd](https://github.com/hedon954/lumen-pdf/commit/acf4bbd0d42dda933913c3c73af0d8216a79c277)）。

### 修复与发布

- 调整 Keychain 存储与签名策略，避免重装时的无效 ACL 访问授权提示；本地和 Release 打包保留 ad-hoc 路径，并确保导出应用的 App Sandbox entitlement 被正确校验（[acf4bbd](https://github.com/hedon954/lumen-pdf/commit/acf4bbd0d42dda933913c3c73af0d8216a79c277)，[8365630](https://github.com/hedon954/lumen-pdf/commit/8365630e4f5f9a11129d18ee289e0aa7e2307d5f)）。
- 对齐发布 tag 摘要与 GitHub Release 页面，并更新提交信息约束，保证发布记录保持面向读者且可追溯（[adbc126](https://github.com/hedon954/lumen-pdf/commit/adbc12649af8e99ba40145ee3c6454805946d686)，[398fb95](https://github.com/hedon954/lumen-pdf/commit/398fb95c3b0c0cea68be16dfa58de9b0be6b442b)）。

---
## [1.0.15](https://github.com/hedon954/lumen-pdf/compare/v1.0.14..v1.0.15) - 2026-07-11

这一版集中修复翻译与笔记浮层在长内容、选区避让和窗口定位上的交互问题，并补齐右侧阅读工作区的笔记与单词管理能力。

### 主要变化

- 将翻译和笔记浮层统一到共用窗口逻辑：浮层随内容自适应增长，最大高度限制为 PDF 阅读器窗口的 80%，超过后改为内部滚动，同时保持选区避让和生成前后位置稳定（[d5f758c](https://github.com/hedon954/lumen-pdf/commit/d5f758c0ce67cc57657b889af94f2c6be9faa01d)，[8fa440d](https://github.com/hedon954/lumen-pdf/commit/8fa440df685f52c8a1fa1aca06fe7534fb78cee3)）。
- 完善右侧阅读工作区：单词和笔记支持删除，笔记内容为空时禁止提交，并恢复页面返回后的快捷操作提示及右侧笔记联动（[8fa440d](https://github.com/hedon954/lumen-pdf/commit/8fa440df685f52c8a1fa1aca06fe7534fb78cee3)）。

### 修复

- 消除词汇编辑保存时未显式处理可选返回值的 Swift 编译警告，保持原有保存交互不变（[9838ef9](https://github.com/hedon954/lumen-pdf/commit/9838ef9a1c0607b478ca98d638c93fb716dd4e02)）。

### 工程与发布

- 发布收尾改为手写维护，GitHub Release 直接读取 `CHANGELOG.md` 中对应版本段落，不再由 git-cliff 自动生成和回写发布记录（[d033dd2](https://github.com/hedon954/lumen-pdf/commit/d033dd22af97588eaae317d9df42a476319a9ee3)，[4a5c10c](https://github.com/hedon954/lumen-pdf/commit/4a5c10c105beec60472927ea5f98d00d98e31b80)）。
- 将发布指南统一为 `release-tag` skill，并通过 `.cursor/skills` 向 Codex 和 Claude 共享同一份仓库级定义，减少多工具间的重复维护（[21267ef](https://github.com/hedon954/lumen-pdf/commit/21267efccaa22e764a6227f6b53cceb61b17cb85)，[5f755ab](https://github.com/hedon954/lumen-pdf/commit/5f755ab221621434e383af9d6c4689d99334c983)）。

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
