use crate::application::note::use_case::NoteUseCase;
use crate::application::pdf_document::use_case::PdfDocumentUseCase;
use crate::application::translation::use_case::TranslationUseCase;
use crate::application::vocabulary::use_case::VocabularyUseCase;
use crate::domain::note::entity::{NoteEntry, SaveNoteRequest, UpdateNoteRequest};
use crate::domain::pdf_document::entity::{PdfDocument, UpsertPdfRequest};
use crate::domain::translation::entity::{
    ImageAttachment, ImageInputCapability, TranslationRequest, TranslationResult,
};
use crate::domain::translation::repository::StreamProgress;
use crate::domain::vocabulary::entity::{
    SaveVocabularyRequest, UpdateVocabularyRequest, VocabularyEntry,
};
use crate::error::LumenError;
use crate::infrastructure::db::{self, DbPool};
use crate::infrastructure::db::{
    note_repo::SqliteNoteRepo, pdf_document_repo::SqlitePdfDocumentRepo,
    translation_cache_repo::SqliteTranslationCacheRepo, vocabulary_repo::SqliteVocabularyRepo,
};
use crate::infrastructure::translator::{
    dictionary_phonetic::DictionaryApiPhoneticProvider,
    fallback_translator::FallbackTranslator,
    llm_translator::{LlmConfig, LlmTranslator},
};
use std::sync::{Arc, OnceLock, RwLock};

// ── Global state ────────────────────────────────────────────────────────────

static POOL: OnceLock<DbPool> = OnceLock::new();
// RwLock so the config can be hot-swapped without restarting the app.
static LLM_CONFIG: RwLock<Option<LlmConfig>> = RwLock::new(None);

/// Called once on app launch. Safe to call again — the DB pool is only created
/// once; calling again only updates the LLM config (useful for re-init after
/// settings change, though `update_llm_config` is preferred for that).
#[uniffi::export]
pub fn initialize(db_path: String, config: AppConfig) -> Result<(), LumenError> {
    // Pool: only create if not already initialised.
    if POOL.get().is_none() {
        let pool = db::create_pool(&db_path).map_err(|e| LumenError::DatabaseError {
            message: e.to_string(),
        })?;
        {
            let conn = pool.get().map_err(|e| LumenError::DatabaseError {
                message: e.to_string(),
            })?;
            crate::infrastructure::db::migration::run(&conn)?;
        }
        // Ignore error if another thread beat us to it.
        let _ = POOL.set(pool);
    }

    // Config: always write (allows subsequent calls to update settings).
    set_llm_config_inner(config)?;
    Ok(())
}

/// Hot-swap the LLM configuration without touching the DB pool.
/// Call this when the user saves new settings in the UI — takes effect
/// immediately for the next translation request.
#[uniffi::export]
pub fn update_llm_config(config: AppConfig) -> Result<(), LumenError> {
    set_llm_config_inner(config)
}

fn set_llm_config_inner(config: AppConfig) -> Result<(), LumenError> {
    let mut guard = LLM_CONFIG.write().map_err(|_| LumenError::DatabaseError {
        message: "LLM config lock poisoned".into(),
    })?;
    *guard = Some(LlmConfig {
        base_url: config.llm_base_url,
        api_key: config.llm_api_key,
        model: config.llm_model,
        target_language: config.target_language,
        word_prompt_template: config.word_prompt_template,
        sentence_prompt_template: config.sentence_prompt_template,
        explanation_prompt_template: config.explanation_prompt_template,
        word_system_prompt: config.word_system_prompt,
        sentence_system_prompt: config.sentence_system_prompt,
        explanation_system_prompt: config.explanation_system_prompt,
        extra_config: config.llm_extra_config,
    });
    Ok(())
}

fn pool() -> Result<&'static DbPool, LumenError> {
    POOL.get().ok_or(LumenError::ConfigNotInitialized)
}

/// Returns a *clone* of the current LLM config (cheap — all fields are `String`).
fn llm_config() -> Result<LlmConfig, LumenError> {
    LLM_CONFIG
        .read()
        .map_err(|_| LumenError::ConfigNotInitialized)?
        .clone()
        .ok_or(LumenError::ConfigNotInitialized)
}

