# LumenPDF — 优化需求技术实现文档 (TDD)

**版本**: v1.0.2 · **日期**: 2026-03-30

---

## 1. 需求概述

本次优化包含 8 个功能点，分为三个模块：

| 编号 | 需求                        | 模块         | 优先级 |
| ---- | --------------------------- | ------------ | ------ |
| O1   | LLM 翻译错误信息完整显示    | 翻译错误处理 | 高     |
| O2   | LLM + 兜底双重错误同时显示  | 翻译错误处理 | 高     |
| O3   | PDF 标注持久化到 PDF 元数据 | PDF 标注系统 | 高     |
| O4   | 笔记功能 + Markdown 导出    | 笔记系统     | 中     |
| O5   | 句子翻译（非单词纠正）      | 翻译逻辑     | 中     |
| O6   | 选词操作栏按钮增大          | UI 优化      | 低     |
| O7   | 目录栏支持隐藏              | UI 优化      | 低     |
| O8   | 单词本切换时保持文件名显示  | UI 优化      | 低     |

---

## 2. 翻译错误处理优化 (O1, O2)

### 2.1 问题分析

**当前行为**：

- LLM 失败后，Rust 层捕获错误信息存入 `llm_error_message`
- Fallback 成功时，UI 显示 LLM 错误信息（已实现）
- Fallback **也失败**时，Rust 返回整体错误，Swift 侧只显示一个错误信息

**期望行为**：

- O1: LLM 失败 → Fallback 成功：显示 LLM 错误 + Fallback 翻译结果 ✓（已实现）
- O2: LLM 失败 → Fallback 失败：显示**两个**错误信息（LLM 错误 + Fallback 错误）

### 2.2 技术方案

#### 2.2.1 Rust 层改动

**修改 `TranslationResult` 结构体**（`lumen-pdf-core/src/domain/translation/entity.rs`）：

```rust
#[derive(Debug, Clone, Default, uniffi::Record, serde::Serialize, serde::Deserialize)]
pub struct TranslationResult {
    pub word: String,
    // ... existing fields ...
    pub source: String,
    /// LLM 错误信息（非空表示 LLM 步骤失败）
    #[serde(default)]
    pub llm_error_message: String,
    /// 【新增】兜底翻译错误信息（非空表示 Fallback 步骤失败）
    #[serde(default)]
    pub fallback_error_message: String,
    /// 【新增】是否为完全失败（两者都失败）
    #[serde(default)]
    pub is_complete_failure: bool,
}
```

**修改 `TranslationDomainService::translate`**（`lumen-pdf-core/src/domain/translation/service.rs`）：

```rust
pub async fn translate(
    &self,
    request: TranslationRequest,
) -> Result<TranslationResult, LumenError> {
    let word_lower = request.word.to_lowercase();
    let hash = Self::sentence_hash(&request.sentence);

    // Level 1: local cache
    if let Some(mut cached) = self.cache.get(&word_lower, &hash)? {
        cached.source = TranslationSource::Cache.to_string();
        return Ok(cached);
    }

    // Level 2: LLM
    let llm_error: Option<String> = match self.llm.translate(&request.word, &request.sentence).await {
        Ok(mut result) => {
            result.source = TranslationSource::Llm.to_string();
            let _ = self.cache.set(&word_lower, &hash, &result);
            return Ok(result);
        }
        Err(e) => Some(e.user_hint_zh()),
    };

    // Level 3: fallback
    let fallback_result = self.fallback.translate(&request.word, &request.sentence).await;

    match fallback_result {
        Ok(mut result) => {
            result.source = TranslationSource::Fallback.to_string();
            result.llm_error_message = llm_error.unwrap_or_default();
            result.fallback_error_message = String::new();
            result.is_complete_failure = false;
            Ok(result)
        }
        Err(fallback_err) => {
            // 【关键改动】不再抛出错误，而是返回带双错误信息的结果
            Ok(TranslationResult {
                word: request.word.clone(),
                source: "failed".to_string(),
                llm_error_message: llm_error.unwrap_or_default(),
                fallback_error_message: fallback_err.user_hint_zh(),
                is_complete_failure: true,
                ..Default::default()
            })
        }
    }
}
```

