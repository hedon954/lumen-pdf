use super::library::{io_error, rewrite_book, CopiedBook};
use super::{query, DbPool};
use crate::domain::library::service::is_library_path;
use crate::domain::pdf_document::{
    entity::{ImportedPdf, PdfDocument, UpsertPdfRequest},
    repository::PdfDocumentRepository,
};
use crate::error::LumenError;
use crate::infrastructure::library_store::LibraryStore;
use chrono::Utc;
use rusqlite::{params, Connection};
use std::path::Path;
use uuid::Uuid;

const COLUMNS: &str =
    "id, file_path, file_name, total_pages, last_page, last_scroll_offset, opened_at, added_at, original_path";

pub struct SqlitePdfDocumentRepo {
    pool: DbPool,
    store: LibraryStore,
}

impl SqlitePdfDocumentRepo {
    pub fn new(pool: DbPool, store: LibraryStore) -> Self {
        Self { pool, store }
    }
}

fn row_to_doc(row: &rusqlite::Row<'_>) -> rusqlite::Result<PdfDocument> {
    Ok(PdfDocument {
        id: row.get(0)?,
        file_path: row.get(1)?,
        file_name: row.get(2)?,
        total_pages: row.get::<_, i64>(3)? as u32,
        last_page: row.get::<_, i64>(4)? as u32,
        last_scroll_offset: row.get(5)?,
        opened_at: row.get(6)?,
        added_at: row.get(7)?,
        original_path: row.get(8)?,
    })
}

fn find(conn: &Connection, filter: &str, value: &str) -> Result<Option<PdfDocument>, LumenError> {
    query::optional(conn.query_row(
        &format!("SELECT {COLUMNS} FROM pdf_documents WHERE {filter} = ?1 ORDER BY opened_at DESC LIMIT 1"),
        params![value],
        row_to_doc,
    ))
}

/// 重新打开：更新打开时间；只有知道页数时才更新页数。
fn touch(conn: &Connection, id: &str, total_pages: u32) -> Result<PdfDocument, LumenError> {
    conn.execute(
        "UPDATE pdf_documents
         SET opened_at = ?1, total_pages = CASE WHEN ?2 > 0 THEN ?2 ELSE total_pages END
         WHERE id = ?3",
        params![Utc::now().timestamp(), total_pages, id],
    )?;
    find(conn, "id", id)?.ok_or_else(|| LumenError::DatabaseError {
        message: format!("pdf document {id} disappeared"),
    })
}

impl PdfDocumentRepository for SqlitePdfDocumentRepo {
    fn upsert(&self, req: UpsertPdfRequest) -> Result<PdfDocument, LumenError> {
        let conn = self.pool.get()?;
        let now = Utc::now().timestamp();

        match find(&conn, "file_path", &req.file_path)? {
            Some(mut doc) => {
                doc.opened_at = now;
                doc.total_pages = req.total_pages;
                conn.execute(
                    "UPDATE pdf_documents SET opened_at = ?1, total_pages = ?2 WHERE file_path = ?3",
                    params![now, req.total_pages, req.file_path],
                )?;
                Ok(doc)
            }
            None => {
                let id = Uuid::new_v4().to_string();
                conn.execute(
                    "INSERT INTO pdf_documents (id, file_path, file_name, total_pages, last_page, last_scroll_offset, opened_at, added_at)
                     VALUES (?1, ?2, ?3, ?4, 0, 0.0, ?5, ?5)",
                    params![id, req.file_path, req.file_name, req.total_pages, now],
                )?;
                Ok(PdfDocument {
                    id,
                    file_path: req.file_path,
                    file_name: req.file_name,
                    total_pages: req.total_pages,
                    last_page: 0,
                    last_scroll_offset: 0.0,
                    opened_at: now,
                    added_at: now,
                    original_path: None,
                })
            }
        }
    }

