use super::{
    entity::{TranslationRequest, TranslationResult, TranslationSource},
    repository::{PhoneticProvider, StreamProgress, TranslationCacheRepository, Translator},
};
use crate::error::LumenError;
use sha2::{Digest, Sha256};
use std::sync::Arc;

pub struct TranslationDomainService {
    cache: Arc<dyn TranslationCacheRepository>,
    llm: Arc<dyn Translator>,
    fallback: Arc<dyn Translator>,
    cache_target_language: String,
    /// Optional authoritative source of (American) IPA for single words. When
    /// present, it overrides the LLM-produced `phonetic`, which is frequently
    /// inaccurate. Best-effort: a `None` result leaves the existing phonetic
    /// untouched.
    phonetic: Option<Arc<dyn PhoneticProvider>>,
}

/// A selection is eligible for dictionary-based phonetic enrichment only when
/// it is a single English word. The dictionary API takes one word at a time and
/// returns nothing useful for phrases / sentences, so we skip those entirely.
fn is_single_word(text: &str) -> bool {
    let trimmed = text.trim();
    !trimmed.is_empty()
        && trimmed
            .chars()
            .all(|c| c.is_alphabetic() || c == '-' || c == '\'')
}

impl TranslationDomainService {
    pub fn new(
        cache: Arc<dyn TranslationCacheRepository>,
        llm: Arc<dyn Translator>,
        fallback: Arc<dyn Translator>,
    ) -> Self {
        Self {
            cache,
            llm,
            fallback,
            cache_target_language: String::new(),
            phonetic: None,
        }
    }

    /// Use the target language as part of the cache key so cached translations
    /// generated for one output language never leak into another language.
    pub fn with_cache_target_language(mut self, target_language: impl Into<String>) -> Self {
        self.cache_target_language = target_language.into();
        self
    }

    /// Attach a phonetic provider used to override the LLM's IPA for single
    /// words. Chainable so `interfaces` can inject it during construction.
    pub fn with_phonetic(mut self, provider: Arc<dyn PhoneticProvider>) -> Self {
        self.phonetic = Some(provider);
        self
    }

    pub fn sentence_hash(sentence: &str) -> String {
        let mut hasher = Sha256::new();
        hasher.update(sentence.to_lowercase().as_bytes());
        hex::encode(hasher.finalize())
    }

    /// Best-effort lookup of an authoritative phonetic for `word`. Returns
    /// `None` when no provider is configured, the selection isn't a single
    /// word, or the provider yields nothing usable.
    async fn fetch_phonetic_override(&self, word: &str) -> Option<String> {
        let provider = self.phonetic.as_ref()?;
        if !is_single_word(word) {
            return None;
        }
        provider
            .fetch_phonetic(word.trim())
            .await
            .map(|p| p.trim().to_string())
            .filter(|p| !p.is_empty())
    }

    async fn cached_result(
        &self,
        request: &TranslationRequest,
        word_lower: &str,
        hash: &str,
    ) -> Result<Option<TranslationResult>, LumenError> {
        let Some(mut cached) = self
            .cache
            .get(word_lower, hash, &self.cache_target_language)?
        else {
            return Ok(None);
        };

        cached.source = TranslationSource::Cache.to_string();
        if cached.phonetic.trim().is_empty() {
            if let Some(p) = self.fetch_phonetic_override(&request.word).await {
                cached.phonetic = p;
            }
        }
        Ok(Some(cached))
    }

    fn apply_phonetic_override(result: &mut TranslationResult, phonetic: &Option<String>) {
        if let Some(p) = phonetic {
            result.phonetic = p.clone();
        }
    }

    fn complete_llm_result(
        &self,
        mut result: TranslationResult,
        phonetic: &Option<String>,
        word_lower: &str,
        hash: &str,
    ) -> TranslationResult {
        result.source = TranslationSource::Llm.to_string();
        result.llm_error_message = String::new();
        Self::apply_phonetic_override(&mut result, phonetic);
        let mut cached = result.clone();
        cached.http_request.clear();
        let _ = self
            .cache
            .set(word_lower, hash, &self.cache_target_language, &cached);
        result
    }