#### 2.2.2 Swift 层改动

**修改 `TranslationBubble.swift` 错误显示区域**：

```swift
// MARK: - Error display section

@ViewBuilder
private func errorSection(result: TranslationResult) -> some View {
    // LLM 错误（即使是 fallback 成功也显示）
    if !result.llmErrorMessage.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
            Label("LLM 调用失败", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)
            Text(result.llmErrorMessage)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // 【新增】兜底翻译错误（仅当完全失败时显示）
    if !result.fallbackErrorMessage.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
            Label("兜底翻译失败", systemImage: "xmark.octagon.fill")
                .font(.caption.bold())
                .foregroundStyle(.red)
            Text(result.fallbackErrorMessage)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .padding(12)
        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // 【新增】完全失败提示
    if result.isCompleteFailure {
        Text("所有翻译途径均失败，请检查网络连接和 LLM 设置")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
    }
}
```

### 2.3 测试用例

```rust
#[tokio::test]
async fn both_llm_and_fallback_fail_returns_error_info() {
    let cache = FakeCache::new();
    let svc = TranslationDomainService::new(
        cache,
        Arc::new(FailingLlm), // LLM 失败
        Arc::new(FailingFallback), // Fallback 也失败
    );

    let result = svc.translate(TranslationRequest {
        word: "test".to_string(),
        sentence: "test sentence".to_string(),
    }).await.unwrap();

    assert!(result.is_complete_failure);
    assert!(!result.llm_error_message.is_empty());
    assert!(!result.fallback_error_message.is_empty());
    assert_eq!(result.source, "failed");
}
```

---

## 3. PDF 标注持久化 (O3)

### 3.1 macOS PDF 标注机制分析

**macOS Preview / PDFKit 标注存储方式**：

PDF 标注（Highlight、Underline、Note）存储在 PDF 文件的元数据层，符合 Adobe PDF Specification：

- Annotation 对象嵌入 PDF 页面的 `/Annots` 数组
- 每个 Annotation 包含：`/Type /Annot`、`/Subtype`（Highlight/Underline）、`/Rect`（位置）、`/Color`、`/Contents`（备注）、`/T`（作者）
- 标注持久化后，任何 PDF 阅读器都能解析并显示

**PDFKit API**：

- `PDFAnnotation`：创建和管理标注
- `PDFPage.addAnnotation()`：添加到页面
- `PDFDocument.write(to:)`：保存标注到文件

### 3.2 当前实现问题

当前标注仅在内存中的 `PDFAnnotation` 对象存在，未调用 `PDFDocument.write(to:)` 保存到文件。

**标注类型区分**：
| 类型 | 当前 userName | 持久化目标 |
|------|--------------|-----------|
| 词汇高亮 | UUID（词汇条目 ID） | 写入 PDF，附带 `/Contents` = `vocab:{id}` |
| 自由高亮 | `"__fh"` | 写入 PDF，附带 `/Contents` = `free:highlight` |
| 自由划线 | `"__fu"` | 写入 PDF，附带 `/Contents` = `free:underline` |

### 3.3 技术方案

#### 3.3.1 新增服务：`AnnotationPersistenceService`

**文件**: `LumenPDF/Services/AnnotationPersistenceService.swift`

