---
version: v1.0.37
date: 2026-11-25
prd: prd/prd-2026-11-25-notes-context-grammar.md
predecessor:
  - tdd/tdd-2026-05-06-v105.md
  - tdd/tdd-2026-08-20-note-autosave-overlay-stability.md
  - tdd/tdd-2026-11-23-reader-context-viewport.md
---

# 笔记展示、临时选区、完整语境与语法树

## 技术结论

笔记的阅读态复用已有的 `MarkdownText`，编辑态继续用 `AutoSavingNoteEditor` 写源码。截断来自 `TextField` 的 `lineLimit` 上限，不是外层缺少 `ScrollView`。查词语境改成阅读器通用的两段式：先按行框把软换行拼回段落，再用系统句子边界切句。现有的 `stripEchoedPrefix` 会因为后文又出现同一个词而删掉句首，这条规则退出语境路径。临时选区停止共用已保存高亮的系统黄和正片叠底。语法拆解是一棵一次展开的递归树：先补全残缺选区，再对整句做结构分析，复杂子句用同一规则继续拆。

## 模块边界

| 模块 | 职责 |
| --- | --- |
| `AutoSavingNoteEditor` | 只负责编辑源码、防抖和自动保存。阅读态不再用它当唯一展示。 |
| `MarkdownText` | 渲染笔记正文。发布说明和 AI 解释已经在用。 |
| `ReadingInspectorNoteCard` / `NoteReviewPopoverView` / `NoteCardView` | 未聚焦时渲染 Markdown；聚焦时换成编辑器。正文随内容增高，由所在的列表或浮窗 `ScrollView` 滚到末尾。 |
| `ParagraphJoiner` | 按行框判断软换行、连字符、分栏和标题间隙，拼出段落。 |
| `ReadingSentenceContext` | 在拼好的段落上用 `NLTokenizer` 取包含选中词的句子。半个词先补成行内的完整词，半句补成整句。句子翻译和语法分析用这个结果；页面临时选区仍只画用户选区的行框。 |
| `PDFSelectionHeadingLeakFilter` | 不再对已经拼好的正文句子做前缀删除。页眉页脚仍走 `PDFPageChromeFilter`。 |
| `TranslationSelectionEmphasisView` | 临时选区的浮起外观。不写 PDF 标注，点击穿透。 |
| `PDFHighlightAnnotationFactory` | 已保存高亮继续用系统黄。这里不改。 |
| `SentenceChunk` | 增加 `role`、`explanation` 与 `children`。`original` 是这一层盖住的连续原文。`explanation` 只写一句作用。 |
| `GrammarTree` | 纯函数：丢掉空节点、限制深度、要求子片段落在父片段内。不把扁平列表猜成树，也不补造下一层。 |
| `DEFAULT_SENTENCE_PROMPT_TEMPLATE` 与 `PromptTemplateDefaults` | 同一套树状 JSON。未改过的内置模板随 `templateRevision` 升级；用户改过的模板不静默覆盖。 |

SwiftUI 视图仍不调用 `BridgeService`。笔记存储、高亮合并和单词模式响应结构不变。

## 关键规则

### 笔记阅读态与滚动

Inspector 列表、回顾浮窗和笔记列表今天都把 `AutoSavingNoteEditor` 直接铺在卡片上。`TextField` 的 `lineLimit(min...max)` 到上限后不再长高，外层 `ScrollView` 滚的是卡片，滚不出被裁掉的行。

未聚焦的条目改为 `MarkdownText`。点击该条后挂上现有编辑器；按 `Esc`、点「完成」或失焦时保存并回到渲染结果。编辑器不再设会截断正文的最大行数；内容变高后，Inspector 和笔记列表用现有外层 `ScrollView`，回顾浮窗用 `ReadingOverlayWindow` 里已有的内容 `ScrollView`。不在卡片内再套一层滚动。

导出页继续显示源码。新建草稿仍是源码输入，不在键入时渲染。

### 完整原句

PDF 里没有句子，只有字形和位置。PDFMiner、pdf.js、pdfium 都是同一条路径：先用字框收成视觉行，再判断哪些换行只是排版折行，最后才对拼好的段落做句子边界。句子边界用 Unicode UAX #29；macOS 上对应 `NaturalLanguage.NLTokenizer` 的 sentence，不自己重写这套规则，也不把句子边界交给模型。pd3f 同样先用版面决定折行和连字符，模型只处理少数拿不准的连字符。

`ParagraphJoiner` 只看 `PDFTextLine` 的矩形，阈值相对行高：

- 上下行距约在 0.5 到 1.8 倍行高、字高接近、水平方向有重叠，并且上一行相对同组左缘已经写满时，视为软换行，用空格接上。
- 行末连字符、下一行以小写字母开头时，去掉连字符再拼接。
- 行内出现约 3 倍行高的空隙时视为分栏或表格，不把左右两栏接成一句。
- 行距明显更大，或下一行比正文短得多且不像上一行的续行时，视为另一段或标题，不接进来。

拼好之后，`NLTokenizer` 给出句子区间，取覆盖选中词的那一句。现有「句子过短，或句子从选中词开头，则带上相邻句」留在这一步之后。只按 `.!?` 切开的实现删掉。