fn translation_use_case(config: &LlmConfig) -> Result<TranslationUseCase, LumenError> {
    let pool = pool()?;
    let cache = Arc::new(SqliteTranslationCacheRepo::new(pool.clone()));
    let llm = Arc::new(LlmTranslator::new(config.clone()));
    let fallback = Arc::new(FallbackTranslator::new(config.target_language.clone()));
    let phonetic = Arc::new(DictionaryApiPhoneticProvider::new());

    Ok(TranslationUseCase::with_phonetic_for_language(
        cache,
        llm,
        fallback,
        phonetic,
        config.word_cache_scope(),
    ))
}

fn llm_translator() -> Result<LlmTranslator, LumenError> {
    Ok(LlmTranslator::new(llm_config()?))
}

fn stream_progress(callback: Arc<dyn TranslationStreamCallback>) -> StreamProgress {
    Box::new(move |partial| callback.on_progress(partial))
}

fn vocabulary_use_case() -> Result<VocabularyUseCase, LumenError> {
    Ok(VocabularyUseCase::new(Arc::new(SqliteVocabularyRepo::new(
        pool()?.clone(),
    ))))
}

fn pdf_document_use_case() -> Result<PdfDocumentUseCase, LumenError> {
    Ok(PdfDocumentUseCase::new(Arc::new(
        SqlitePdfDocumentRepo::new(pool()?.clone()),
    )))
}

fn note_use_case() -> Result<NoteUseCase, LumenError> {
    Ok(NoteUseCase::new(Arc::new(SqliteNoteRepo::new(
        pool()?.clone(),
    ))))
}

// ── Config type ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone, uniffi::Record)]
pub struct AppConfig {
    pub llm_base_url: String,
    pub llm_api_key: String,
    pub llm_model: String,
    pub target_language: String,
    pub word_prompt_template: String,
    pub sentence_prompt_template: String,
    pub explanation_prompt_template: String,
    pub word_system_prompt: String,
    pub sentence_system_prompt: String,
    pub explanation_system_prompt: String,
    pub llm_extra_config: String,
}

/// Provider Extra Config used when Settings leaves the field empty.
/// Pure host/model heuristics; does not require `initialize`.
#[uniffi::export]
pub fn default_extra_config(base_url: String, model: String) -> String {
    crate::infrastructure::translator::thinking_control::default_extra_config_json(
        &base_url, &model,
    )
}

// ── Translation API ──────────────────────────────────────────────────────────

/// Foreign-implemented callback used by streaming translation APIs to publish
/// partial `TranslationResult`s as soon as individual JSON fields finish
/// streaming from the LLM. Called many times per request, finally with the
/// fully-populated result. Implementations should marshal to the UI thread
/// and update the bubble; do not block.
#[uniffi::export(with_foreign)]
pub trait TranslationStreamCallback: Send + Sync {
    fn on_progress(&self, partial: TranslationResult);
}

/// Streaming word-level translation. Returns the same final `TranslationResult`
/// as a blocking lookup, but invokes `callback.on_progress` repeatedly while the
/// response streams in. Cache hits emit exactly once unless `skip_cache` is
/// true, which forces a fresh LLM call so the user can regenerate an
/// unsatisfactory explanation.
#[uniffi::export(async_runtime = "tokio")]
pub async fn translate_streaming(
    request: TranslationRequest,
    callback: Arc<dyn TranslationStreamCallback>,
    skip_cache: bool,
) -> Result<TranslationResult, LumenError> {
    let config = llm_config()?;
    translation_use_case(&config)?
        .translate_streaming(request, stream_progress(callback), skip_cache)
        .await
}

/// Streaming sentence translation. The callback fires repeatedly with partial
/// `TranslationResult`s containing the in-progress `context_sentence_translation`,
/// then a final emit with `sentence_breakdown` filled in (for long / complex
/// sentences). Short / simple sentences come back with an empty breakdown.
#[uniffi::export(async_runtime = "tokio")]
pub async fn translate_sentence_streaming(
    sentence: String,
    callback: Arc<dyn TranslationStreamCallback>,
) -> Result<TranslationResult, LumenError> {
    llm_translator()?
        .translate_sentence_streaming(&sentence, stream_progress(callback))
        .await
}

