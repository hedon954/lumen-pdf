//! 把文库里的书复制进书库，并改写数据库里的路径。
//!
//! 一次性迁移：先在 `data.db` 旁边做带时间戳的备份，再把每本书复制进书库（在事务外，
//! 只写书库目录），最后在**一个事务**里改写 `pdf_documents` / `notes` / `vocabulary_entries`
//! 的路径并填上 `document_id`。原文件找不到的书留在原处，下次启动再试。
//! 已在书库里的书不再处理，所以中途崩溃后重跑不会重复复制或重复改写。

use crate::domain::library::service::is_library_path;
use crate::error::LumenError;
use crate::infrastructure::library_store::LibraryStore;
use chrono::Local;
use rusqlite::{params, Connection};
use std::path::{Path, PathBuf};

#[derive(Debug, Default, PartialEq, Eq)]
pub struct LibraryMigrationReport {
    pub copied: usize,
    /// 原文件找不到，留在文库里等下次。
    pub missing: usize,
    /// 原文件在，但复制或校验失败。
    pub failed: usize,
    pub backup: Option<PathBuf>,
}

/// 已复制进书库、等待写进数据库的一本书。
#[derive(Debug, Clone)]
pub struct CopiedBook {
    pub id: String,
    pub old_path: String,
    pub new_path: String,
    pub hash: String,
}

struct PendingBook {
    id: String,
    file_path: String,
    file_name: String,
}

pub(crate) fn io_error(error: std::io::Error) -> LumenError {
    LumenError::DatabaseError {
        message: format!("library: {error}"),
    }
}

/// 启动时调用。没有需要复制的书时不做备份。
pub fn migrate(
    conn: &Connection,
    store: &LibraryStore,
    db_path: &Path,
) -> Result<LibraryMigrationReport, LumenError> {
    let pending = pending_books(conn, store)?;
    let mut report = LibraryMigrationReport::default();
    if pending
        .iter()
        .any(|book| Path::new(&book.file_path).is_file())
    {
        report.backup = Some(backup_database(conn, db_path)?);
    }
    let copied = copy_pending(conn, store, &mut report)?;
    commit_copies(conn, &copied)?;
    report.copied = copied.len();
    Ok(report)
}

/// 第一步：把还没进书库的书复制进去。只写书库目录，不动数据库。
pub fn copy_pending(
    conn: &Connection,
    store: &LibraryStore,
    report: &mut LibraryMigrationReport,
) -> Result<Vec<CopiedBook>, LumenError> {
    let mut copied = Vec::new();
    for book in pending_books(conn, store)? {
        let source = Path::new(&book.file_path);
        if !source.is_file() {
            report.missing += 1;
            continue;
        }
        let result = LibraryStore::sha256(source).and_then(|hash| {
            store
                .copy_in(source, &book.id, &book.file_name, &hash)
                .map(|path| (hash, path))
        });
        match result {
            Ok((hash, path)) => copied.push(CopiedBook {
                id: book.id,
                old_path: book.file_path,
                new_path: path.to_string_lossy().into_owned(),
                hash,
            }),
            Err(_) => report.failed += 1,
        }
    }
    Ok(copied)
}

/// 第二步：一个事务里改写路径并填 `document_id`。
pub fn commit_copies(conn: &Connection, copied: &[CopiedBook]) -> Result<(), LumenError> {
    let tx = conn.unchecked_transaction()?;
    for book in copied {
        rewrite_book(&tx, book)?;
    }
    fill_document_ids(&tx)?;
    tx.commit()?;
    Ok(())
}