    fn complete_fallback_result(
        mut result: TranslationResult,
        llm_failure_note: Option<String>,
        phonetic: &Option<String>,
        http_request: String,
    ) -> TranslationResult {
        result.source = TranslationSource::Fallback.to_string();
        result.llm_error_message = llm_failure_note.unwrap_or_default();
        result.fallback_error_message = String::new();
        result.is_complete_failure = false;
        result.http_request = http_request;
        Self::apply_phonetic_override(&mut result, phonetic);
        result
    }

    fn complete_failure_result(
        request: &TranslationRequest,
        llm_failure_note: Option<String>,
        fallback_err: LumenError,
        http_request: String,
    ) -> TranslationResult {
        TranslationResult {
            word: request.word.clone(),
            source: "failed".to_string(),
            llm_error_message: llm_failure_note.unwrap_or_default(),
            fallback_error_message: fallback_err.user_hint_zh(),
            is_complete_failure: true,
            http_request,
            ..Default::default()
        }
    }

    pub async fn translate(
        &self,
        request: TranslationRequest,
    ) -> Result<TranslationResult, LumenError> {
        self.translate_impl(request, false).await
    }

    pub async fn translate_skipping_cache(
        &self,
        request: TranslationRequest,
    ) -> Result<TranslationResult, LumenError> {
        self.translate_impl(request, true).await
    }

    async fn translate_impl(
        &self,
        request: TranslationRequest,
        skip_cache: bool,
    ) -> Result<TranslationResult, LumenError> {
        let word_lower = request.word.to_lowercase();
        let hash = Self::sentence_hash(&request.sentence);

        if !skip_cache {
            if let Some(cached) = self.cached_result(&request, &word_lower, &hash).await? {
                return Ok(cached);
            }
        }

        // Level 2: LLM. Fetch the authoritative phonetic concurrently so it
        // adds no latency on top of the (slower) LLM round-trip.
        let (llm_res, phonetic) = tokio::join!(
            self.llm.translate(&request.word, &request.sentence),
            self.fetch_phonetic_override(&request.word),
        );
        let (llm_failure_note, http_request): (Option<String>, String) = match llm_res {
            Ok(result) => {
                return Ok(self.complete_llm_result(result, &phonetic, &word_lower, &hash))
            }
            Err(e) => (Some(e.user_hint_zh()), e.http_request().to_string()),
        };

        // Level 3: fallback (MyMemory), not cached
        match self
            .fallback
            .translate(&request.word, &request.sentence)
            .await
        {
            Ok(result) => Ok(Self::complete_fallback_result(
                result,
                llm_failure_note,
                &phonetic,
                http_request,
            )),
            Err(fallback_err) => Ok(Self::complete_failure_result(
                &request,
                llm_failure_note,
                fallback_err,
                http_request,
            )),
        }
    }

    /// Streaming variant of `translate`. Behaves identically to `translate`
    /// from the caller's perspective (returns the final result), but invokes
    /// `on_progress` repeatedly as fields stream in from the LLM. Cache hits
    /// emit exactly once with `source = "cache"`. Falling back to MyMemory
    /// also emits exactly once with the fallback result.
    pub async fn translate_streaming(
        &self,
        request: TranslationRequest,
        on_progress: StreamProgress,
    ) -> Result<TranslationResult, LumenError> {
        self.translate_streaming_impl(request, on_progress, false)
            .await
    }

    pub async fn translate_streaming_skipping_cache(
        &self,
        request: TranslationRequest,
        on_progress: StreamProgress,
    ) -> Result<TranslationResult, LumenError> {
        self.translate_streaming_impl(request, on_progress, true)
            .await
    }

