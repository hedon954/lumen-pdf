---
version: v1.0.32
date: 2026-09-10
prd: prd/prd-2026-09-10-reader-open-note-popover.md
predecessor:
  - tdd/tdd-2026-09-01-native-translation-popover.md
  - tdd/tdd-2026-08-20-note-autosave-overlay-stability.md
---

# 系统打开与笔记浮窗实现

## 边界

- `LumenPDFApp` 在主阅读视图用 `onOpenURL` 接收文件事件，`handlesExternalEvents` 优先交给已有窗口；调用统一的 `AppState.openPDF`。
- `AppState` 验证文件并在安全作用域内打开；切换前同步发送保存阅读位置事件，再复用 upsert/selectedDocument 和 `PDFKitView` 的逐文档视口恢复。相同路径仅切回阅读页。旧文档的延迟页码回调仅持久化其自身，不改新文档当前页码。
- `PDFKitView.savePositionNow` 在视口恢复尚未完成时不采集中间几何。文档变化清理笔记草稿、回顾弹窗和旧锚点。
- `ReadingOverlayWindow` 移除 `opaqueChrome` 分支，所有圆角卡片共用 thinMaterial、16pt 圆角、0.5pt/0.08 边框和同一阴影；箭头使用相同材质。三类弹窗全部带箭头，并由同一个根呈现层渲染。
- `NoteReviewPopoverView` 从阅读视图拆出，保留 header/content/footer 组合。快速添加放在 footer，不随长列表滚走；通过窄闭包交给 `AppState`，失败时保留草稿。
- `AppState.appendNoteItem` 从最新 notes 读取并追加，保存后刷新。编辑成功同步刷新 active review，删除也从最新 notes 读取，避免旧快照覆盖已保存修改。
- 自动编辑器可把 lastSavedText 传给保存闭包；`NoteTextList.replacingItem` 可校验原文本和条目数量，拒绝删除或追加导致索引变化后的延迟保存。回顾行身份包含条目数量，结构变动时重建编辑器，防止复用已删除行的本地文本。

## 统一呈现与边界修订

- 原来翻译在根视图、草稿和回顾在 PDF 局部视图，导致可用区域、点外关闭和层级不一致。现在 `ReadingPopoverModel.Presentation` 用枚举持有唯一的翻译/草稿/回顾；`ContentView` 只用一个根 GeometryReader 转换锚点并分发内容。PDFReaderView 仅报告选区、笔记入口与持久化回调，不再持有第二份弹窗状态或绘制局部浮窗。
- 新呈现使用独立 generation，切换内容时重置编辑器和容器测量；更新同一回顾不改变 generation，避免自动保存打断输入。旧翻译结果按请求 ID 拒绝，关闭后的编辑器刷新也不能重开回顾。
- 三类内容都通过 `ReadingOverlayWindow` 绘制相同的圆角卡片与箭头。移除局部透明点击遮罩，复用从选区操作栏提取的 `WindowOutsideClickMonitor`；监听覆盖同窗口的正文、目录、Inspector、toolbar，以及窗外点击，事件原样向下传递。关闭同步发生在本次事件处理之前，避免异步回调误关新浮窗；sheet 在场时暂停外点判断。监听的代表视图卸载即移除事件 token，无独立窗口或 NSHostingView 注入。
- 原文与音标改为一段带不同字体的 Text，自然换行；header/footer 采用固有高度。容器宽度由配置显式控制，不再从上一轮测量宽度扣除箭头反向计算，避免箭头换边后的反馈收缩。
- `NoteAnchorCatalog` 为已保存笔记的每个 page markup 生成入口，并补充可见页面上的自由划线；同一几何已有笔记时避免重复入口。自由划线携带原文和几何用于创建笔记。回顾按 note ID 定位，避免第二页入口被主 pageIndex 过滤掉。
- 迁移保留现有箭头、材质、拖动、内容滚动和尺寸上限；坐标统一为 reader root 后再转 host local。点击、焦点、激活、尺寸变化、关闭和多窗口生命周期按统一容器执行，不持久化瞬时浮层。

## 验证

- `NoteTextListTests` 覆盖修改后删除另一条、删除后继续修改、旧编辑器延迟写入、重复文本的索引变化保护。
- 回归 `TranslationPopoverGeometryTests`、`ReadingOverlayPlacementTests` 与 `ReaderViewportGeometryTests` 的尺寸、箭头和视口算法。
- 使用运行中的 macOS app 检查系统打开事件，以及添加/自动编辑/单条和全部删除完整流程；编译与单元测试不能替代运行时验收。
- 统一展示层需保留点内操作、点外关闭、焦点、选区所有权、唯一实例、滚动缩放关闭翻译、应用激活、窗口移动缩放和 teardown 行为；浅色/深色与分栏边缘需实测。

## 首轮验证记录（统一呈现修订前）

- 本地 `xcodebuild test` 编译成功，36 项定向测试全部通过。原有内容增高测试把 y=486、高度=330 的浮窗要求保留在 800pt 容器中，会越过下边界；断言已修正为遵循现有 12pt 安全边距，布局算法未改。
- 运行最终 Debug 构建，用自建 A/B PDF 实测冷启动指定文件、从单词本切回阅读、A/B 各自第 6 页不同滚动偏移的恢复、重启后的恢复。
- 实测笔记连续追加三条、自动编辑第二条、删除第一条仍保留修改、删除后继续编辑并关闭重开、删除当前选区全部条目及划线。数据库确认测试笔记已清除。
- 浅色外观已对比翻译与笔记背景，并检查翻译选区强调、点内操作和点外关闭。深色启动参数未改变实际系统外观，因此不计为深色证据；深色、完整左右边缘/窗口移动缩放/分栏组合和多显示器仍未完成运行时验收。

## 统一呈现修订验证记录

- 完整应用目标本地构建通过。隔离 QA 宿主编译同一份生产 Swift 源码（仅替换 App 入口，使用内存笔记数据，不初始化凭据或用户数据库）；38 项定向测试通过，包括 model 的互斥/过期结果、笔记条目更新、划线入口、定位和长音标浅深色实际渲染。渲染用例生成图片供人工检查，图片生成成功本身不证明视觉正确。
- 在运行中的 QA 宿主实测：长音标正常换行且无大块空白；翻译、草稿、回顾共用材质及箭头；浅色/深色、左右边界可见；点击内部可以输入，点击正文/左侧栏/右侧栏关闭且原按钮事件生效；工具栏打开另一类弹窗只保留新弹窗；滚动正文、重新选区后旧弹窗消失；移动及调整窗口大小后可重新打开。
- 笔记内存数据实测新增、回顾中快速追加、自动保存修改、单条删除和全部删除。删除确认 sheet 不会触发外点关闭；用户实际数据库的持久化流程沿用首轮证据，尚未在最终完整应用重跑。
- QA 宿主进一步装载实际 `PDFKitView` 和 `NoteAnchorOverlayView`，使用独立测试 PDF：无已保存笔记的自由划线也出现按钮，点击可携带原文打开草稿，滚动和第二次选区关闭旧弹窗。
- 最终完整应用启动停在 `KeychainService.loadLLMAPIKey` 的系统钥匙串访问提示，采样显示主线程等待 `SecItemCopyMatching`；自动操作系统 SecurityAgent 被工具拒绝，未更改凭据或权限。完整应用中的分栏组合、激活/失活、多窗口和显示器变更仍未完成运行时验收，不能用 QA 宿主或构建成功代替。