/// Streaming explanation for selected text. The LLM receives the selection and
/// its surrounding context, then streams an explanation into
/// `context_explanation` so the Swift UI can display it immediately and save
/// it as a note.
#[uniffi::export(async_runtime = "tokio")]
pub async fn explain_selection_streaming(
    selection: String,
    context: String,
    focus: String,
    images: Vec<ImageAttachment>,
    callback: Arc<dyn TranslationStreamCallback>,
) -> Result<TranslationResult, LumenError> {
    llm_translator()?
        .explain_selection_streaming(
            &selection,
            &context,
            &focus,
            &images,
            stream_progress(callback),
        )
        .await
}

/// Detect whether the configured model accepts image input. Providers that
/// expose model modality metadata are checked first; otherwise the translator
/// sends one minimal image probe. Authentication, network, and rate-limit
/// failures return `Unknown` rather than being misclassified as unsupported.
#[uniffi::export(async_runtime = "tokio")]
pub async fn detect_image_input_capability() -> Result<ImageInputCapability, LumenError> {
    Ok(llm_translator()?.detect_image_input_capability().await)
}

// ── Vocabulary API ───────────────────────────────────────────────────────────

#[uniffi::export]
pub fn save_vocabulary(req: SaveVocabularyRequest) -> Result<VocabularyEntry, LumenError> {
    vocabulary_use_case()?.save(req)
}

#[uniffi::export]
pub fn get_vocabulary_by_word_and_hash(
    word: String,
    sentence_hash: String,
) -> Result<Option<VocabularyEntry>, LumenError> {
    vocabulary_use_case()?.get_by_word_and_hash(&word, &sentence_hash)
}

#[uniffi::export]
pub fn list_vocabulary() -> Result<Vec<VocabularyEntry>, LumenError> {
    vocabulary_use_case()?.list()
}

#[uniffi::export]
pub fn delete_vocabulary(id: String) -> Result<(), LumenError> {
    vocabulary_use_case()?.delete(&id)
}

#[uniffi::export]
pub fn update_vocabulary_annotation(id: String, annotation_id: String) -> Result<(), LumenError> {
    vocabulary_use_case()?.update_annotation_id(&id, &annotation_id)
}

#[uniffi::export]
pub fn increment_vocabulary_query_count(id: String) -> Result<(), LumenError> {
    vocabulary_use_case()?.increment_query_count(&id)
}

#[uniffi::export]
pub fn update_vocabulary(req: UpdateVocabularyRequest) -> Result<VocabularyEntry, LumenError> {
    vocabulary_use_case()?.update(req)
}

// ── PDF Document API ─────────────────────────────────────────────────────────

#[uniffi::export]
pub fn upsert_pdf_document(req: UpsertPdfRequest) -> Result<PdfDocument, LumenError> {
    pdf_document_use_case()?.upsert(req)
}

#[uniffi::export]
pub fn save_reading_position(
    file_path: String,
    page: u32,
    scroll_offset: f64,
) -> Result<(), LumenError> {
    pdf_document_use_case()?.save_reading_position(&file_path, page, scroll_offset)
}

#[uniffi::export]
pub fn list_pdf_documents() -> Result<Vec<PdfDocument>, LumenError> {
    pdf_document_use_case()?.list()
}

#[uniffi::export]
pub fn delete_pdf_document(file_path: String) -> Result<(), LumenError> {
    pdf_document_use_case()?.delete(&file_path)
}

// ── Note API ───────────────────────────────────────────────────────────────

#[uniffi::export]
pub fn save_note(req: SaveNoteRequest) -> Result<NoteEntry, LumenError> {
    note_use_case()?.save(req)
}

#[uniffi::export]
pub fn apply_note_history_snapshot(
    remove_ids: Vec<String>,
    restore_notes: Vec<NoteEntry>,
) -> Result<(), LumenError> {
    note_use_case()?.apply_history_snapshot(remove_ids, restore_notes)
}

#[uniffi::export]
pub fn list_notes() -> Result<Vec<NoteEntry>, LumenError> {
    note_use_case()?.list()
}

#[uniffi::export]
pub fn list_notes_by_pdf(pdf_path: String) -> Result<Vec<NoteEntry>, LumenError> {
    note_use_case()?.list_by_pdf(&pdf_path)
}

#[uniffi::export]
pub fn delete_note(id: String) -> Result<(), LumenError> {
    note_use_case()?.delete(&id)
}

#[uniffi::export]
pub fn update_note(req: UpdateNoteRequest) -> Result<NoteEntry, LumenError> {
    note_use_case()?.update(req)
}