```swift
import PDFKit

/// PDF 标注持久化服务：将 Annotation 写入 PDF 文件元数据
class AnnotationPersistenceService {
    static let shared = AnnotationPersistenceService()

    /// 保存标注到 PDF 文件（异步，返回是否成功）
    func saveAnnotations(for document: PDFDocument, filePath: String) async -> Bool {
        guard let url = resolveAccessibleURL(filePath: filePath) else { return false }

        // 使用 Data 写入，避免覆盖原文件的安全问题
        var data = Data()
        guard document.write(to: url) else { return false }
        return true
    }

    /// 从 PDF 文件恢复标注（加载时调用）
    func loadAnnotations(from document: PDFDocument, filePath: String) {
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for ann in page.annotations {
                // 根据 Contents 字段判断标注类型
                parseAnnotationContents(ann, page: pageIndex, filePath: filePath)
            }
        }
    }

    private func parseAnnotationContents(_ ann: PDFAnnotation, page: Int, filePath: String) {
        guard let contents = ann.contents else { return }

        // vocab:{id} → 词汇高亮，写入数据库关联
        if contents.hasPrefix("vocab:") {
            let entryId = contents.dropFirst(6).toString()
            // 更新数据库中的 annotation_id 字段
            try? BridgeService.shared.linkAnnotation(id: entryId, annotationId: ann.userName ?? "")
        }
        // free:highlight / free:underline → 自由标注，已在 PDF 中
    }

    private func resolveAccessibleURL(filePath: String) -> URL? {
        let url = URL(fileURLWithPath: filePath)
        // 尝试直接访问
        if PDFDocument(url: url) != nil { return url }
        // Security-Scoped Bookmark fallback
        if let data = UserDefaults.standard.data(forKey: "bm_\(filePath)") {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: data,
                                       options: .withSecurityScope,
                                       bookmarkDataIsStale: &stale) {
                _ = resolved.startAccessingSecurityScopedResource()
                return resolved
            }
        }
        return nil
    }
}
```

#### 3.3.2 修改标注添加逻辑

**修改 `PDFReaderView.swift` Coordinator**：

```swift
private static func makeAnnotation(bounds: CGRect, type: PDFAnnotationSubtype,
                                   color: NSColor, tag: String, page: PDFPage,
                                   contents: String? = nil) -> PDFAnnotation {
    let ann = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
    ann.color = color
    ann.userName = tag
    ann.contents = contents // 【新增】设置 Contents 用于持久化识别
    page.addAnnotation(ann)
    return ann
}
```

**词汇高亮添加**：

```swift
private func addVocabAnnotation(entryId: String, boundsStr: String, to page: PDFPage) {
    // ... existing code ...
    for rect in lineRects {
        let ann = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
        ann.color = NSColor.systemYellow.withAlphaComponent(0.5)
        ann.userName = entryId
        ann.contents = "vocab:\(entryId)" // 【新增】
        page.addAnnotation(ann)
    }
    // 【新增】触发持久化
    triggerAutoSave()
}
```

**自由标注添加**：

```swift
@objc func addFreeAnnotation(_ notification: Notification) {
    // ... existing code ...
    for rect in lineRects {
        let contents = typeStr == "underline" ? "free:underline" : "free:highlight"
        added.append(Self.makeAnnotation(
            bounds: rect, type: annType, color: color,
            tag: tag, page: page, contents: contents // 【新增】
        ))
    }
    triggerAutoSave()
}
```

#### 3.3.3 自动保存策略

```swift
// Coordinator 内新增
private var saveDebounce: Timer?

private func triggerAutoSave() {
    saveDebounce?.invalidate()
    saveDebounce = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
        guard let self, let pdfView = self.pdfView, let doc = pdfView.document else { return }
        Task {
            await AnnotationPersistenceService.shared.saveAnnotations(
                for: doc, filePath: self.currentFilePath
            )
        }
    }
}
```

#### 3.3.4 文档加载时恢复标注关联

```swift
func updateNSView(_ pdfView: PDFView, context: Context) {
    // ... existing code ...
    context.coordinator.applyHighlights(to: doc, filePath: filePath)

    // 【新增】从 PDF 元数据恢复标注关联
    AnnotationPersistenceService.shared.loadAnnotations(from: doc, filePath: filePath)
}
```

#### 3.3.5 Rust 层数据库改动

**新增字段**（`migration.rs`）：

```sql
ALTER TABLE vocabulary_entries ADD COLUMN annotation_id TEXT DEFAULT '';
ALTER TABLE vocabulary_entries ADD COLUMN annotation_persisted INTEGER DEFAULT 0;
```

**新增 API**（`interfaces/api.rs`）：

```rust
#[uniffi::export]
pub fn link_annotation(id: String, annotation_id: String) -> Result<(), LumenError> {
    // 更新 vocabulary_entries.annotation_id
}
```

### 3.4 注意事项

- **用户确认**：首次保存标注到原文件时，应弹出确认对话框（"标注将写入 PDF 文件，其他阅读器可见"）
- **Undo 支持**：标注的 Undo/Redo 操作后，同样触发自动保存
- **并发安全**：保存操作在后台线程执行，避免阻塞 UI

