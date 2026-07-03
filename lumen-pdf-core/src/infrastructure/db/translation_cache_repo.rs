use super::{query, DbPool};
use crate::domain::translation::{
    entity::TranslationResult, repository::TranslationCacheRepository,
};
use crate::error::LumenError;
use chrono::Utc;
use uuid::Uuid;

pub struct SqliteTranslationCacheRepo {
    pool: DbPool,
}

impl SqliteTranslationCacheRepo {
    pub fn new(pool: DbPool) -> Self {
        Self { pool }
    }
}

impl TranslationCacheRepository for SqliteTranslationCacheRepo {
    fn get(
        &self,
        word: &str,
        sentence_hash: &str,
        target_language: &str,
    ) -> Result<Option<TranslationResult>, LumenError> {
        let conn = self.pool.get()?;
        let json = query::optional(conn.query_row(
            "SELECT response_json FROM translation_cache WHERE word = ?1 AND sentence_hash = ?2 AND target_language = ?3",
            rusqlite::params![word, sentence_hash, target_language],
            |row| row.get::<_, String>(0),
        ))?;

        match json {
            Some(json) => {
                conn.execute(
                    "UPDATE translation_cache SET hit_count = hit_count + 1 WHERE word = ?1 AND sentence_hash = ?2 AND target_language = ?3",
                    rusqlite::params![word, sentence_hash, target_language],
                ).ok();
                let r: TranslationResult =
                    serde_json::from_str(&json).map_err(|e| LumenError::SerializationError {
                        message: e.to_string(),
                    })?;
                Ok(Some(r))
            }
            None => Ok(None),
        }
    }

    fn set(
        &self,
        word: &str,
        sentence_hash: &str,
        target_language: &str,
        result: &TranslationResult,
    ) -> Result<(), LumenError> {
        let conn = self.pool.get()?;
        let json = serde_json::to_string(result)?;
        conn.execute(
            "INSERT INTO translation_cache (id, word, sentence_hash, target_language, response_json, source, created_at, hit_count)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 0)
             ON CONFLICT(word, sentence_hash, target_language) DO UPDATE SET response_json = excluded.response_json, source = excluded.source",
            rusqlite::params![
                Uuid::new_v4().to_string(),
                word,
                sentence_hash,
                target_language,
                json,
                result.source,
                Utc::now().timestamp(),
            ],
        )?;
        Ok(())
    }
}
