use crate::domain::translation::{
    entity::{TranslationRequest, TranslationResult},
    repository::{PhoneticProvider, StreamProgress, TranslationCacheRepository, Translator},
    service::TranslationDomainService,
};
use crate::error::LumenError;
use std::sync::Arc;

pub struct TranslationUseCase {
    service: TranslationDomainService,
}

impl TranslationUseCase {
    pub fn with_phonetic_for_language(
        cache: Arc<dyn TranslationCacheRepository>,
        llm: Arc<dyn Translator>,
        fallback: Arc<dyn Translator>,
        phonetic: Arc<dyn PhoneticProvider>,
        target_language: impl Into<String>,
    ) -> Self {
        Self {
            service: TranslationDomainService::new(cache, llm, fallback)
                .with_cache_target_language(target_language)
                .with_phonetic(phonetic),
        }
    }

    pub async fn translate_streaming(
        &self,
        request: TranslationRequest,
        on_progress: StreamProgress,
        skip_cache: bool,
    ) -> Result<TranslationResult, LumenError> {
        if skip_cache {
            self.service
                .translate_streaming_skipping_cache(request, on_progress)
                .await
        } else {
            self.service.translate_streaming(request, on_progress).await
        }
    }
}
