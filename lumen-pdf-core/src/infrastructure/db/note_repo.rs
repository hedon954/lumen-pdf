use crate::domain::note::{
    entity::{NoteEntry, SaveNoteRequest, UpdateNoteRequest},
    repository::NoteRepository,
};
use crate::error::LumenError;
use crate::infrastructure::db::DbPool;
use rusqlite::params;
use std::time::{SystemTime, UNIX_EPOCH};

pub struct SqliteNoteRepo {
    pool: DbPool,
}

impl SqliteNoteRepo {
    pub fn new(pool: DbPool) -> Self {
        Self { pool }
    }
}

impl NoteRepository for SqliteNoteRepo {
    fn save(&self, req: &SaveNoteRequest) -> Result<NoteEntry, LumenError> {
        let conn = self.pool.get().map_err(|e| LumenError::DatabaseError {
            message: e.to_string(),
        })?;

        let id = uuid::Uuid::new_v4().to_string();
        let created_at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;

        conn.execute(
            "INSERT INTO notes (id, pdf_path, pdf_name, page_index, content, note, bounds_str, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
            params![
                id,
                req.pdf_path,
                req.pdf_name,
                req.page_index as i32,
                req.content,
                req.note,
                req.bounds_str,
                created_at
            ],
        )?;

        Ok(NoteEntry {
            id,
            pdf_path: req.pdf_path.clone(),
            pdf_name: req.pdf_name.clone(),
            page_index: req.page_index,
            content: req.content.clone(),
            note: req.note.clone(),
            bounds_str: req.bounds_str.clone(),
            created_at,
        })
    }

    fn list(&self) -> Result<Vec<NoteEntry>, LumenError> {
        let conn = self.pool.get().map_err(|e| LumenError::DatabaseError {
            message: e.to_string(),
        })?;

        let mut stmt = conn.prepare(
            "SELECT id, pdf_path, pdf_name, page_index, content, note, bounds_str, created_at
             FROM notes ORDER BY created_at DESC",
        )?;

        let entries = stmt
            .query_map([], |row| {
                Ok(NoteEntry {
                    id: row.get(0)?,
                    pdf_path: row.get(1)?,
                    pdf_name: row.get(2)?,
                    page_index: row.get::<_, i32>(3)? as u32,
                    content: row.get(4)?,
                    note: row.get(5)?,
                    bounds_str: row.get(6)?,
                    created_at: row.get(7)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(entries)
    }

    fn list_by_pdf(&self, pdf_path: &str) -> Result<Vec<NoteEntry>, LumenError> {
        let conn = self.pool.get().map_err(|e| LumenError::DatabaseError {
            message: e.to_string(),
        })?;

        let mut stmt = conn.prepare(
            "SELECT id, pdf_path, pdf_name, page_index, content, note, bounds_str, created_at
             FROM notes WHERE pdf_path = ?1 ORDER BY created_at DESC",
        )?;

        let entries = stmt
            .query_map(params![pdf_path], |row| {
                Ok(NoteEntry {
                    id: row.get(0)?,
                    pdf_path: row.get(1)?,
                    pdf_name: row.get(2)?,
                    page_index: row.get::<_, i32>(3)? as u32,
                    content: row.get(4)?,
                    note: row.get(5)?,
                    bounds_str: row.get(6)?,
                    created_at: row.get(7)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(entries)
    }

    fn delete(&self, id: &str) -> Result<(), LumenError> {
        let conn = self.pool.get().map_err(|e| LumenError::DatabaseError {
            message: e.to_string(),
        })?;

        conn.execute("DELETE FROM notes WHERE id = ?1", params![id])?;

        Ok(())
    }

    fn update(&self, req: &UpdateNoteRequest) -> Result<NoteEntry, LumenError> {
        let conn = self.pool.get().map_err(|e| LumenError::DatabaseError {
            message: e.to_string(),
        })?;

        conn.execute(
            "UPDATE notes SET note = ?1 WHERE id = ?2",
            params![req.note, req.id],
        )?;

        // Fetch the updated entry
        let mut stmt = conn.prepare(
            "SELECT id, pdf_path, pdf_name, page_index, content, note, bounds_str, created_at
             FROM notes WHERE id = ?1",
        )?;

        let entry = stmt.query_row(params![req.id], |row| {
            Ok(NoteEntry {
                id: row.get(0)?,
                pdf_path: row.get(1)?,
                pdf_name: row.get(2)?,
                page_index: row.get::<_, i32>(3)? as u32,
                content: row.get(4)?,
                note: row.get(5)?,
                bounds_str: row.get(6)?,
                created_at: row.get(7)?,
            })
        })?;

        Ok(entry)
    }
}
