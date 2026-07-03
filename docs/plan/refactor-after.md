# LumenPDF Refactor After

- Generated: 2026-07-03T17:26:43Z
- Branch: `codex/lumen-refactor-automation`
- Commit: `4cbd703`

## Summary Metrics

| Metric | Value |
| --- | ---: |
| Swift LOC (excluding Generated) | 7653 |
| Rust LOC | 3976 |
| PDFReaderView.swift LOC | 619 |
| translation/service.rs LOC | 850 |
| llm_translator.rs LOC | 709 |
| Swift BridgeService.shared references | 3 |
| Swift NotificationCenter post/addObserver references | 5 |
| Swift try? references | 60 |

## Compatibility Fingerprints

| Fingerprint | SHA-256 |
| --- | --- |
| Generated Swift binding | `0d7ee13e2a3243493639ac1df09ae3dccde97726bd80310697fadbae20e75c02` |
| Rust UniFFI public signatures | `32d1a483459a25fe7391365bb0aeb1cedef0dfb4dbfb37a0d1138c20c093aa70` |

## Largest Swift Files

```text
    7653 total
    1208 LumenPDF/Reader/PDFKitView.swift
     835 LumenPDF/Views/TranslationBubble.swift
     619 LumenPDF/Views/PDFReaderView.swift
     511 LumenPDF/Views/SettingsView.swift
     498 LumenPDF/Views/ReadingInspector/ReadingGuidePanel.swift
     404 LumenPDF/Views/VocabularyListView.swift
     328 LumenPDF/Services/BridgeService.swift
     302 LumenPDF/Views/NoteListView.swift
     301 LumenPDF/Views/ContentView.swift
```

## Largest Rust Files

```text
    3976 total
     850 lumen-pdf-core/src/domain/translation/service.rs
     709 lumen-pdf-core/src/infrastructure/translator/llm_translator.rs
     463 lumen-pdf-core/src/infrastructure/translator/streaming.rs
     325 lumen-pdf-core/src/interfaces/api.rs
     198 lumen-pdf-core/src/infrastructure/translator/dictionary_phonetic.rs
     187 lumen-pdf-core/src/infrastructure/db/vocabulary_repo.rs
     136 lumen-pdf-core/src/infrastructure/db/note_repo.rs
     113 lumen-pdf-core/src/infrastructure/db/migration.rs
     110 lumen-pdf-core/src/infrastructure/db/pdf_document_repo.rs
```