/// 一本书改用书库副本：文档、笔记、单词的路径一起改，原路径记在 `original_path`。
/// 条件里带旧路径，已经改写过的行不会再改一次。
pub(crate) fn rewrite_book(conn: &Connection, book: &CopiedBook) -> Result<(), LumenError> {
    conn.execute(
        "UPDATE pdf_documents
         SET file_path = ?1, content_hash = ?2, original_path = COALESCE(original_path, ?3)
         WHERE id = ?4 AND file_path = ?3",
        params![book.new_path, book.hash, book.old_path, book.id],
    )?;
    for table in ["notes", "vocabulary_entries"] {
        conn.execute(
            &format!("UPDATE {table} SET pdf_path = ?1, document_id = ?2 WHERE pdf_path = ?3"),
            params![book.new_path, book.id, book.old_path],
        )?;
    }
    Ok(())
}

/// 按路径给还没有 `document_id` 的笔记和单词补上（包括原文件找不到的书）。
fn fill_document_ids(conn: &Connection) -> Result<(), LumenError> {
    for table in ["notes", "vocabulary_entries"] {
        conn.execute(
            &format!(
                "UPDATE {table} SET document_id =
                    (SELECT id FROM pdf_documents WHERE pdf_documents.file_path = {table}.pdf_path)
                 WHERE document_id IS NULL"
            ),
            [],
        )?;
    }
    Ok(())
}

