/// The source of a translation result.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum TranslationSource {
    Cache,
    Llm,
    Fallback,
}

impl TranslationSource {
    pub fn as_str(&self) -> &'static str {
        match self {
            TranslationSource::Cache => "cache",
            TranslationSource::Llm => "llm",
            TranslationSource::Fallback => "fallback",
        }
    }
}

impl std::fmt::Display for TranslationSource {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.as_str())
    }
}

impl TryFrom<&str> for TranslationSource {
    type Error = ();
    fn try_from(s: &str) -> Result<Self, Self::Error> {
        match s {
            "cache" => Ok(TranslationSource::Cache),
            "llm" => Ok(TranslationSource::Llm),
            "fallback" => Ok(TranslationSource::Fallback),
            _ => Err(()),
        }
    }
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct TranslationRequest {
    pub word: String,
    pub sentence: String,
}

#[derive(Debug, Clone, Default, uniffi::Record, serde::Serialize, serde::Deserialize)]
pub struct TranslationResult {
    pub word: String,
    pub phonetic: String,
    pub part_of_speech: String,
    pub context_translation: String,
    pub context_explanation: String,
    pub general_definition: String,
    /// Full translation of the entire context sentence (helps LLM / reading).
    #[serde(default)]
    pub context_sentence_translation: String,
    pub source: String,
    /// When non-empty: LLM step failed but fallback (or cache) still produced a result.
    /// Empty when LLM succeeded or when the result came from cache without a prior LLM error in this request.
    #[serde(default)]
    pub llm_error_message: String,
    /// When non-empty: Fallback step also failed. Contains the fallback error message.
    /// Empty when fallback succeeded or wasn't needed.
    #[serde(default)]
    pub fallback_error_message: String,
    /// When true: both LLM and Fallback failed, result contains only error info.
    /// The UI should display both errors and indicate complete failure.
    #[serde(default)]
    pub is_complete_failure: bool,
}
