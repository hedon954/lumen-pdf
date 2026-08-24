use super::{query, DbPool};
use crate::domain::vocabulary::{
    entity::{SaveVocabularyRequest, UpdateVocabularyRequest, VocabularyEntry},
    repository::VocabularyRepository,
};
use crate::error::LumenError;
use chrono::Utc;
use uuid::Uuid;

pub struct SqliteVocabularyRepo {
    pool: DbPool,
}

impl SqliteVocabularyRepo {
    pub fn new(pool: DbPool) -> Self {
        Self { pool }
    }
}

fn row_to_entry(row: &rusqlite::Row<'_>) -> rusqlite::Result<VocabularyEntry> {
    Ok(VocabularyEntry {
        id: row.get(0)?,
        word: row.get(1)?,
        sentence: row.get(2)?,
        sentence_hash: row.get(3)?,
        pdf_path: row.get(4)?,
        pdf_name: row.get(5)?,
        page_index: row.get::<_, i64>(6)? as u32,
        selection_bounds: row.get(7)?,
        phonetic: row.get(8)?,
        part_of_speech: row.get(9)?,
        context_translation: row.get(10)?,
        context_explanation: row.get(11)?,
        etymology: row.get(12)?,
        general_definition: row.get(13)?,
        context_sentence_translation: row.get(14)?,
        translation_source: row.get(15)?,
        annotation_id: row.get(16)?,
        created_at: row.get(17)?,
        query_count: row.get::<_, i64>(18).unwrap_or(0) as u32,
    })
}

const SELECT_COLS: &str = "id, word, sentence, sentence_hash, pdf_path, pdf_name,
    page_index, selection_bounds, phonetic, part_of_speech,
    context_translation, context_explanation, etymology, general_definition,
    context_sentence_translation,
    translation_source, annotation_id, created_at,
    COALESCE(query_count, 0) AS query_count";

impl VocabularyRepository for SqliteVocabularyRepo {
    fn save(&self, req: SaveVocabularyRequest) -> Result<VocabularyEntry, LumenError> {
        let conn = self.pool.get()?;
        let id = Uuid::new_v4().to_string();
        let now = Utc::now().timestamp();
        conn.execute(
            "INSERT INTO vocabulary_entries
             (id, word, sentence, sentence_hash, pdf_path, pdf_name, page_index,
              selection_bounds, phonetic, part_of_speech, context_translation,
              context_explanation, etymology, general_definition, context_sentence_translation,
              translation_source, annotation_id, created_at,
              query_count)
             VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17,?18,0)",
            rusqlite::params![
                id,
                req.word,
                req.sentence,
                req.sentence_hash,
                req.pdf_path,
                req.pdf_name,
                req.page_index,
                req.selection_bounds,
                req.phonetic,
                req.part_of_speech,
                req.context_translation,
                req.context_explanation,
                req.etymology,
                req.general_definition,
                req.context_sentence_translation,
                req.translation_source,
                req.annotation_id,
                now,
            ],
        )?;
        Ok(VocabularyEntry {
            id,
            word: req.word,
            sentence: req.sentence,
            sentence_hash: req.sentence_hash,
            pdf_path: req.pdf_path,
            pdf_name: req.pdf_name,
            page_index: req.page_index,
            selection_bounds: req.selection_bounds,
            phonetic: req.phonetic,
            part_of_speech: req.part_of_speech,
            context_translation: req.context_translation,
            context_explanation: req.context_explanation,
            etymology: req.etymology,
            general_definition: req.general_definition,
            context_sentence_translation: req.context_sentence_translation,
            translation_source: req.translation_source,
            annotation_id: req.annotation_id,
            created_at: now,
            query_count: 0,
        })
    }

    fn get_by_id(&self, id: &str) -> Result<Option<VocabularyEntry>, LumenError> {
        let conn = self.pool.get()?;
        query::optional(conn.query_row(
            &format!("SELECT {SELECT_COLS} FROM vocabulary_entries WHERE id = ?1"),
            rusqlite::params![id],
            row_to_entry,
        ))
    }

    fn get_by_word_and_hash(
        &self,
        word: &str,
        sentence_hash: &str,
    ) -> Result<Option<VocabularyEntry>, LumenError> {
        let conn = self.pool.get()?;
        query::optional(conn.query_row(
            &format!("SELECT {SELECT_COLS} FROM vocabulary_entries WHERE LOWER(word) = LOWER(?1) AND sentence_hash = ?2"),
            rusqlite::params![word, sentence_hash],
            row_to_entry,
        ))
    }

    fn list(&self) -> Result<Vec<VocabularyEntry>, LumenError> {
        let conn = self.pool.get()?;
        let mut stmt = conn.prepare(&format!(
            "SELECT {SELECT_COLS} FROM vocabulary_entries ORDER BY created_at DESC"
        ))?;
        let entries = stmt
            .query_map([], row_to_entry)?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(entries)
    }

    fn delete(&self, id: &str) -> Result<(), LumenError> {
        let conn = self.pool.get()?;
        conn.execute(
            "DELETE FROM vocabulary_entries WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    }

    fn increment_query_count(&self, id: &str) -> Result<(), LumenError> {
        let conn = self.pool.get()?;
        conn.execute(
            "UPDATE vocabulary_entries SET query_count = query_count + 1 WHERE id = ?1",
            rusqlite::params![id],
        )?;
        Ok(())
    }

    fn update(&self, req: UpdateVocabularyRequest) -> Result<VocabularyEntry, LumenError> {
        let conn = self.pool.get()?;
        conn.execute(
            "UPDATE vocabulary_entries SET phonetic = ?1, part_of_speech = ?2,
             context_translation = ?3, context_explanation = ?4, etymology = ?5,
             general_definition = ?6, context_sentence_translation = ?7
             WHERE id = ?8",
            rusqlite::params![
                req.phonetic,
                req.part_of_speech,
                req.context_translation,
                req.context_explanation,
                req.etymology,
                req.general_definition,
                req.context_sentence_translation,
                req.id,
            ],
        )?;
        self.get_by_id(&req.id)?
            .ok_or_else(|| LumenError::NotFound {
                message: format!("entry {} not found", req.id),
            })
    }
}