锚点是选区矩形相交面积最大的那一行，不用「页面上哪里出现过这段文字」来选行。这一行在拼好的段落里占一段字符区间，选区中心的横坐标落在该行的哪个字符，句子就是盖住这个字符的那一句。同一个词在别的行再出现，也不会被选中。残词只在这一行、这个字符所在的词上补全。`TranslationSelectionEmphasisView` 只画用户选区自己的行框。句子翻译在句子模式下用这一句做请求和缓存键。单词释义只解释选中的那个词。

`stripEchoedPrefix` 用「前缀像标题，且后文包含同一词」删除句首。报告中的原句因此会丢掉 `Engineering`，因为后面有 `engineering capability`。这和「先拼段落、再切句」相反。语境路径不再调用它。跨页重复的页眉页脚继续由 `PDFPageChromeFilter` 按位置去掉。选区字符串里多出来的标题，只有在它自己是一行、并且和正文不是软换行时才排除。

夹具不依赖那份 PDF：

- 报告中的原句，无论写成一行还是句首词单独占一行，语境都含 `Engineering`。
- `Mr. Smith left.` 保持一句。
- 行末 `informa-` / `tion` 拼成 `information`。
- 大间隙标题不进入下一句；左右两栏不拼成一句。

不为某个词或某一页写分支。中文语境只翻译这一句完整原文。

### 临时选区

`TranslationSelectionEmphasisView` 之前把 `PDFHighlightAnnotationFactory.nativeHighlightColor` 填进子图层并用 `multiplyBlendMode`，和已保存高亮视觉相同；后续尝试在透明父层挂 `CALayer` 阴影会被 AppKit 覆盖，手绘黑色加 `destinationOut` 又会在抗锯齿边缘留下一圈灰暗描边。

现在 `TranslationSelectionEmphasisView` 按用户选区的可见行框紧包定位，采用两遍 CoreGraphics 绘制：第一遍在圆角亮黄不透明标牌下投柔和的高斯投影，避免多行选区的投影压到相邻行上；第二遍在标牌裁切区内铺轻微纵向亮黄渐变，并用 `multiply` 混合模式叠加对应 `CGPDFPage` 矢量字形（坐标由 `PDFView.convert(_:from:)` 推出仿射变换，兼容缩放、旋转和 `cropBox` 偏移）。系统选区颜色设为透明，写入选区时通过 `isApplyingTranslationSelection` 与异步复位屏蔽 PDFKit 自身发出的选区与视口通知，避免翻译结果刷新时误关浮窗。视图不接收点击，关闭翻译后移除，不写入标注。已保存高亮仍是 `nativeHighlightColor` 的平铺标注，没有投影。

### 语法树

解析按递归做，展示一次给完。模型在同一次句子响应里返回整棵树，不为下一层再发请求，也不等用户点开。

根是补全后的整句。每个节点有 `role`、`original`、`explanation` 和 `children`。`original` 是这一层盖住的连续原文，包含它的子层。`explanation` 是一句目标语言说明，写这一层在父层中的作用。只有从句、并列、补语这类自身还有结构的部分才继续拆。短句的 `breakdown` 仍为空数组。UniFFI 若拒绝记录递归，改为节点数组加父下标。`templateRevision` 从 2 提到 3，当前内置整句模板登记为旧内置值。

`GrammarTree` 放在 domain：

- 丢掉 `original` 为空的节点。
- 子片段不在父片段内时丢掉该子树。
- 深度超过 4 的子节点丢掉。
- 没有 `children` 的旧缓存保持扁平，不补造父子关系。

`TranslationBubble` 把子节点画在父节点里面。每一层先写角色胶囊，再按顺序写不属于子节点的那些词，词下面是这一层的 `explanation`，子节点插在这些词之间。同一个词不在外层再出现一次。有子节点的层只有一个尖角按钮，不写「展开」「收起」。收起时隐藏子框，这一层的角色、词和说明仍在。初始只展开深度小于 2 的层，整句和主干可见，宾语及其从句收着。框用浅底和细边，沿用现有胶囊，不用编号。浮窗已有的内容滚动负责看完长树。旧的扁平结果仍用现在的编号列表，直到这句被重新翻译。缓存用 `serde(default)` 读取新字段，不迁移旧行。

## 测试与运行时验收

- `ParagraphJoiner`：报告中的原句在单行和句首独占一行时都保留 `Engineering`；行末连字符拼回；大间隙标题不并入；分栏不左右拼接。
- `ReadingSentenceContext`：在已给出的句子区间里选中覆盖选中词的那一句；`Mr. Smith left.` 不被句号截断。半句 `from those that exer` 和半个词都补成所在的整句。
- `GrammarTree`：空节点删除、深度截断、子片段必须落在父片段内、扁平输入保持扁平、简单叶子没有子节点。展示时 `from` 留在两个宾语框之间，从句框在宾语里面。
- 笔记渲染、临时选区的浅色与深色对比、长笔记滚到末尾、真实 PDF 上的句首词，需要在运行中的应用里看。编译和上述纯函数测试不能代替这次外观验收。
