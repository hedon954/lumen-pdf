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

    migrate_translation_cache_language_key(conn)?;

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
}