    fn import(&self, req: UpsertPdfRequest) -> Result<ImportedPdf, LumenError> {
        let conn = self.pool.get()?;
        if is_library_path(&req.file_path, &self.store.root_str()) {
            let document = match find(&conn, "file_path", &req.file_path)? {
                Some(doc) => touch(&conn, &doc.id, req.total_pages)?,
                None => self.upsert(req)?,
            };
            return Ok(ImportedPdf {
                document,
                is_new: false,
            });
        }

        let source = Path::new(&req.file_path);
        let hash = LibraryStore::sha256(source).map_err(io_error)?;

        // 迁移时原文件找不到的旧书：现在找到了，补做复制。
        if let Some(doc) = find(&conn, "file_path", &req.file_path)? {
            let copy = self
                .store
                .copy_in(source, &doc.id, &doc.file_name, &hash)
                .map_err(io_error)?;
            let tx = conn.unchecked_transaction()?;
            rewrite_book(
                &tx,
                &CopiedBook {
                    id: doc.id.clone(),
                    old_path: doc.file_path.clone(),
                    new_path: copy.to_string_lossy().into_owned(),
                    hash,
                },
            )?;
            tx.commit()?;
            return Ok(ImportedPdf {
                document: touch(&conn, &doc.id, req.total_pages)?,
                is_new: false,
            });
        }

        // 内容相同（哪怕换了名字）就复用已有的书。
        if let Some(doc) = find(&conn, "content_hash", &hash)? {
            return Ok(ImportedPdf {
                document: touch(&conn, &doc.id, req.total_pages)?,
                is_new: false,
            });
        }

        let id = Uuid::new_v4().to_string();
        let copy = self
            .store
            .copy_in(source, &id, &req.file_name, &hash)
            .map_err(io_error)?;
        let copy = copy.to_string_lossy().into_owned();
        let insert = || -> Result<(), LumenError> {
            let now = Utc::now().timestamp();
            let tx = conn.unchecked_transaction()?;
            tx.execute(
                "INSERT INTO pdf_documents
                    (id, file_path, file_name, total_pages, last_page, last_scroll_offset, opened_at, added_at, content_hash, original_path)
                 VALUES (?1, ?2, ?3, ?4, 0, 0.0, ?5, ?5, ?6, ?7)",
                params![id, copy, req.file_name, req.total_pages, now, hash, req.file_path],
            )?;
            // 之前从文库移除的书，笔记和单词指回了原文件；重新导入时接回新副本。
            for table in ["notes", "vocabulary_entries"] {
                tx.execute(
                    &format!(
                        "UPDATE {table} SET pdf_path = ?1, document_id = ?2
                         WHERE pdf_path = ?3 AND document_id IS NULL"
                    ),
                    params![copy, id, req.file_path],
                )?;
            }
            tx.commit()?;
            Ok(())
        };
        if let Err(error) = insert() {
            let _ = self.store.remove(&id);
            return Err(error);
        }
        Ok(ImportedPdf {
            document: touch(&conn, &id, req.total_pages)?,
            is_new: true,
        })
    }

    fn save_reading_position(
        &self,
        file_path: &str,
        page: u32,
        scroll_offset: f64,
    ) -> Result<(), LumenError> {
        let conn = self.pool.get()?;
        conn.execute(
            "UPDATE pdf_documents
             SET last_page = ?1, last_scroll_offset = ?2, opened_at = ?3
             WHERE file_path = ?4",
            params![page, scroll_offset, Utc::now().timestamp(), file_path],
        )?;
        Ok(())
    }

    fn list(&self) -> Result<Vec<PdfDocument>, LumenError> {
        let conn = self.pool.get()?;
        let mut stmt = conn.prepare(&format!(
            "SELECT {COLUMNS} FROM pdf_documents ORDER BY opened_at DESC"
        ))?;
        let docs = stmt
            .query_map([], row_to_doc)?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(docs)
    }

    /// 笔记和单词保留，并指回原文件（从笔记再次打开时会重新导入）。书库副本随后删除。
    fn delete(&self, file_path: &str) -> Result<(), LumenError> {
        let conn = self.pool.get()?;
        let Some(doc) = find(&conn, "file_path", file_path)? else {
            return Ok(());
        };
        let tx = conn.unchecked_transaction()?;
        let restored_path = doc.original_path.as_deref().unwrap_or(file_path);
        for table in ["notes", "vocabulary_entries"] {
            tx.execute(
                &format!(
                    "UPDATE {table} SET pdf_path = ?1, document_id = NULL
                     WHERE document_id = ?2 OR pdf_path = ?3"
                ),
                params![restored_path, doc.id, file_path],
            )?;
        }
        tx.execute("DELETE FROM pdf_documents WHERE id = ?1", params![doc.id])?;
        tx.commit()?;
        if is_library_path(file_path, &self.store.root_str()) {
            // 副本删不掉不影响移出文库；下次移除同一目录不会出错。
            let _ = self.store.remove(&doc.id);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::infrastructure::db::{create_pool, migration};
    use crate::infrastructure::library_store::tests::temp_dir;
    use std::fs;
    use std::path::PathBuf;

    struct Fixture {
        dir: PathBuf,
        repo: SqlitePdfDocumentRepo,
        pool: DbPool,
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.dir);
        }
    }

    fn fixture() -> Fixture {
        let dir = temp_dir("repo");
        let db_path = dir.join("data.db");
        let pool = create_pool(db_path.to_str().unwrap()).unwrap();
        migration::run(&pool.get().unwrap()).unwrap();
        let repo = SqlitePdfDocumentRepo::new(pool.clone(), LibraryStore::for_database(&db_path));
        Fixture { dir, repo, pool }
    }

    impl Fixture {
        fn write(&self, relative: &str, content: &[u8]) -> String {
            let path = self.dir.join("originals").join(relative);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(&path, content).unwrap();
            path.to_string_lossy().into_owned()
        }