    async fn translate_streaming_impl(
        &self,
        request: TranslationRequest,
        on_progress: StreamProgress,
        skip_cache: bool,
    ) -> Result<TranslationResult, LumenError> {
        let word_lower = request.word.to_lowercase();
        let hash = Self::sentence_hash(&request.sentence);

        // Wrap the caller's callback in a shared cell so we can hand a forwarding
        // adapter to the LLM streaming method while still being able to invoke
        // the original after streaming completes (final emit / fallback emit).
        // `Mutex` is fine: emissions are sequential, never concurrent.
        let shared: Arc<std::sync::Mutex<StreamProgress>> =
            Arc::new(std::sync::Mutex::new(on_progress));
        let emit = |result: TranslationResult| {
            if let Ok(mut cb) = shared.lock() {
                (cb)(result);
            }
        };

        if !skip_cache {
            if let Some(cached) = self.cached_result(&request, &word_lower, &hash).await? {
                emit(cached.clone());
                return Ok(cached);
            }
        }

        // Level 2: LLM (streaming). The forwarder stamps the canonical source
        // on each partial result before passing it through. The authoritative
        // phonetic is fetched concurrently and applied to the final result so
        // it adds no latency on top of the LLM stream.
        let forwarder: StreamProgress = {
            let shared = shared.clone();
            Box::new(move |mut partial: TranslationResult| {
                partial.source = TranslationSource::Llm.to_string();
                if let Ok(mut cb) = shared.lock() {
                    (cb)(partial);
                }
            })
        };
        let (llm_res, phonetic) = tokio::join!(
            self.llm
                .translate_streaming(&request.word, &request.sentence, forwarder),
            self.fetch_phonetic_override(&request.word),
        );
        let (llm_failure_note, http_request): (Option<String>, String) = match llm_res {
            Ok(result) => {
                let result = self.complete_llm_result(result, &phonetic, &word_lower, &hash);
                emit(result.clone());
                return Ok(result);
            }
            Err(e) => (Some(e.user_hint_zh()), e.http_request().to_string()),
        };

        // Level 3: fallback (non-streaming, single emit).
        match self
            .fallback
            .translate(&request.word, &request.sentence)
            .await
        {
            Ok(result) => {
                let result = Self::complete_fallback_result(
                    result,
                    llm_failure_note,
                    &phonetic,
                    http_request,
                );
                emit(result.clone());
                Ok(result)
            }
            Err(fallback_err) => {
                let result = Self::complete_failure_result(
                    &request,
                    llm_failure_note,
                    fallback_err,
                    http_request,
                );
                emit(result.clone());
                Ok(result)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::Mutex;

    struct FakeCache(Mutex<HashMap<String, TranslationResult>>);

    impl FakeCache {
        fn new() -> Arc<Self> {
            Arc::new(Self(Mutex::new(HashMap::new())))
        }
    }

    impl TranslationCacheRepository for FakeCache {
        fn get(
            &self,
            word: &str,
            hash: &str,
            target_language: &str,
        ) -> Result<Option<TranslationResult>, LumenError> {
            Ok(self
                .0
                .lock()
                .unwrap()
                .get(&format!("{word}:{hash}:{target_language}"))
                .cloned())
        }
        fn set(
            &self,
            word: &str,
            hash: &str,
            target_language: &str,
            r: &TranslationResult,
        ) -> Result<(), LumenError> {
            self.0
                .lock()
                .unwrap()
                .insert(format!("{word}:{hash}:{target_language}"), r.clone());
            Ok(())
        }
    }

    struct FakePhonetic {
        value: Option<String>,
        queried: Mutex<Vec<String>>,
    }

    impl FakePhonetic {
        fn new(value: Option<&str>) -> Arc<Self> {
            Arc::new(Self {
                value: value.map(|s| s.to_string()),
                queried: Mutex::new(Vec::new()),
            })
        }
    }

    #[async_trait::async_trait]
    impl PhoneticProvider for FakePhonetic {
        async fn fetch_phonetic(&self, word: &str) -> Option<String> {
            self.queried.lock().unwrap().push(word.to_string());
            self.value.clone()
        }
    }

    struct FakeLlm {
        word_result: &'static str,
    }

    #[async_trait::async_trait]
    impl Translator for FakeLlm {
        async fn translate(
            &self,
            word: &str,
            _sentence: &str,
        ) -> Result<TranslationResult, LumenError> {
            Ok(TranslationResult {
                word: word.to_string(),
                general_definition: self.word_result.to_string(),
                ..Default::default()
            })
        }
    }

    struct SequenceLlm {
        results: Mutex<Vec<&'static str>>,
    }

    #[async_trait::async_trait]
    impl Translator for SequenceLlm {
        async fn translate(
            &self,
            word: &str,
            _sentence: &str,
        ) -> Result<TranslationResult, LumenError> {
            let next = self.results.lock().unwrap().remove(0);
            Ok(TranslationResult {
                word: word.to_string(),
                general_definition: next.to_string(),
                ..Default::default()
            })
        }
    }

    struct FailingLlm;

    #[async_trait::async_trait]
    impl Translator for FailingLlm {
        async fn translate(
            &self,
            _word: &str,
            _sentence: &str,
        ) -> Result<TranslationResult, LumenError> {
            Err(LumenError::llm_api("timeout"))
        }
    }

    struct FakeFallback;

    #[async_trait::async_trait]
    impl Translator for FakeFallback {
        async fn translate(
            &self,
            word: &str,
            _sentence: &str,
        ) -> Result<TranslationResult, LumenError> {
            Ok(TranslationResult {
                word: word.to_string(),
                general_definition: "fallback result".to_string(),
                ..Default::default()
            })
        }
    }

    struct FailingFallback;

    #[async_trait::async_trait]
    impl Translator for FailingFallback {
        async fn translate(
            &self,
            _word: &str,
            _sentence: &str,
        ) -> Result<TranslationResult, LumenError> {
            Err(LumenError::FallbackApiError {
                message: "network error".to_string(),
            })
        }
    }

    #[tokio::test]
    async fn cache_hit_skips_llm() {
        let cache = FakeCache::new();
        let hash = TranslationDomainService::sentence_hash("the quick brown fox");
        cache
            .set(
                "run",
                &hash,
                "",
                &TranslationResult {
                    word: "run".to_string(),
                    general_definition: "cached".to_string(),
                    ..Default::default()
                },
            )
            .unwrap();

        let svc = TranslationDomainService::new(cache, Arc::new(FailingLlm), Arc::new(FailingLlm));

        let result = svc
            .translate(TranslationRequest {
                word: "run".to_string(),
                sentence: "the quick brown fox".to_string(),
            })
            .await
            .unwrap();

        assert_eq!(result.source, "cache");
        assert_eq!(result.general_definition, "cached");
    }

    #[tokio::test]
    async fn successful_llm_result_is_cached() {
        let cache = FakeCache::new();
        let svc = TranslationDomainService::new(
            cache.clone(),
            Arc::new(FakeLlm {
                word_result: "llm def",
            }),
            Arc::new(FailingLlm),
        );

        let result = svc
            .translate(TranslationRequest {
                word: "run".to_string(),
                sentence: "the quick brown fox".to_string(),
            })
            .await
            .unwrap();

        assert_eq!(result.source, "llm");
        assert_eq!(result.general_definition, "llm def");

        let hash = TranslationDomainService::sentence_hash("the quick brown fox");
        let cached = cache.get("run", &hash, "").unwrap();
        assert!(cached.is_some());
    }

    #[tokio::test]
    async fn cache_is_scoped_by_target_language() {
        let cache = FakeCache::new();
        let english = TranslationDomainService::new(
            cache.clone(),
            Arc::new(FakeLlm {
                word_result: "English definition",
            }),
            Arc::new(FailingLlm),
        )
        .with_cache_target_language("English");
        let chinese = TranslationDomainService::new(
            cache.clone(),
            Arc::new(FakeLlm {
                word_result: "中文释义",
            }),
            Arc::new(FailingLlm),
        )
        .with_cache_target_language("简体中文");

        let request = TranslationRequest {
            word: "run".to_string(),
            sentence: "the quick brown fox".to_string(),
        };

        let english_result = english.translate(request.clone()).await.unwrap();
        let chinese_result = chinese.translate(request).await.unwrap();

        assert_eq!(english_result.general_definition, "English definition");
        assert_eq!(chinese_result.general_definition, "中文释义");

        let hash = TranslationDomainService::sentence_hash("the quick brown fox");
        assert!(cache.get("run", &hash, "English").unwrap().is_some());
        assert!(cache.get("run", &hash, "简体中文").unwrap().is_some());
    }

    #[tokio::test]
    async fn llm_failure_falls_back_and_does_not_cache() {
        let cache = FakeCache::new();
        let svc = TranslationDomainService::new(
            cache.clone(),
            Arc::new(FailingLlm),
            Arc::new(FakeFallback),
        );

        let result = svc
            .translate(TranslationRequest {
                word: "run".to_string(),
                sentence: "the quick brown fox".to_string(),
            })
            .await
            .unwrap();

        assert_eq!(result.source, "fallback");
        assert!(
            result.llm_error_message.contains("LLM"),
            "expected LLM failure note when falling back, got {:?}",
            result.llm_error_message
        );

        let hash = TranslationDomainService::sentence_hash("the quick brown fox");
        let cached = cache.get("run", &hash, "").unwrap();
        assert!(cached.is_none());
    }

    struct StreamingFakeLlm {
        partials: Vec<TranslationResult>,
        final_result: TranslationResult,
    }

    #[async_trait::async_trait]
    impl Translator for StreamingFakeLlm {
        async fn translate(
            &self,
            _word: &str,
            _sentence: &str,
        ) -> Result<TranslationResult, LumenError> {
            Ok(self.final_result.clone())
        }

        async fn translate_streaming(
            &self,
            _word: &str,
            _sentence: &str,
            mut on_progress: StreamProgress,
        ) -> Result<TranslationResult, LumenError> {
            for p in &self.partials {
                on_progress(p.clone());
            }
            Ok(self.final_result.clone())
        }
    }

    #[tokio::test]
    async fn streaming_cache_hit_emits_once() {
        let cache = FakeCache::new();
        let hash = TranslationDomainService::sentence_hash("the quick brown fox");
        cache
            .set(
                "run",
                &hash,
                "",
                &TranslationResult {
                    word: "run".to_string(),
                    general_definition: "cached".to_string(),
                    ..Default::default()
                },
            )
            .unwrap();

        let svc = TranslationDomainService::new(cache, Arc::new(FailingLlm), Arc::new(FailingLlm));

        let emitted = Arc::new(std::sync::Mutex::new(Vec::<TranslationResult>::new()));
        let emitted_capture = emitted.clone();
        let cb: StreamProgress = Box::new(move |r| emitted_capture.lock().unwrap().push(r));

        let final_result = svc
            .translate_streaming(
                TranslationRequest {
                    word: "run".to_string(),
                    sentence: "the quick brown fox".to_string(),
                },
                cb,
            )
            .await
            .unwrap();

        assert_eq!(final_result.source, "cache");
        let emitted = emitted.lock().unwrap();
        assert_eq!(emitted.len(), 1);
        assert_eq!(emitted[0].source, "cache");
    }

    #[tokio::test]
    async fn streaming_llm_emits_each_partial_then_final() {
        let cache = FakeCache::new();
        let llm = StreamingFakeLlm {
            partials: vec![
                TranslationResult {
                    word: "run".into(),
                    context_translation: "跑".into(),
                    ..Default::default()
                },
                TranslationResult {
                    word: "run".into(),
                    context_translation: "跑".into(),
                    general_definition: "to move quickly".into(),
                    etymology: "源自古英语 rinnan，意为流动或奔跑。".into(),
                    ..Default::default()
                },
            ],
            final_result: TranslationResult {
                word: "run".into(),
                context_translation: "跑".into(),
                general_definition: "to move quickly".into(),
                etymology: "源自古英语 rinnan，意为流动或奔跑。".into(),
                context_sentence_translation: "他在跑步".into(),
                ..Default::default()
            },
        };
        let svc = TranslationDomainService::new(cache.clone(), Arc::new(llm), Arc::new(FailingLlm));

        let emitted = Arc::new(std::sync::Mutex::new(Vec::<TranslationResult>::new()));
        let emitted_capture = emitted.clone();
        let cb: StreamProgress = Box::new(move |r| emitted_capture.lock().unwrap().push(r));

        let final_result = svc
            .translate_streaming(
                TranslationRequest {
                    word: "run".into(),
                    sentence: "He is running".into(),
                },
                cb,
            )
            .await
            .unwrap();

        assert_eq!(final_result.source, "llm");
        assert_eq!(final_result.context_sentence_translation, "他在跑步");
        assert_eq!(
            final_result.etymology,
            "源自古英语 rinnan，意为流动或奔跑。"
        );

        let emitted = emitted.lock().unwrap();
        assert_eq!(emitted.len(), 3);
        assert!(emitted.iter().all(|r| r.source == "llm"));

        let hash = TranslationDomainService::sentence_hash("He is running");
        assert!(cache.get("run", &hash, "").unwrap().is_some());
    }

    #[tokio::test]
    async fn streaming_llm_failure_falls_back_and_emits_once() {
        let cache = FakeCache::new();
        let svc = TranslationDomainService::new(
            cache.clone(),
            Arc::new(FailingLlm),
            Arc::new(FakeFallback),
        );

        let emitted = Arc::new(std::sync::Mutex::new(Vec::<TranslationResult>::new()));
        let emitted_capture = emitted.clone();
        let cb: StreamProgress = Box::new(move |r| emitted_capture.lock().unwrap().push(r));

        let final_result = svc
            .translate_streaming(
                TranslationRequest {
                    word: "run".into(),
                    sentence: "He is running".into(),
                },
                cb,
            )
            .await
            .unwrap();

        assert_eq!(final_result.source, "fallback");

        let emitted = emitted.lock().unwrap();
        assert_eq!(emitted.len(), 1);
        assert_eq!(emitted[0].source, "fallback");
        assert!(emitted[0].llm_error_message.contains("LLM"));

        let hash = TranslationDomainService::sentence_hash("He is running");
        assert!(cache.get("run", &hash, "").unwrap().is_none());
    }

    #[tokio::test]
    async fn both_llm_and_fallback_fail_returns_error_info() {
        let cache = FakeCache::new();
        let svc = TranslationDomainService::new(
            cache,
            Arc::new(FailingLlm),      // LLM fails
            Arc::new(FailingFallback), // Fallback also fails
        );

        let result = svc
            .translate(TranslationRequest {
                word: "test".to_string(),
                sentence: "test sentence".to_string(),
            })
            .await
            .unwrap();

        assert!(result.is_complete_failure);
        assert!(!result.llm_error_message.is_empty());
        assert!(!result.fallback_error_message.is_empty());
        assert_eq!(result.source, "failed");
        assert!(result.http_request.is_empty());
    }

    struct FailingLlmWithRequest;

    #[async_trait::async_trait]
    impl Translator for FailingLlmWithRequest {
        async fn translate(
            &self,
            _word: &str,
            _sentence: &str,
        ) -> Result<TranslationResult, LumenError> {
            Err(LumenError::llm_api("timeout").with_http_request(
                "POST https://example.test/v1/chat/completions\nAuthorization: Bearer ***\nContent-Type: application/json\n\n{\"enable_thinking\":false}".into(),
            ))
        }
    }

    #[tokio::test]
    async fn fallback_keeps_llm_http_request_dump() {
        let cache = FakeCache::new();
        let svc = TranslationDomainService::new(
            cache,
            Arc::new(FailingLlmWithRequest),
            Arc::new(FakeFallback),
        );

        let result = svc
            .translate(TranslationRequest {
                word: "run".to_string(),
                sentence: "the quick brown fox".to_string(),
            })
            .await
            .unwrap();

        assert_eq!(result.source, "fallback");
        assert!(result.http_request.contains("enable_thinking"));
        assert!(result.http_request.contains("Bearer ***"));
        assert!(!result.http_request.contains("timeout"));
    }

    struct PhoneticLlm {
        phonetic: &'static str,
    }

    #[async_trait::async_trait]
    impl Translator for PhoneticLlm {
        async fn translate(
            &self,
            word: &str,
            _sentence: &str,
        ) -> Result<TranslationResult, LumenError> {
            Ok(TranslationResult {
                word: word.to_string(),
                phonetic: self.phonetic.to_string(),
                ..Default::default()
            })
        }
    }

    #[tokio::test]
    async fn phonetic_provider_overrides_llm_for_single_word() {
        let cache = FakeCache::new();
        let phonetic = FakePhonetic::new(Some("həˈloʊ"));
        let svc = TranslationDomainService::new(
            cache.clone(),
            Arc::new(PhoneticLlm { phonetic: "wrong" }),
            Arc::new(FailingLlm),
        )
        .with_phonetic(phonetic.clone());

        let result = svc
            .translate(TranslationRequest {
                word: "hello".to_string(),
                sentence: "hello world".to_string(),
            })
            .await
            .unwrap();

        assert_eq!(result.source, "llm");
        assert_eq!(result.phonetic, "həˈloʊ");
        assert_eq!(phonetic.queried.lock().unwrap().as_slice(), &["hello"]);

        let hash = TranslationDomainService::sentence_hash("hello world");
        let cached = cache.get("hello", &hash, "").unwrap().unwrap();
        assert_eq!(cached.phonetic, "həˈloʊ");
    }

    #[tokio::test]
    async fn phonetic_provider_skips_multi_word_selection() {
        let cache = FakeCache::new();
        let phonetic = FakePhonetic::new(Some("should-not-be-used"));
        let svc = TranslationDomainService::new(
            cache,
            Arc::new(PhoneticLlm {
                phonetic: "llm-phonetic",
            }),
            Arc::new(FailingLlm),
        )
        .with_phonetic(phonetic.clone());

        let result = svc
            .translate(TranslationRequest {
                word: "give up".to_string(),
                sentence: "give up now".to_string(),
            })
            .await
            .unwrap();

        assert!(phonetic.queried.lock().unwrap().is_empty());
        assert_eq!(result.phonetic, "llm-phonetic");
    }

    #[tokio::test]
    async fn phonetic_provider_keeps_llm_value_when_lookup_misses() {
        let cache = FakeCache::new();
        let phonetic = FakePhonetic::new(None);
        let svc = TranslationDomainService::new(
            cache,
            Arc::new(PhoneticLlm {
                phonetic: "llm-phonetic",
            }),
            Arc::new(FailingLlm),
        )
        .with_phonetic(phonetic.clone());

        let result = svc
            .translate(TranslationRequest {
                word: "obscureword".to_string(),
                sentence: "an obscureword here".to_string(),
            })
            .await
            .unwrap();

        assert_eq!(phonetic.queried.lock().unwrap().len(), 1);
        assert_eq!(result.phonetic, "llm-phonetic");
    }

    #[tokio::test]
    async fn phonetic_backfills_empty_cache_hit() {
        let cache = FakeCache::new();
        let hash = TranslationDomainService::sentence_hash("hello world");
        cache
            .set(
                "hello",
                &hash,
                "",
                &TranslationResult {
                    word: "hello".to_string(),
                    phonetic: String::new(),
                    general_definition: "cached".to_string(),
                    ..Default::default()
                },
            )
            .unwrap();

        let phonetic = FakePhonetic::new(Some("həˈloʊ"));
        let svc = TranslationDomainService::new(cache, Arc::new(FailingLlm), Arc::new(FailingLlm))
            .with_phonetic(phonetic.clone());

        let result = svc
            .translate(TranslationRequest {
                word: "hello".to_string(),
                sentence: "hello world".to_string(),
            })
            .await
            .unwrap();

        assert_eq!(result.source, "cache");
        assert_eq!(result.phonetic, "həˈloʊ");
    }

    #[test]
    fn is_single_word_recognises_words_and_phrases() {
        assert!(is_single_word("hello"));
        assert!(is_single_word("  hello  "));
        assert!(is_single_word("well-being"));
        assert!(is_single_word("don't"));
        assert!(!is_single_word("give up"));
        assert!(!is_single_word("a sentence here"));
        assert!(!is_single_word(""));
        assert!(!is_single_word("word1"));
    }

    fn word_request() -> TranslationRequest {
        TranslationRequest {
            word: "run".to_string(),
            sentence: "the quick brown fox".to_string(),
        }
    }

    #[tokio::test]
    async fn skip_cache_calls_llm_and_overwrites_cached_result() {
        let cache = FakeCache::new();
        let hash = TranslationDomainService::sentence_hash("the quick brown fox");
        cache
            .set(
                "run",
                &hash,
                "",
                &TranslationResult {
                    word: "run".to_string(),
                    general_definition: "cached".to_string(),
                    ..Default::default()
                },
            )
            .unwrap();

        let llm = SequenceLlm {
            results: Mutex::new(vec!["fresh"]),
        };
        let svc = TranslationDomainService::new(cache.clone(), Arc::new(llm), Arc::new(FailingLlm));

        let cached = svc.translate(word_request()).await.unwrap();
        assert_eq!(cached.source, "cache");
        assert_eq!(cached.general_definition, "cached");

        let fresh = svc.translate_skipping_cache(word_request()).await.unwrap();
        assert_eq!(fresh.source, "llm");
        assert_eq!(fresh.general_definition, "fresh");

        let stored = cache.get("run", &hash, "").unwrap().unwrap();
        assert_eq!(stored.general_definition, "fresh");
    }

    #[tokio::test]
    async fn streaming_skip_cache_bypasses_hit_and_emits_llm_result() {
        let cache = FakeCache::new();
        let hash = TranslationDomainService::sentence_hash("the quick brown fox");
        cache
            .set(
                "run",
                &hash,
                "",
                &TranslationResult {
                    word: "run".to_string(),
                    general_definition: "cached".to_string(),
                    ..Default::default()
                },
            )
            .unwrap();

        let llm = SequenceLlm {
            results: Mutex::new(vec!["streamed-fresh"]),
        };
        let svc = TranslationDomainService::new(cache.clone(), Arc::new(llm), Arc::new(FailingLlm));
        let emitted = Arc::new(Mutex::new(Vec::<TranslationResult>::new()));
        let emitted_capture = emitted.clone();
        let cb: StreamProgress = Box::new(move |r| emitted_capture.lock().unwrap().push(r));

        let result = svc
            .translate_streaming_skipping_cache(word_request(), cb)
            .await
            .unwrap();

        assert_eq!(result.source, "llm");
        assert_eq!(result.general_definition, "streamed-fresh");
        let emitted = emitted.lock().unwrap();
        assert!(emitted.iter().all(|item| item.source != "cache"));
        assert_eq!(
            emitted.last().map(|item| item.general_definition.as_str()),
            Some("streamed-fresh")
        );
    }
}
