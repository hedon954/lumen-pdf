use crate::error::LumenError;
use rusqlite::Connection;

pub fn run(conn: &Connection) -> Result<(), LumenError> {
    conn.execute_batch("PRAGMA journal_mode=WAL;")?;

    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS vocabulary_entries (
            id                  TEXT PRIMARY KEY,
            word                TEXT NOT NULL,
            sentence            TEXT NOT NULL,
            sentence_hash       TEXT NOT NULL,
            pdf_path            TEXT NOT NULL,
            pdf_name            TEXT NOT NULL,
            page_index          INTEGER NOT NULL,
            selection_bounds    TEXT NOT NULL DEFAULT '',
            phonetic            TEXT NOT NULL DEFAULT '',
            part_of_speech      TEXT NOT NULL DEFAULT '',
            context_translation TEXT NOT NULL DEFAULT '',
            context_explanation TEXT NOT NULL DEFAULT '',
            etymology           TEXT NOT NULL DEFAULT '',
            general_definition  TEXT NOT NULL DEFAULT '',
            context_sentence_translation TEXT NOT NULL DEFAULT '',
            translation_source  TEXT NOT NULL DEFAULT '',
            annotation_id       TEXT,
            created_at          INTEGER NOT NULL,
            query_count         INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE IF NOT EXISTS translation_cache (
            id              TEXT PRIMARY KEY,
            word            TEXT NOT NULL,
            sentence_hash   TEXT NOT NULL,
            target_language TEXT NOT NULL DEFAULT '',
            response_json   TEXT NOT NULL,
            source          TEXT NOT NULL DEFAULT 'llm',
            created_at      INTEGER NOT NULL,
            hit_count       INTEGER NOT NULL DEFAULT 0,
            UNIQUE(word, sentence_hash, target_language)
        );

        CREATE TABLE IF NOT EXISTS pdf_documents (
            id                 TEXT PRIMARY KEY,
            file_path          TEXT NOT NULL UNIQUE,
            file_name          TEXT NOT NULL,
            total_pages        INTEGER NOT NULL DEFAULT 0,
            last_page          INTEGER NOT NULL DEFAULT 0,
            last_scroll_offset REAL    NOT NULL DEFAULT 0.0,
            opened_at          INTEGER NOT NULL,
            added_at           INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS notes (
            id            TEXT PRIMARY KEY,
            pdf_path      TEXT NOT NULL,
            pdf_name      TEXT NOT NULL,
            page_index    INTEGER NOT NULL,
            content       TEXT NOT NULL,
            note          TEXT NOT NULL DEFAULT '',
            bounds_str    TEXT NOT NULL DEFAULT '',
            page_markups  TEXT NOT NULL DEFAULT '',
            created_at    INTEGER NOT NULL
        );
    ",
    )?;

    // Add query_count to existing databases (ignore error if column already exists)
    let _ = conn.execute_batch(
        "ALTER TABLE vocabulary_entries ADD COLUMN query_count INTEGER NOT NULL DEFAULT 0;",
    );
    let _ = conn.execute_batch(
        "ALTER TABLE vocabulary_entries ADD COLUMN context_sentence_translation TEXT NOT NULL DEFAULT '';"
    );
    add_column_if_missing(
        conn,
        "vocabulary_entries",
        "etymology",
        "ALTER TABLE vocabulary_entries ADD COLUMN etymology TEXT NOT NULL DEFAULT '';",
    )?;
    add_column_if_missing(
        conn,
        "notes",
        "page_markups",
        "ALTER TABLE notes ADD COLUMN page_markups TEXT NOT NULL DEFAULT '';",
    )?;

    migrate_translation_cache_language_key(conn)?;
    add_library_columns(conn)?;
    add_shelves(conn)?;

    Ok(())
}

fn add_shelves(conn: &Connection) -> Result<(), LumenError> {
    conn.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS shelves (
            id TEXT PRIMARY KEY,
            parent_id TEXT,
            name TEXT NOT NULL,
            position INTEGER NOT NULL,
            created_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_shelves_parent ON shelves(parent_id);
        ",
    )?;
    add_column_if_missing(
        conn,
        "pdf_documents",
        "shelf_id",
        "ALTER TABLE pdf_documents ADD COLUMN shelf_id TEXT;",
    )?;
    add_column_if_missing(
        conn,
        "pdf_documents",
        "position",
        "ALTER TABLE pdf_documents ADD COLUMN position INTEGER NOT NULL DEFAULT 0;",
    )?;
    Ok(())
}

/// 书库需要的列：副本的内容哈希和原文件路径；笔记和单词记下所属文档 id。
/// 新写入的笔记和单词由触发器按 `pdf_path` 填上 `document_id`。
fn add_library_columns(conn: &Connection) -> Result<(), LumenError> {
    add_column_if_missing(
        conn,
        "pdf_documents",
        "content_hash",
        "ALTER TABLE pdf_documents ADD COLUMN content_hash TEXT;",
    )?;
    add_column_if_missing(
        conn,
        "pdf_documents",
        "original_path",
        "ALTER TABLE pdf_documents ADD COLUMN original_path TEXT;",
    )?;
    add_column_if_missing(
        conn,
        "notes",
        "document_id",
        "ALTER TABLE notes ADD COLUMN document_id TEXT;",
    )?;
    add_column_if_missing(
        conn,
        "vocabulary_entries",
        "document_id",
        "ALTER TABLE vocabulary_entries ADD COLUMN document_id TEXT;",
    )?;
    conn.execute_batch(
        "
        CREATE INDEX IF NOT EXISTS idx_pdf_documents_content_hash ON pdf_documents(content_hash);
        CREATE TRIGGER IF NOT EXISTS notes_fill_document_id AFTER INSERT ON notes
        WHEN NEW.document_id IS NULL
        BEGIN
            UPDATE notes SET document_id = (SELECT id FROM pdf_documents WHERE file_path = NEW.pdf_path)
            WHERE id = NEW.id;
        END;
        CREATE TRIGGER IF NOT EXISTS vocabulary_fill_document_id AFTER INSERT ON vocabulary_entries
        WHEN NEW.document_id IS NULL
        BEGIN
            UPDATE vocabulary_entries SET document_id = (SELECT id FROM pdf_documents WHERE file_path = NEW.pdf_path)
            WHERE id = NEW.id;
        END;
        ",
    )?;
    Ok(())
}

fn add_column_if_missing(
    conn: &Connection,
    table: &str,
    column: &str,
    statement: &str,
) -> Result<(), LumenError> {
    let mut stmt = conn.prepare(&format!("PRAGMA table_info({table})"))?;
    let columns = stmt
        .query_map([], |row| row.get::<_, String>(1))?
        .collect::<Result<Vec<_>, _>>()?;
    if !columns.iter().any(|existing| existing == column) {
        conn.execute_batch(statement)?;
    }
    Ok(())
}

fn migrate_translation_cache_language_key(conn: &Connection) -> Result<(), LumenError> {
    let mut stmt = conn.prepare("PRAGMA table_info(translation_cache)")?;
    let columns = stmt
        .query_map([], |row| row.get::<_, String>(1))?
        .collect::<Result<Vec<_>, _>>()?;
    if columns.iter().any(|column| column == "target_language") {
        return Ok(());
    }

    conn.execute_batch(
        "
        ALTER TABLE translation_cache RENAME TO translation_cache_old;

        CREATE TABLE translation_cache (
            id              TEXT PRIMARY KEY,
            word            TEXT NOT NULL,
            sentence_hash   TEXT NOT NULL,
            target_language TEXT NOT NULL DEFAULT '',
            response_json   TEXT NOT NULL,
            source          TEXT NOT NULL DEFAULT 'llm',
            created_at      INTEGER NOT NULL,
            hit_count       INTEGER NOT NULL DEFAULT 0,
            UNIQUE(word, sentence_hash, target_language)
        );

        INSERT INTO translation_cache
            (id, word, sentence_hash, target_language, response_json, source, created_at, hit_count)
        SELECT id, word, sentence_hash, '', response_json, source, created_at, hit_count
        FROM translation_cache_old;

        DROP TABLE translation_cache_old;
        ",
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adds_etymology_to_existing_vocabulary_table_idempotently() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "
            CREATE TABLE vocabulary_entries (
                id TEXT PRIMARY KEY,
                word TEXT NOT NULL,
                sentence TEXT NOT NULL,
                sentence_hash TEXT NOT NULL,
                pdf_path TEXT NOT NULL,
                pdf_name TEXT NOT NULL,
                page_index INTEGER NOT NULL,
                selection_bounds TEXT NOT NULL DEFAULT '',
                phonetic TEXT NOT NULL DEFAULT '',
                part_of_speech TEXT NOT NULL DEFAULT '',
                context_translation TEXT NOT NULL DEFAULT '',
                context_explanation TEXT NOT NULL DEFAULT '',
                general_definition TEXT NOT NULL DEFAULT '',
                context_sentence_translation TEXT NOT NULL DEFAULT '',
                translation_source TEXT NOT NULL DEFAULT '',
                annotation_id TEXT,
                created_at INTEGER NOT NULL,
                query_count INTEGER NOT NULL DEFAULT 0
            );
            ",
        )
        .unwrap();

        run(&conn).unwrap();
        run(&conn).unwrap();

        let mut stmt = conn
            .prepare("PRAGMA table_info(vocabulary_entries)")
            .unwrap();
        let columns = stmt
            .query_map([], |row| row.get::<_, String>(1))
            .unwrap()
            .collect::<Result<Vec<_>, _>>()
            .unwrap();
        assert_eq!(
            columns
                .iter()
                .filter(|column| column.as_str() == "etymology")
                .count(),
            1
        );
    }

    #[test]
    fn adds_page_markups_to_existing_notes_table_idempotently() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "
            CREATE TABLE notes (
                id TEXT PRIMARY KEY,
                pdf_path TEXT NOT NULL,
                pdf_name TEXT NOT NULL,
                page_index INTEGER NOT NULL,
                content TEXT NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                bounds_str TEXT NOT NULL DEFAULT '',
                created_at INTEGER NOT NULL
            );
            INSERT INTO notes
                (id, pdf_path, pdf_name, page_index, content, note, bounds_str, created_at)
            VALUES
                ('legacy', '/tmp/book.pdf', 'book.pdf', 3, 'source', 'note', '{{1, 2}, {3, 4}}', 1);
            ",
        )
        .unwrap();

        run(&conn).unwrap();
        run(&conn).unwrap();

        let (count, page_markups): (i64, String) = conn
            .query_row(
                "SELECT COUNT(*), page_markups FROM notes WHERE id = 'legacy'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(count, 1);
        assert_eq!(page_markups, "");
    }

    #[test]
    fn shelves_leave_existing_books_on_the_root() {
        let conn = Connection::open_in_memory().unwrap();
        conn.execute_batch(
            "
            CREATE TABLE pdf_documents (
                id TEXT PRIMARY KEY,
                file_path TEXT NOT NULL UNIQUE,
                file_name TEXT NOT NULL,
                total_pages INTEGER NOT NULL DEFAULT 0,
                last_page INTEGER NOT NULL DEFAULT 0,
                last_scroll_offset REAL NOT NULL DEFAULT 0.0,
                opened_at INTEGER NOT NULL,
                added_at INTEGER NOT NULL
            );
            INSERT INTO pdf_documents
                (id, file_path, file_name, opened_at, added_at)
            VALUES
                ('book', '/tmp/book.pdf', 'book.pdf', 1, 1);
            ",
        )
        .unwrap();

        run(&conn).unwrap();
        run(&conn).unwrap();

        let (shelf_id, position): (Option<String>, i64) = conn
            .query_row(
                "SELECT shelf_id, position FROM pdf_documents WHERE id = 'book'",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        let shelf_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM shelves", [], |row| row.get(0))
            .unwrap();
        assert_eq!(shelf_id, None);
        assert_eq!(position, 0);
        assert_eq!(shelf_count, 0);
    }
}
