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

fn row_to_note(row: &rusqlite::Row<'_>) -> rusqlite::Result<NoteEntry> {
    Ok(NoteEntry {
        id: row.get(0)?,
        pdf_path: row.get(1)?,
        pdf_name: row.get(2)?,
        page_index: row.get::<_, i32>(3)? as u32,
        content: row.get(4)?,
        note: row.get(5)?,
        bounds_str: row.get(6)?,
        page_markups: row.get(7)?,
        created_at: row.get(8)?,
    })
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
            "INSERT INTO notes (id, pdf_path, pdf_name, page_index, content, note, bounds_str, page_markups, created_at)
             VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)",
            params![
                id,
                req.pdf_path,
                req.pdf_name,
                req.page_index as i32,
                req.content,
                req.note,
                req.bounds_str,
                req.page_markups,
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
            page_markups: req.page_markups.clone(),
            created_at,
        })
    }

    fn apply_history_snapshot(
        &self,
        remove_ids: &[String],
        restore_notes: &[NoteEntry],
    ) -> Result<(), LumenError> {
        let mut conn = self.pool.get().map_err(|e| LumenError::DatabaseError {
            message: e.to_string(),
        })?;
        let transaction = conn.transaction()?;

        for id in remove_ids {
            transaction.execute("DELETE FROM notes WHERE id = ?1", params![id])?;
        }

        for note in restore_notes {
            transaction.execute(
                "INSERT INTO notes (
                    id, pdf_path, pdf_name, page_index, content, note,
                    bounds_str, page_markups, created_at
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
                 ON CONFLICT(id) DO UPDATE SET
                    pdf_path = excluded.pdf_path,
                    pdf_name = excluded.pdf_name,
                    page_index = excluded.page_index,
                    content = excluded.content,
                    note = excluded.note,
                    bounds_str = excluded.bounds_str,
                    page_markups = excluded.page_markups,
                    created_at = excluded.created_at",
                params![
                    note.id,
                    note.pdf_path,
                    note.pdf_name,
                    note.page_index as i32,
                    note.content,
                    note.note,
                    note.bounds_str,
                    note.page_markups,
                    note.created_at,
                ],
            )?;
        }

        transaction.commit()?;
        Ok(())
    }

    fn list(&self) -> Result<Vec<NoteEntry>, LumenError> {
        let conn = self.pool.get().map_err(|e| LumenError::DatabaseError {
            message: e.to_string(),
        })?;

        let mut stmt = conn.prepare(
            "SELECT id, pdf_path, pdf_name, page_index, content, note, bounds_str, page_markups, created_at
             FROM notes ORDER BY created_at DESC",
        )?;

        let entries = stmt
            .query_map([], row_to_note)?
            .collect::<Result<Vec<_>, _>>()?;

        Ok(entries)
    }

    fn list_by_pdf(&self, pdf_path: &str) -> Result<Vec<NoteEntry>, LumenError> {
        let conn = self.pool.get().map_err(|e| LumenError::DatabaseError {
            message: e.to_string(),
        })?;

        let mut stmt = conn.prepare(
            "SELECT id, pdf_path, pdf_name, page_index, content, note, bounds_str, page_markups, created_at
             FROM notes WHERE pdf_path = ?1 ORDER BY created_at DESC",
        )?;

        let entries = stmt
            .query_map(params![pdf_path], row_to_note)?
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
            "SELECT id, pdf_path, pdf_name, page_index, content, note, bounds_str, page_markups, created_at
             FROM notes WHERE id = ?1",
        )?;

        let entry = stmt.query_row(params![req.id], row_to_note)?;

        Ok(entry)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use r2d2::Pool;
    use r2d2_sqlite::SqliteConnectionManager;

    fn repo() -> SqliteNoteRepo {
        let manager = SqliteConnectionManager::memory();
        let pool = Pool::builder().max_size(1).build(manager).unwrap();
        pool.get()
            .unwrap()
            .execute_batch(
                "CREATE TABLE notes (
                    id TEXT PRIMARY KEY,
                    pdf_path TEXT NOT NULL,
                    pdf_name TEXT NOT NULL,
                    page_index INTEGER NOT NULL,
                    content TEXT NOT NULL,
                    note TEXT NOT NULL,
                    bounds_str TEXT NOT NULL,
                    page_markups TEXT NOT NULL DEFAULT '',
                    created_at INTEGER NOT NULL
                );",
            )
            .unwrap();
        SqliteNoteRepo::new(pool)
    }

    fn note(id: &str, content: &str, created_at: i64) -> NoteEntry {
        NoteEntry {
            id: id.to_string(),
            pdf_path: "/tmp/book.pdf".to_string(),
            pdf_name: "book.pdf".to_string(),
            page_index: 3,
            content: content.to_string(),
            note: "memo".to_string(),
            bounds_str: "{{1, 2}, {3, 4}}".to_string(),
            page_markups: "[]".to_string(),
            created_at,
        }
    }

    #[test]
    fn history_snapshot_restores_exact_identity_and_is_idempotent() {
        let repo = repo();
        let original = note("original-id", "before", 123);
        let replacement = note("replacement-id", "after", 456);

        repo.apply_history_snapshot(&[], std::slice::from_ref(&replacement))
            .unwrap();
        repo.apply_history_snapshot(
            std::slice::from_ref(&replacement.id),
            std::slice::from_ref(&original),
        )
        .unwrap();
        repo.apply_history_snapshot(&[], std::slice::from_ref(&original))
            .unwrap();

        let restored = repo.list_by_pdf("/tmp/book.pdf").unwrap();
        assert_eq!(restored.len(), 1);
        assert_eq!(restored[0].id, "original-id");
        assert_eq!(restored[0].content, "before");
        assert_eq!(restored[0].created_at, 123);
    }
}