---

## 4. 笔记功能 (O4)

### 4.1 功能设计

**笔记数据模型**：

| 字段         | 说明                       |
| ------------ | -------------------------- |
| `id`         | UUID                       |
| `pdf_path`   | 来源 PDF 文件路径          |
| `pdf_name`   | PDF 文件名                 |
| `page_index` | 所在页码                   |
| `content`    | 划线的原文内容             |
| `note`       | 用户添加的笔记内容（可选） |
| `created_at` | 创建时间                   |

**笔记卡片视图**：

- 显示划线内容 + 用户笔记
- 支持跳转到原 PDF 位置
- 支持编辑笔记内容

**Markdown 导出格式**：

```markdown
# 笔记导出 - {pdf_name}

---

## Page {page_index}

> {划线内容}

{用户笔记}

---

（重复每个笔记条目）
```

### 4.2 技术方案

#### 4.2.1 Rust 层数据库

**新增表**（`migration.rs`）：

```sql
CREATE TABLE IF NOT EXISTS notes (
    id            TEXT PRIMARY KEY,
    pdf_path      TEXT NOT NULL,
    pdf_name      TEXT NOT NULL,
    page_index    INTEGER NOT NULL,
    content       TEXT NOT NULL,
    note          TEXT NOT NULL DEFAULT '',
    bounds_str    TEXT NOT NULL DEFAULT '',
    created_at    INTEGER NOT NULL
);
```

**新增 Domain 层**（`domain/note/`）：

```rust
// entity.rs
#[derive(Debug, Clone, uniffi::Record)]
pub struct NoteEntry {
    pub id: String,
    pub pdf_path: String,
    pub pdf_name: String,
    pub page_index: u32,
    pub content: String,
    pub note: String,
    pub bounds_str: String,
    pub created_at: i64,
}

// repository.rs
pub trait NoteRepository {
    fn save(&self, entry: &NoteEntry) -> Result<(), LumenError>;
    fn list(&self) -> Result<Vec<NoteEntry>, LumenError>;
    fn delete(&self, id: &str) -> Result<(), LumenError>;
    fn update_note(&self, id: &str, note: &str) -> Result<(), LumenError>;
}
```

**新增 UniFFI API**（`interfaces/api.rs`）：

```rust
#[uniffi::export]
pub fn save_note(...) -> Result<NoteEntry, LumenError>;

#[uniffi::export]
pub fn list_notes() -> Result<Vec<NoteEntry>, LumenError>;

#[uniffi::export]
pub fn delete_note(id: String) -> Result<(), LumenError>;

#[uniffi::export]
pub fn update_note(id: String, note: String) -> Result<(), LumenError>;

#[uniffi::export]
pub fn export_notes_markdown(pdf_path: Option<String>) -> Result<String, LumenError>;
```

#### 4.2.2 Swift 层 UI

**新增视图文件**：

```
LumenPDF/Views/
├── NoteListView.swift       # 笔记列表视图
├── NoteCardView.swift       # 单条笔记卡片
├── NoteEditSheet.swift      # 编辑笔记弹窗
└── NoteExportView.swift     # 导出预览与保存
```

**ContentView 改动**：

```swift
// Toolbar picker 增加「笔记」选项
Picker("", selection: $appState.activeTab) {
    Text("PDF 阅读").tag(MainTab.reader)
    Text("单词本").tag(MainTab.vocabulary)
    Text("笔记").tag(MainTab.notes) // 【新增】
}

// detail 区域增加笔记视图
if appState.activeTab == .notes {
    NoteListView()
}
```

**AppState 改动**：

```swift
enum MainTab {
    case reader
    case vocabulary
    case notes // 【新增】
}

@Published var notes: [NoteEntry] = []

func refreshNotes() {
    notes = (try? BridgeService.shared.listNotes()) ?? []
}
```

**选词操作栏增加「笔记」按钮**：

```swift
// PDFReaderView.swift selectionActionBar
actionBarBtn(icon: "note.text", label: "笔记") {
    saveAsNote(word: sel.word, sentence: sel.sentence,
               boundsStr: sel.boundsStr, page: sel.page)
    pendingSelection = nil
}
```

#### 4.2.3 Markdown 导出实现

