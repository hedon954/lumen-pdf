# LumenPDF Refactor Baseline

- Generated: 2026-07-03T13:30:00Z
- Branch: `codex/lumen-refactor-automation`
- Commit: `4cbd703`

## Summary Metrics

| Metric | Value |
| --- | ---: |
| Swift LOC (excluding Generated) | 7047 |
| Rust LOC | 4057 |
| PDFReaderView.swift LOC | 2125 |
| translation/service.rs LOC | 851 |
| llm_translator.rs LOC | 755 |
| Swift BridgeService.shared references | 36 |
| Swift NotificationCenter post/addObserver references | 28 |
| Swift try? references | 59 |

## Compatibility Fingerprints

| Fingerprint | SHA-256 |
| --- | --- |
| Generated Swift binding | `0d7ee13e2a3243493639ac1df09ae3dccde97726bd80310697fadbae20e75c02` |
| Rust UniFFI public signatures | `32d1a483459a25fe7391365bb0aeb1cedef0dfb4dbfb37a0d1138c20c093aa70` |

## Largest Swift Files

```text
    7047 total
    2125 LumenPDF/Views/PDFReaderView.swift
     511 LumenPDF/Views/SettingsView.swift
     498 LumenPDF/Views/ReadingInspector/ReadingGuidePanel.swift
     492 LumenPDF/Views/TranslationBubble.swift
     413 LumenPDF/Views/VocabularyListView.swift
     328 LumenPDF/Services/BridgeService.swift
     302 LumenPDF/Views/NoteListView.swift
     297 LumenPDF/Views/ContentView.swift
     218 LumenPDF/Views/ReadingInspector/ReadingGuideService.swift
```

## Largest Rust Files

```text
    4057 total
     851 lumen-pdf-core/src/domain/translation/service.rs
     755 lumen-pdf-core/src/infrastructure/translator/llm_translator.rs
     463 lumen-pdf-core/src/infrastructure/translator/streaming.rs
     337 lumen-pdf-core/src/interfaces/api.rs
     198 lumen-pdf-core/src/infrastructure/translator/dictionary_phonetic.rs
     197 lumen-pdf-core/src/infrastructure/db/vocabulary_repo.rs
     156 lumen-pdf-core/src/infrastructure/db/note_repo.rs
     113 lumen-pdf-core/src/infrastructure/db/migration.rs
     111 lumen-pdf-core/src/infrastructure/db/pdf_document_repo.rs
```
