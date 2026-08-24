use crate::domain::note::entity::{NoteEntry, SaveNoteRequest, UpdateNoteRequest};
use crate::domain::note::repository::NoteRepository;
use crate::domain::pdf_document::entity::{PdfDocument, UpsertPdfRequest};
use crate::domain::pdf_document::repository::PdfDocumentRepository;
use crate::domain::translation::entity::{
    ImageAttachment, ImageInputCapability, TranslationRequest, TranslationResult,
};
use crate::domain::translation::repository::StreamProgress;
use crate::domain::translation::service::TranslationDomainService;
use crate::domain::vocabulary::entity::{
    SaveVocabularyRequest, UpdateVocabularyRequest, VocabularyEntry,
};
use crate::domain::vocabulary::repository::VocabularyRepository;
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

static POOL: OnceLock<DbPool> = OnceLock::new();
static LLM_CONFIG: RwLock<Option<LlmConfig>> = RwLock::new(None);

/// Called once on app launch. Safe to call again — the DB pool is only created
/// once; later calls only refresh LLM config (`update_llm_config` is preferred).
#[uniffi::export]
pub fn initialize(db_path: String, config: AppConfig) -> Result<(), LumenError> {
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
        let _ = POOL.set(pool);
    }

    set_llm_config_inner(config)?;
    Ok(())
}

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

fn llm_config() -> Result<LlmConfig, LumenError> {
    LLM_CONFIG
        .read()
        .map_err(|_| LumenError::ConfigNotInitialized)?
        .clone()
        .ok_or(LumenError::ConfigNotInitialized)
}

fn translation_service(config: &LlmConfig) -> Result<TranslationDomainService, LumenError> {
    let pool = pool()?;
    let cache = Arc::new(SqliteTranslationCacheRepo::new(pool.clone()));
    let llm = Arc::new(LlmTranslator::new(config.clone()));
    let fallback = Arc::new(FallbackTranslator::new(config.target_language.clone()));
    let phonetic = Arc::new(DictionaryApiPhoneticProvider::new());
    Ok(TranslationDomainService::new(cache, llm, fallback)
        .with_cache_target_language(config.word_cache_scope())
        .with_phonetic(phonetic))
}

fn llm_translator() -> Result<LlmTranslator, LumenError> {
    Ok(LlmTranslator::new(llm_config()?))
}

fn stream_progress(callback: Arc<dyn TranslationStreamCallback>) -> StreamProgress {
    Box::new(move |partial| callback.on_progress(partial))
}

fn vocabulary_repo() -> Result<SqliteVocabularyRepo, LumenError> {
    Ok(SqliteVocabularyRepo::new(pool()?.clone()))
}

fn pdf_repo() -> Result<SqlitePdfDocumentRepo, LumenError> {
    Ok(SqlitePdfDocumentRepo::new(pool()?.clone()))
}

fn note_repo() -> Result<SqliteNoteRepo, LumenError> {
    Ok(SqliteNoteRepo::new(pool()?.clone()))
}

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

#[uniffi::export(with_foreign)]
pub trait TranslationStreamCallback: Send + Sync {
    fn on_progress(&self, partial: TranslationResult);
}

/// Streaming word translation. Cache hits emit once unless `skip_cache` is true.
#[uniffi::export(async_runtime = "tokio")]
pub async fn translate_streaming(
    request: TranslationRequest,
    callback: Arc<dyn TranslationStreamCallback>,
    skip_cache: bool,
) -> Result<TranslationResult, LumenError> {
    let config = llm_config()?;
    let service = translation_service(&config)?;
    let progress = stream_progress(callback);
    if skip_cache {
        service
            .translate_streaming_skipping_cache(request, progress)
            .await
    } else {
        service.translate_streaming(request, progress).await
    }
}

#[uniffi::export(async_runtime = "tokio")]
pub async fn translate_sentence_streaming(
    sentence: String,
    callback: Arc<dyn TranslationStreamCallback>,
) -> Result<TranslationResult, LumenError> {
    llm_translator()?
        .translate_sentence_streaming(&sentence, stream_progress(callback))
        .await
}

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

#[uniffi::export(async_runtime = "tokio")]
pub async fn detect_image_input_capability() -> Result<ImageInputCapability, LumenError> {
    Ok(llm_translator()?.detect_image_input_capability().await)
}

#[uniffi::export]
pub fn save_vocabulary(req: SaveVocabularyRequest) -> Result<VocabularyEntry, LumenError> {
    vocabulary_repo()?.save(req)
}

#[uniffi::export]
pub fn get_vocabulary_by_word_and_hash(
    word: String,
    sentence_hash: String,
) -> Result<Option<VocabularyEntry>, LumenError> {
    vocabulary_repo()?.get_by_word_and_hash(&word, &sentence_hash)
}

#[uniffi::export]
pub fn list_vocabulary() -> Result<Vec<VocabularyEntry>, LumenError> {
    vocabulary_repo()?.list()
}

#[uniffi::export]
pub fn delete_vocabulary(id: String) -> Result<(), LumenError> {
    vocabulary_repo()?.delete(&id)
}

#[uniffi::export]
pub fn increment_vocabulary_query_count(id: String) -> Result<(), LumenError> {
    vocabulary_repo()?.increment_query_count(&id)
}

#[uniffi::export]
pub fn update_vocabulary(req: UpdateVocabularyRequest) -> Result<VocabularyEntry, LumenError> {
    vocabulary_repo()?.update(req)
}

#[uniffi::export]
pub fn upsert_pdf_document(req: UpsertPdfRequest) -> Result<PdfDocument, LumenError> {
    pdf_repo()?.upsert(req)
}

#[uniffi::export]
pub fn save_reading_position(
    file_path: String,
    page: u32,
    scroll_offset: f64,
) -> Result<(), LumenError> {
    pdf_repo()?.save_reading_position(&file_path, page, scroll_offset)
}

#[uniffi::export]
pub fn list_pdf_documents() -> Result<Vec<PdfDocument>, LumenError> {
    pdf_repo()?.list()
}

#[uniffi::export]
pub fn delete_pdf_document(file_path: String) -> Result<(), LumenError> {
    pdf_repo()?.delete(&file_path)
}

#[uniffi::export]
pub fn save_note(req: SaveNoteRequest) -> Result<NoteEntry, LumenError> {
    note_repo()?.save(&req)
}

#[uniffi::export]
pub fn list_notes() -> Result<Vec<NoteEntry>, LumenError> {
    note_repo()?.list()
}

#[uniffi::export]
pub fn list_notes_by_pdf(pdf_path: String) -> Result<Vec<NoteEntry>, LumenError> {
    note_repo()?.list_by_pdf(&pdf_path)
}

#[uniffi::export]
pub fn delete_note(id: String) -> Result<(), LumenError> {
    note_repo()?.delete(&id)
}

#[uniffi::export]
pub fn update_note(req: UpdateNoteRequest) -> Result<NoteEntry, LumenError> {
    note_repo()?.update(&req)
}
