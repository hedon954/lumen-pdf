use crate::domain::translation::repository::PhoneticProvider;
use crate::infrastructure::translator::http_client::shared_client;
use serde::Deserialize;

/// Phonetic provider backed by the free, key-less [Free Dictionary API]
/// (`https://api.dictionaryapi.dev`). It returns one or more IPA transcriptions
/// per word, often tagged with an audio clip whose URL encodes the accent
/// (`...-us.mp3` / `...-uk.mp3`). We prefer the American variant.
///
/// All failures (network, non-200, malformed JSON, unknown word) collapse to
/// `None` so phonetic lookup can never break translation.
///
/// [Free Dictionary API]: https://dictionaryapi.dev/
pub struct DictionaryApiPhoneticProvider;

impl DictionaryApiPhoneticProvider {
    pub fn new() -> Self {
        Self
    }
}

impl Default for DictionaryApiPhoneticProvider {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Deserialize)]
struct DictEntry {
    #[serde(default)]
    phonetic: Option<String>,
    #[serde(default)]
    phonetics: Vec<DictPhonetic>,
}

#[derive(Debug, Deserialize)]
struct DictPhonetic {
    #[serde(default)]
    text: Option<String>,
    #[serde(default)]
    audio: Option<String>,
}

#[async_trait::async_trait]
impl PhoneticProvider for DictionaryApiPhoneticProvider {
    async fn fetch_phonetic(&self, word: &str) -> Option<String> {
        let trimmed = word.trim();
        if trimmed.is_empty() {
            return None;
        }
        let url = format!(
            "https://api.dictionaryapi.dev/api/v2/entries/en/{}",
            urlencoding::encode(trimmed),
        );
        let resp = shared_client().get(&url).send().await.ok()?;
        if !resp.status().is_success() {
            return None;
        }
        let entries: Vec<DictEntry> = resp.json().await.ok()?;
        select_american_phonetic(&entries)
    }
}

/// Pick the best phonetic from the API response, preferring the American
/// accent. Selection order:
/// 1. A `phonetics[]` entry whose audio URL marks it as US (`-us.`) with text.
/// 2. The first `phonetics[]` entry that carries a non-empty `text`.
/// 3. The top-level `phonetic` field.
///
/// The result is normalized: surrounding slashes / brackets and whitespace are
/// stripped so the UI (which wraps the value in `[...]`) renders cleanly.
fn select_american_phonetic(entries: &[DictEntry]) -> Option<String> {
    // 1. US-tagged audio with text.
    for entry in entries {
        for ph in &entry.phonetics {
            let is_us = ph
                .audio
                .as_deref()
                .map(|a| a.to_lowercase().contains("-us."))
                .unwrap_or(false);
            if is_us {
                if let Some(text) = normalize(ph.text.as_deref()) {
                    return Some(text);
                }
            }
        }
    }
    // 2. Any phonetics entry with non-empty text.
    for entry in entries {
        for ph in &entry.phonetics {
            if let Some(text) = normalize(ph.text.as_deref()) {
                return Some(text);
            }
        }
    }
    // 3. Top-level phonetic.
    for entry in entries {
        if let Some(text) = normalize(entry.phonetic.as_deref()) {
            return Some(text);
        }
    }
    None
}

/// Trim whitespace and a single layer of surrounding IPA delimiters (`/` or
/// `[]`). Returns `None` for empty / missing input.
fn normalize(raw: Option<&str>) -> Option<String> {
    let s = raw?.trim();
    let s = s
        .strip_prefix('/')
        .and_then(|inner| inner.strip_suffix('/'))
        .or_else(|| {
            s.strip_prefix('[')
                .and_then(|inner| inner.strip_suffix(']'))
        })
        .unwrap_or(s)
        .trim();
    if s.is_empty() {
        None
    } else {
        Some(s.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(phonetic: Option<&str>, phonetics: Vec<(Option<&str>, Option<&str>)>) -> DictEntry {
        DictEntry {
            phonetic: phonetic.map(|s| s.to_string()),
            phonetics: phonetics
                .into_iter()
                .map(|(text, audio)| DictPhonetic {
                    text: text.map(|s| s.to_string()),
                    audio: audio.map(|s| s.to_string()),
                })
                .collect(),
        }
    }

    #[test]
    fn prefers_us_audio_variant() {
        let entries = vec![entry(
            Some("/həˈləʊ/"),
            vec![
                (Some("/həˈləʊ/"), Some("https://.../hello-uk.mp3")),
                (Some("/həˈloʊ/"), Some("https://.../hello-us.mp3")),
            ],
        )];
        assert_eq!(
            select_american_phonetic(&entries),
            Some("həˈloʊ".to_string())
        );
    }

    #[test]
    fn falls_back_to_any_text_when_no_us_audio() {
        let entries = vec![entry(
            Some("/ˈwɜːrd/"),
            vec![(Some("/wɜːd/"), Some("https://.../word-uk.mp3"))],
        )];
        assert_eq!(select_american_phonetic(&entries), Some("wɜːd".to_string()));
    }

    #[test]
    fn falls_back_to_top_level_phonetic() {
        let entries = vec![entry(Some("[ˈtɛst]"), vec![(None, None)])];
        assert_eq!(
            select_american_phonetic(&entries),
            Some("ˈtɛst".to_string())
        );
    }

    #[test]
    fn returns_none_when_nothing_present() {
        let entries = vec![entry(None, vec![(Some("  "), None)])];
        assert_eq!(select_american_phonetic(&entries), None);
        assert_eq!(select_american_phonetic(&[]), None);
    }

    #[test]
    fn skips_us_entry_without_text_and_uses_next() {
        // US audio present but no text → should fall through to the next
        // entry that has text.
        let entries = vec![entry(
            None,
            vec![
                (None, Some("https://.../x-us.mp3")),
                (Some("/ɪɡˈzæmpəl/"), Some("https://.../x-uk.mp3")),
            ],
        )];
        assert_eq!(
            select_american_phonetic(&entries),
            Some("ɪɡˈzæmpəl".to_string())
        );
    }
}