```swift
// NoteExportView.swift
struct NoteExportView: View {
    let notes: [NoteEntry]
    @State private var markdownContent: String = ""

    var body: some View {
        VStack {
            TextEditor(text: $markdownContent)
                .font(.body)
                .frame(maxHeight: 400)

            HStack {
                Button("复制到剪贴板") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdownContent, forType: .string)
                }
                Button("保存为文件") {
                    saveToFile()
                }
            }
        }
        .onAppear { generateMarkdown() }
    }

    private func generateMarkdown() {
        markdownContent = BridgeService.shared.exportNotesMarkdown(pdfPath: nil)
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        panel.nameFieldStringValue = "LumenPDF_Notes.md"
        if panel.runModal() == .OK, let url = panel.url {
            try? markdownContent.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
```

---

## 5. 句子翻译优化 (O5)

### 5.1 问题分析

**当前行为**：

- 用户选中一个句子（多个单词），点击「翻译」
- LLM prompt 要求针对 `word`（选中的文本）进行「语境翻译」
- LLM 可能将句子当作单词处理，给出不恰当的「词汇纠正」

**期望行为**：

- 检测选中文本是否为句子（长度 > 某阈值，或包含空格）
- 如果是句子，则请求 LLM 翻译整个句子，而非单词语境解释

### 5.2 技术方案

#### 5.2.1 Swift 层判断逻辑

```swift
// PDFReaderView.swift requestTranslation
private func requestTranslation(word: String, sentence: String, ...) {
    // 判断是否为句子翻译模式
    let isSentenceMode = word.split(separator: " ").count > 3 || word.count > 20

    if isSentenceMode {
        // 句子模式：直接翻译选中内容作为句子
        Task {
            let result = try await BridgeService.shared.translateSentence(
                sentence: word // 选中的完整句子
            )
            // 显示句子翻译气泡
        }
    } else {
        // 单词模式：现有逻辑
        Task {
            let result = try await BridgeService.shared.translate(
                word: word, sentence: sentence
            )
        }
    }
}
```

#### 5.2.2 Rust 层新增句子翻译 API

```rust
// interfaces/api.rs
#[uniffi::export(async_runtime = "tokio")]
pub async fn translate_sentence(sentence: String) -> Result<TranslationResult, LumenError> {
    let svc = get_translation_service()?;

    // 使用专门的句子翻译 prompt
    let prompt = format!(
        "Translate the following English sentence to {}. Provide only the translation, no explanation.\n\nSentence: {}",
        get_target_lang(),
        sentence
    );

    // 调用 LLM（简化版，不需要 word-level 分析）
    let llm_result = svc.llm.translate_sentence(&sentence).await?;

    Ok(TranslationResult {
        word: sentence.clone(),
        context_translation: String::new(),
        context_explanation: String::new(),
        general_definition: String::new(),
        context_sentence_translation: llm_result,
        source: "llm".to_string(),
        ..Default::default()
    })
}
```

#### 5.2.3 LLM Prompt 改动

**单词模式 Prompt**（现有）：

```
You are a translator. For the word "{word}" in the context of the sentence "{sentence}",
provide JSON with: word, phonetic, part_of_speech, context_translation, context_explanation,
general_definition, context_sentence_translation.
```

**句子模式 Prompt**（新增）：

```
You are a translator. Translate the following sentence to {target_lang}.
Provide the translation only, no explanation.

Sentence: {sentence}
```

#### 5.2.4 气泡 UI 改动

```swift
// TranslationBubble.swift
@ViewBuilder
private func contentBody(result: TranslationResult) -> some View {
    // 检测是否为句子翻译模式（word 较长，且其他字段为空）
    let isSentenceOnly = result.word.count > 15
        && result.contextTranslation.isEmpty
        && result.generalDefinition.isEmpty

    if isSentenceOnly {
        // 句子翻译模式：只显示原文和译文
        VStack(alignment: .leading, spacing: 12) {
            BubbleSection("原文") {
                Text(result.word).font(.body)
            }
            BubbleSection("译文") {
                Text(result.contextSentenceTranslation).font(.body)
            }
        }
        .padding(14)
    } else {
        // 单词翻译模式：现有逻辑
        // ... existing code ...
    }
}
```