        fn import(&self, path: &str) -> ImportedPdf {
            let file_name = Path::new(path)
                .file_name()
                .unwrap()
                .to_string_lossy()
                .into_owned();
            self.repo
                .import(UpsertPdfRequest {
                    file_path: path.into(),
                    file_name,
                    total_pages: 0,
                })
                .unwrap()
        }

        fn add_note(&self, id: &str, pdf_path: &str) {
            self.pool
                .get()
                .unwrap()
                .execute(
                    "INSERT INTO notes (id, pdf_path, pdf_name, page_index, content, note, created_at)
                     VALUES (?1, ?2, 'Book.pdf', 0, 'fake', '[\"fake note\"]', 1)",
                    params![id, pdf_path],
                )
                .unwrap();
        }

        fn note_link(&self, id: &str) -> (String, Option<String>) {
            self.pool
                .get()
                .unwrap()
                .query_row(
                    "SELECT pdf_path, document_id FROM notes WHERE id = ?1",
                    [id],
                    |row| Ok((row.get(0)?, row.get(1)?)),
                )
                .unwrap()
        }
    }

    #[test]
    fn import_copies_into_the_library_and_keeps_the_original() {
        let f = fixture();
        let original = f.write("Book.pdf", b"%PDF fake");

        let imported = f.import(&original);

        assert!(imported.is_new);
        let doc = imported.document;
        assert!(doc
            .file_path
            .ends_with(&format!("Library/{}/Book.pdf", doc.id)));
        assert_eq!(fs::read(&doc.file_path).unwrap(), b"%PDF fake");
        assert_eq!(doc.original_path.as_deref(), Some(original.as_str()));
        assert_eq!(fs::read(&original).unwrap(), b"%PDF fake");
    }

    #[test]
    fn same_content_under_a_new_name_reuses_the_book() {
        let f = fixture();
        let first = f.import(&f.write("Book.pdf", b"%PDF same")).document;

        let again = f.import(&f.write("Book.pdf", b"%PDF same"));
        let renamed = f.import(&f.write("moved/Renamed.pdf", b"%PDF same"));
        let from_library = f.import(&first.file_path);

        for reused in [again, renamed, from_library] {
            assert!(!reused.is_new);
            assert_eq!(reused.document.id, first.id);
        }
        assert_eq!(f.repo.list().unwrap().len(), 1);
    }

    #[test]
    fn same_name_with_different_content_is_a_new_book() {
        let f = fixture();
        let first = f.import(&f.write("a/Book.pdf", b"%PDF one")).document;

        let second = f.import(&f.write("b/Book.pdf", b"%PDF two"));

        assert!(second.is_new);
        assert_ne!(second.document.id, first.id);
        assert_ne!(second.document.file_path, first.file_path);
        assert_eq!(fs::read(&first.file_path).unwrap(), b"%PDF one");
        assert_eq!(fs::read(&second.document.file_path).unwrap(), b"%PDF two");
    }

    #[test]
    fn removing_a_book_deletes_its_copy_and_keeps_marks() {
        let f = fixture();
        let original = f.write("Book.pdf", b"%PDF fake");
        let doc = f.import(&original).document;
        f.add_note("n1", &doc.file_path);
        assert_eq!(
            f.note_link("n1"),
            (doc.file_path.clone(), Some(doc.id.clone()))
        );

        f.repo.delete(&doc.file_path).unwrap();

        assert!(!Path::new(&doc.file_path).exists());
        assert!(!Path::new(&doc.file_path).parent().unwrap().exists());
        assert!(Path::new(&original).exists(), "original kept");
        assert!(f.repo.list().unwrap().is_empty());
        assert_eq!(
            f.note_link("n1"),
            (original.clone(), None),
            "note points back to the original"
        );

        // 从笔记再次打开原文件：重新导入，笔记接回新副本。
        let again = f.import(&original);
        assert!(again.is_new);
        assert_eq!(
            f.note_link("n1"),
            (
                again.document.file_path.clone(),
                Some(again.document.id.clone())
            )
        );
    }

    #[test]
    fn a_legacy_book_whose_original_comes_back_is_copied_on_open() {
        let f = fixture();
        let original = f.write("Book.pdf", b"%PDF fake");
        let legacy = f
            .repo
            .upsert(UpsertPdfRequest {
                file_path: original.clone(),
                file_name: "Book.pdf".into(),
                total_pages: 12,
            })
            .unwrap();
        f.add_note("n1", &original);

        let imported = f.import(&original);

        assert!(!imported.is_new);
        assert_eq!(imported.document.id, legacy.id);
        assert_eq!(
            imported.document.total_pages, 12,
            "unknown page count keeps the old one"
        );
        assert!(imported.document.file_path.contains("/Library/"));
        assert_eq!(
            f.note_link("n1"),
            (imported.document.file_path, Some(legacy.id))
        );
    }
}