fn pending_books(conn: &Connection, store: &LibraryStore) -> Result<Vec<PendingBook>, LumenError> {
    let root = store.root_str();
    let mut stmt = conn.prepare("SELECT id, file_path, file_name FROM pdf_documents")?;
    let books = stmt
        .query_map([], |row| {
            Ok(PendingBook {
                id: row.get(0)?,
                file_path: row.get(1)?,
                file_name: row.get(2)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(books
        .into_iter()
        .filter(|book| !is_library_path(&book.file_path, &root))
        .collect())
}

/// `data.db.before-library-<时间>`，用 `VACUUM INTO` 得到包含 WAL 内容的一致副本。
fn backup_database(conn: &Connection, db_path: &Path) -> Result<PathBuf, LumenError> {
    let name = db_path
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| "data.db".into());
    let stamp = Local::now().format("%Y%m%d-%H%M%S");
    let base = db_path.with_file_name(format!("{name}.before-library-{stamp}"));
    let mut target = base.clone();
    let mut attempt = 1;
    while target.exists() {
        attempt += 1;
        target = PathBuf::from(format!("{}-{attempt}", base.to_string_lossy()));
    }
    conn.execute("VACUUM INTO ?1", params![target.to_string_lossy()])?;
    Ok(target)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::infrastructure::db::migration;
    use crate::infrastructure::library_store::tests::temp_dir;
    use std::fs;

    struct Fixture {
        dir: PathBuf,
        db_path: PathBuf,
        conn: Connection,
        store: LibraryStore,
    }

    impl Drop for Fixture {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.dir);
        }
    }

    fn fixture() -> Fixture {
        let dir = temp_dir("migration");
        let db_path = dir.join("data.db");
        let conn = Connection::open(&db_path).unwrap();
        migration::run(&conn).unwrap();
        let store = LibraryStore::for_database(&db_path);
        Fixture {
            dir,
            db_path,
            conn,
            store,
        }
    }

    impl Fixture {
        /// 假 PDF 和它的文库记录、一条笔记、一个单词。
        fn add_book(&self, id: &str, name: &str, content: Option<&[u8]>) -> String {
            let path = self.dir.join("originals").join(name);
            if let Some(content) = content {
                fs::create_dir_all(path.parent().unwrap()).unwrap();
                fs::write(&path, content).unwrap();
            }
            let path = path.to_string_lossy().into_owned();
            self.conn
                .execute(
                    "INSERT INTO pdf_documents (id, file_path, file_name, total_pages, last_page, last_scroll_offset, opened_at, added_at)
                     VALUES (?1, ?2, ?3, 10, 4, 0.5, 100, 50)",
                    params![id, path, name],
                )
                .unwrap();
            self.conn
                .execute(
                    "INSERT INTO notes (id, pdf_path, pdf_name, page_index, content, note, bounds_str, page_markups, created_at)
                     VALUES (?1, ?2, ?3, 3, 'fake highlight', '[\"fake note\"]', '1,2,3,4', 'markups', 60)",
                    params![format!("note-{id}"), path, name],
                )
                .unwrap();
            self.conn
                .execute(
                    "INSERT INTO vocabulary_entries (id, word, sentence, sentence_hash, pdf_path, pdf_name, page_index, annotation_id, created_at)
                     VALUES (?1, 'word', 'fake sentence', 'h', ?2, ?3, 2, 'ann-1', 70)",
                    params![format!("word-{id}"), path, name],
                )
                .unwrap();
            path
        }

        fn book_path(&self, id: &str) -> String {
            self.conn
                .query_row(
                    "SELECT file_path FROM pdf_documents WHERE id = ?1",
                    [id],
                    |row| row.get(0),
                )
                .unwrap()
        }

        /// 笔记和单词除路径和 document_id 外的所有字段。
        fn marks(&self) -> Vec<String> {
            let mut marks = Vec::new();
            let mut stmt = self
                .conn
                .prepare("SELECT id, pdf_name, page_index, content, note, bounds_str, page_markups, created_at FROM notes ORDER BY id")
                .unwrap();
            let rows = stmt
                .query_map([], |row| {
                    Ok(format!(
                        "{}|{}|{}|{}|{}|{}|{}|{}",
                        row.get::<_, String>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, i64>(2)?,
                        row.get::<_, String>(3)?,
                        row.get::<_, String>(4)?,
                        row.get::<_, String>(5)?,
                        row.get::<_, String>(6)?,
                        row.get::<_, i64>(7)?
                    ))
                })
                .unwrap();
            marks.extend(rows.map(Result::unwrap));
            let mut stmt = self
                .conn
                .prepare("SELECT id, word, pdf_name, page_index, annotation_id, created_at FROM vocabulary_entries ORDER BY id")
                .unwrap();
            let rows = stmt
                .query_map([], |row| {
                    Ok(format!(
                        "{}|{}|{}|{}|{:?}|{}",
                        row.get::<_, String>(0)?,
                        row.get::<_, String>(1)?,
                        row.get::<_, String>(2)?,
                        row.get::<_, i64>(3)?,
                        row.get::<_, Option<String>>(4)?,
                        row.get::<_, i64>(5)?
                    ))
                })
                .unwrap();
            marks.extend(rows.map(Result::unwrap));
            marks
        }

        fn mark_links(&self, id: &str) -> Vec<(String, Option<String>)> {
            ["notes", "vocabulary_entries"]
                .iter()
                .map(|table| {
                    self.conn
                        .query_row(
                            &format!("SELECT pdf_path, document_id FROM {table} WHERE id LIKE '%-' || ?1"),
                            [id],
                            |row| Ok((row.get(0)?, row.get(1)?)),
                        )
                        .unwrap()
                })
                .collect()
        }

        fn backups(&self) -> usize {
            fs::read_dir(&self.dir)
                .unwrap()
                .filter(|entry| {
                    entry
                        .as_ref()
                        .unwrap()
                        .file_name()
                        .to_string_lossy()
                        .contains("before-library")
                })
                .count()
        }
    }

    #[test]
    fn migration_copies_books_and_keeps_marks_and_links() {
        let f = fixture();
        let original = f.add_book("a", "Book A.pdf", Some(b"%PDF fake A"));
        f.add_book("b", "Book B.pdf", Some(b"%PDF fake B"));
        // 旧数据库里笔记和单词还没有 document_id。
        f.conn
            .execute_batch("UPDATE notes SET document_id = NULL; UPDATE vocabulary_entries SET document_id = NULL;")
            .unwrap();
        let marks_before = f.marks();

        let report = migrate(&f.conn, &f.store, &f.db_path).unwrap();

        assert_eq!(report.copied, 2);
        assert_eq!((report.missing, report.failed), (0, 0));
        let copy = f.book_path("a");
        assert_eq!(copy, f.store.root().join("a/Book A.pdf").to_string_lossy());
        assert_eq!(fs::read(&copy).unwrap(), b"%PDF fake A");
        assert_eq!(
            fs::read(&original).unwrap(),
            b"%PDF fake A",
            "original untouched"
        );
        assert_eq!(f.marks(), marks_before, "marks unchanged");
        assert_eq!(
            f.mark_links("a"),
            vec![(copy.clone(), Some("a".into())), (copy, Some("a".into()))]
        );
        let (page, offset, original_path, hash): (i64, f64, String, String) = f
            .conn
            .query_row(
                "SELECT last_page, last_scroll_offset, original_path, content_hash FROM pdf_documents WHERE id = 'a'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?)),
            )
            .unwrap();
        assert_eq!((page, offset), (4, 0.5));
        assert_eq!(original_path, original);
        assert_eq!(hash, LibraryStore::sha256(Path::new(&original)).unwrap());

        let backup = Connection::open(report.backup.unwrap()).unwrap();
        let backed_up: String = backup
            .query_row(
                "SELECT file_path FROM pdf_documents WHERE id = 'a'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(backed_up, original, "backup holds the old paths");
    }

    #[test]
    fn missing_original_stays_and_the_others_still_migrate() {
        let f = fixture();
        let missing = f.add_book("gone", "Gone.pdf", None);
        f.add_book("here", "Here.pdf", Some(b"%PDF fake"));
        f.conn
            .execute_batch("UPDATE notes SET document_id = NULL; UPDATE vocabulary_entries SET document_id = NULL;")
            .unwrap();

        let report = migrate(&f.conn, &f.store, &f.db_path).unwrap();

        assert_eq!((report.copied, report.missing), (1, 1));
        assert_eq!(f.book_path("gone"), missing);
        assert_eq!(
            f.mark_links("gone"),
            vec![
                (missing.clone(), Some("gone".into())),
                (missing, Some("gone".into()))
            ]
        );
        assert!(is_library_path(&f.book_path("here"), &f.store.root_str()));
    }

    #[test]
    fn crash_before_commit_then_rerun_neither_duplicates_nor_rewrites_twice() {
        let f = fixture();
        f.add_book("a", "Book.pdf", Some(b"%PDF fake"));
        let marks_before = f.marks();
        // 第一次：备份、复制完成后在提交前崩溃。
        let mut crashed = LibraryMigrationReport::default();
        backup_database(&f.conn, &f.db_path).unwrap();
        copy_pending(&f.conn, &f.store, &mut crashed).unwrap();
        assert!(!is_library_path(&f.book_path("a"), &f.store.root_str()));

        let rerun = migrate(&f.conn, &f.store, &f.db_path).unwrap();
        let again = migrate(&f.conn, &f.store, &f.db_path).unwrap();

        assert_eq!(rerun.copied, 1);
        assert_eq!(
            again,
            LibraryMigrationReport::default(),
            "nothing left to do"
        );
        assert_eq!(fs::read_dir(f.store.root()).unwrap().count(), 1);
        assert_eq!(fs::read_dir(f.store.root().join("a")).unwrap().count(), 1);
        let copy = f.book_path("a");
        assert_eq!(copy, f.store.root().join("a/Book.pdf").to_string_lossy());
        assert_eq!(f.mark_links("a")[0].0, copy);
        assert_eq!(f.marks(), marks_before);
        assert_eq!(f.backups(), 2, "the first backup is kept");
    }

    #[test]
    fn migration_is_idempotent_for_schema_and_triggers() {
        let f = fixture();
        migration::run(&f.conn).unwrap();
        migration::run(&f.conn).unwrap();
        f.add_book("a", "Book.pdf", Some(b"%PDF fake"));
        // 触发器在插入时按路径填上 document_id。
        assert_eq!(f.mark_links("a")[0].1.as_deref(), Some("a"));
    }
}