---

## 6. UI 优化 (O6, O7, O8)

### 6.1 操作栏按钮增大 (O6)

**当前尺寸**：`font(.system(size: 12))`，`padding(.horizontal, 10)`

**改动**（`PDFReaderView.swift`）：

```swift
private func actionBarBtn(icon: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium)) // 增大图标
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 13)) // 增大文字
            }
        }
        .padding(.horizontal, 12)  // 增大水平 padding
        .padding(.vertical, 9)     // 增大垂直 padding
    }
    .buttonStyle(.plain)
    .contentShape(Rectangle())
}

// 整体容器 padding 也增大
private func selectionActionBar(_ sel: SelectionInfo) -> some View {
    HStack(spacing: 0) {
        // ... buttons ...
    }
    .padding(.horizontal, 6)  // 增大
    .padding(.vertical, 6)    // 增大
    .background(.regularMaterial, in: Capsule())
    // ...
}
```

### 6.2 目录栏支持隐藏 (O7)

**改动**（`ContentView.swift`）：

```swift
// 新增状态
@State private var sidebarVisible: Bool = true

// NavigationSplitView 使用动态可见性
NavigationSplitView(columnVisibility: $sidebarVisibility) {
    // ...
}

// 根据状态决定 columnVisibility
private var sidebarVisibility: NavigationSplitViewVisibility {
    sidebarVisible ? .all : .detailOnly
}

// Toolbar 增加「目录」按钮
ToolbarItem(placement: .navigation) {
    Button {
        withAnimation { sidebarVisible.toggle() }
    } label: {
        Label(sidebarVisible ? "隐藏目录" : "显示目录",
              systemImage: sidebarVisible ? "sidebar.left" : "sidebar.right")
    }
}
```

**注意**：`NavigationSplitView.columnVisibility` 在 macOS 13+ 可用，需做版本检查。

### 6.3 单词本切换保持文件名 (O8)

**当前逻辑**（`ContentView.swift`）：

```swift
if appState.activeTab == .reader,
   let fileName = appState.selectedDocument?.fileName {
    // 显示文件名 + 页码
}
```

**改动**：移除 `activeTab == .reader` 条件：

```swift
// 保持显示，不论当前 Tab
if let fileName = appState.selectedDocument?.fileName {
    Divider().frame(height: 14)

    Text(fileName)
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()

    if appState.activeTab == .reader && appState.totalPages > 0 {
        // 页码只在 PDF 阅读模式下显示
        Text("\(appState.currentPageIndex + 1) / \(appState.totalPages)")
            .font(.callout.monospacedDigit())
            .foregroundStyle(.tertiary)
    }
}
```

---

## 7. 实现优先级与依赖关系

```
O1/O2 (翻译错误) ──→ 独立实现，无依赖
O3 (PDF 标注持久化) ──→ 独立实现，需用户确认机制
O4 (笔记功能) ──→ 依赖 O3（标注需要持久化才能关联笔记）
O5 (句子翻译) ──→ 独立实现
O6/O7/O8 (UI 优化) ──→ 独立实现，可合并一个 commit
```

**建议实施顺序**：

1. O1/O2（翻译错误处理）— 核心功能修复
2. O5（句子翻译）— 功能增强
3. O6/O7/O8（UI 优化）— 快速完成
4. O3（PDF 标注持久化）— 需要仔细设计持久化策略
5. O4（笔记功能）— 最后实现，依赖 O3

---

## 8. 测试清单

| 编号 | 测试场景                                        |
| ---- | ----------------------------------------------- |
| O1   | LLM 失败 → Fallback 成功 → UI 显示 LLM 错误信息 |
| O2   | LLM 失败 → Fallback 失败 → UI 显示双重错误信息  |
| O3-1 | 添加标注 → 自动保存 → 重新打开 PDF → 标注可见   |
| O3-2 | 在 Preview.app 打开已保存标注的 PDF → 标注可见  |
| O3-3 | 删除词汇 → 对应标注从 PDF 元数据中移除          |
| O4-1 | 划线 → 点击「笔记」→ 笔记保存成功               |
| O4-2 | 笔记列表 → 点击跳转 → PDF 定位正确              |
| O4-3 | 导出 Markdown → 文件格式正确                    |
| O5-1 | 选单词 → 翻译气泡显示单词分析                   |
| O5-2 | 选句子 → 翻译气泡显示句子译文（无单词分析）     |
| O6   | 选词操作栏 → 点击按钮 → 响应正常，视觉更清晰    |
| O7   | 点击目录按钮 → 目录栏隐藏/显示                  |
| O8   | 切换到单词本 → 文件名保持显示，无跳跃           |

---

## 9. 兼容性考虑

| 功能          | macOS 版本   | 说明                                       |
| ------------- | ------------ | ------------------------------------------ |
| O7 目录栏隐藏 | macOS 13+    | `NavigationSplitView.columnVisibility` API |
| O3 标注持久化 | macOS 10.15+ | PDFKit API 稳定                            |
| 其他          | macOS 13+    | 项目已有最低版本要求                       |

---

## 10. 数据库迁移脚本

```sql
-- v1.0.2 migration
ALTER TABLE vocabulary_entries ADD COLUMN annotation_id TEXT DEFAULT '';
ALTER TABLE vocabulary_entries ADD COLUMN annotation_persisted INTEGER DEFAULT 0;

CREATE TABLE IF NOT EXISTS notes (
    id            TEXT PRIMARY KEY,
    pdf_path      TEXT NOT NULL,
    pdf_name      TEXT NOT NULL,
    page_index    INTEGER NOT NULL,
    content       TEXT NOT NULL,
    note          TEXT NOT NULL DEFAULT '',
    bounds_str    TEXT NOT NULL DEFAULT '',
    created_at    INTEGER NOT NULL
);
```

---

## 11. 文件变更清单

### 新增文件

| 文件                                                   | 说明                  |
| ------------------------------------------------------ | --------------------- |
| `lumen-pdf-core/src/domain/note/mod.rs`                | 笔记 Domain 模块      |
| `lumen-pdf-core/src/domain/note/entity.rs`             | 笔记实体定义          |
| `lumen-pdf-core/src/domain/note/repository.rs`         | 笔记 Repository trait |
| `lumen-pdf-core/src/infrastructure/db/note_repo.rs`    | 笔记 SQLite 实现      |
| `lumen-pdf-core/src/application/note/mod.rs`           | 笔记 Application 层   |
| `lumen-pdf-core/src/application/note/use_case.rs`      | 笔记用例              |
| `LumenPDF/Services/AnnotationPersistenceService.swift` | 标注持久化服务        |
| `LumenPDF/Views/NoteListView.swift`                    | 笔记列表视图          |
| `LumenPDF/Views/NoteCardView.swift`                    | 笔记卡片组件          |
| `LumenPDF/Views/NoteEditSheet.swift`                   | 笔记编辑弹窗          |
| `LumenPDF/Views/NoteExportView.swift`                  | Markdown 导出视图     |

### 修改文件

| 文件                                                | 改动点                                               |
| --------------------------------------------------- | ---------------------------------------------------- |
| `lumen-pdf-core/src/domain/translation/entity.rs`   | 新增 `fallback_error_message`、`is_complete_failure` |
| `lumen-pdf-core/src/domain/translation/service.rs`  | 修改降级逻辑，返回双错误信息                         |
| `lumen-pdf-core/src/infrastructure/db/migration.rs` | 新增 notes 表、vocabulary_entries 新字段             |
| `lumen-pdf-core/src/interfaces/api.rs`              | 新增笔记相关 API、句子翻译 API                       |
| `LumenPDF/Generated/lumen_pdf_core.swift`           | UniFFI 自动重新生成                                  |
| `LumenPDF/Views/TranslationBubble.swift`            | 错误显示逻辑、句子翻译 UI                            |
| `LumenPDF/Views/PDFReaderView.swift`                | 标注持久化、笔记按钮、句子判断                       |
| `LumenPDF/Views/ContentView.swift`                  | 目录隐藏、Tab 切换保持文件名                         |
| `LumenPDF/App/AppState.swift`                       | 新增 notes 状态、notes Tab                           |
| `LumenPDF/Services/BridgeService.swift`             | 新增笔记相关调用封装                                 |
