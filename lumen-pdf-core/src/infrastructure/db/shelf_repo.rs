use crate::domain::library::service::is_library_path;
use crate::domain::pdf_document::entity::PdfDocument;
use crate::domain::shelf::entity::{
    DeletionPreview, Shelf, ShelfChild, ShelfItemKind, ShelfNode, ShelfPage, ShelfPlacement,
};
use crate::domain::shelf::repository::ShelfRepository;
use crate::domain::shelf::service::subtree_ids;
use crate::error::LumenError;
use crate::infrastructure::db::DbPool;
use crate::infrastructure::library_store::LibraryStore;
use chrono::Utc;
use rusqlite::{params, Connection, OptionalExtension};
use uuid::Uuid;

const DOC_COLUMNS: &str =
    "id, file_path, file_name, total_pages, last_page, last_scroll_offset, opened_at, added_at, original_path, position";

pub struct SqliteShelfRepo {
    pool: DbPool,
    store: LibraryStore,
}

impl SqliteShelfRepo {
    pub fn new(pool: DbPool, store: LibraryStore) -> Self {
        Self { pool, store }
    }
}

struct LocatedDocument {
    id: String,
    file_path: String,
    original_path: Option<String>,
}

impl ShelfRepository for SqliteShelfRepo {
    fn page(&self, parent_id: Option<&str>) -> Result<ShelfPage, LumenError> {
        let conn = self.pool.get()?;
        let crumbs = match parent_id {
            Some(id) => crumbs(&conn, id)?,
            None => Vec::new(),
        };
        let mut placed: Vec<(i32, String, ShelfChild)> = Vec::new();
        for shelf in shelves_in(&conn, parent_id)? {
            placed.push((
                shelf.position,
                shelf.name.clone(),
                ShelfChild::Shelf { shelf },
            ));
        }
        for (position, name, document) in documents_in(&conn, parent_id)? {
            placed.push((position, name, ShelfChild::Document { document }));
        }
        placed.sort_by(|left, right| left.0.cmp(&right.0).then(left.1.cmp(&right.1)));
        Ok(ShelfPage {
            crumbs,
            children: placed.into_iter().map(|(_, _, child)| child).collect(),
        })
    }

    fn nodes(&self) -> Result<Vec<ShelfNode>, LumenError> {
        let conn = self.pool.get()?;
        let mut stmt = conn.prepare("SELECT id, parent_id FROM shelves")?;
        let nodes = stmt
            .query_map([], |row| {
                Ok(ShelfNode {
                    id: row.get(0)?,
                    parent_id: row.get(1)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(nodes)
    }

    fn create(&self, parent_id: Option<&str>, name: &str) -> Result<Shelf, LumenError> {
        let conn = self.pool.get()?;
        let id = Uuid::new_v4().to_string();
        let position = next_position(&conn, parent_id)?;
        let created_at = Utc::now().timestamp();
        conn.execute(
            "INSERT INTO shelves (id, parent_id, name, position, created_at) VALUES (?1, ?2, ?3, ?4, ?5)",
            params![id, parent_id, name, position, created_at],
        )?;
        Ok(Shelf {
            id,
            parent_id: parent_id.map(str::to_string),
            name: name.to_string(),
            position,
            book_count: 0,
        })
    }

    fn rename(&self, id: &str, name: &str) -> Result<Shelf, LumenError> {
        let conn = self.pool.get()?;
        let changed = conn.execute(
            "UPDATE shelves SET name = ?1 WHERE id = ?2",
            params![name, id],
        )?;
        if changed == 0 {
            return Err(LumenError::NotFound {
                message: "找不到这个书架".into(),
            });
        }
        load_shelf(&conn, id)?.ok_or_else(|| LumenError::NotFound {
            message: "找不到这个书架".into(),
        })
    }

    fn move_shelf(&self, id: &str, parent_id: Option<&str>) -> Result<(), LumenError> {
        let conn = self.pool.get()?;
        let position = next_position(&conn, parent_id)?;
        let changed = conn.execute(
            "UPDATE shelves SET parent_id = ?1, position = ?2 WHERE id = ?3",
            params![parent_id, position, id],
        )?;
        if changed == 0 {
            return Err(LumenError::NotFound {
                message: "找不到这个书架".into(),
            });
        }
        Ok(())
    }

    fn move_document(&self, id: &str, parent_id: Option<&str>) -> Result<(), LumenError> {
        self.place_document(id, parent_id)
    }

    fn reorder(&self, parent_id: Option<&str>, order: &[ShelfPlacement]) -> Result<(), LumenError> {
        let conn = self.pool.get()?;
        let tx = conn.unchecked_transaction()?;
        for (index, item) in order.iter().enumerate() {
            let position = i32::try_from(index).unwrap_or(i32::MAX);
            let changed = match item.kind {
                ShelfItemKind::Shelf => tx.execute(
                    "UPDATE shelves SET position = ?1 WHERE id = ?2 AND parent_id IS ?3",
                    params![position, item.id, parent_id],
                )?,
                ShelfItemKind::Document => tx.execute(
                    "UPDATE pdf_documents SET position = ?1 WHERE id = ?2 AND shelf_id IS ?3",
                    params![position, item.id, parent_id],
                )?,
            };
            if changed == 0 {
                return Err(LumenError::NotFound {
                    message: "有一项已经不在这一层".into(),
                });
            }
        }
        tx.commit()?;
        Ok(())
    }

    fn place_document(&self, id: &str, parent_id: Option<&str>) -> Result<(), LumenError> {
        let conn = self.pool.get()?;
        let position = next_position(&conn, parent_id)?;
        let changed = conn.execute(
            "UPDATE pdf_documents SET shelf_id = ?1, position = ?2 WHERE id = ?3",
            params![parent_id, position, id],
        )?;
        if changed == 0 {
            return Err(LumenError::NotFound {
                message: "找不到这本书".into(),
            });
        }
        Ok(())
    }

    fn preview_documents(&self, ids: &[String]) -> Result<DeletionPreview, LumenError> {
        let conn = self.pool.get()?;
        preview_for(&conn, &documents_by_ids(&conn, ids)?)
    }

    fn preview_shelf(&self, id: &str) -> Result<DeletionPreview, LumenError> {
        let conn = self.pool.get()?;
        preview_for(&conn, &documents_in_shelf(&conn, id)?)
    }

    fn preview_library(&self) -> Result<DeletionPreview, LumenError> {
        let conn = self.pool.get()?;
        let docs = all_documents(&conn)?;
        preview_for(&conn, &docs)
    }

    fn delete_documents(&self, ids: &[String]) -> Result<(), LumenError> {
        let conn = self.pool.get()?;
        let docs = documents_by_ids(&conn, ids)?;
        remove_documents(&conn, &docs)?;
        remove_copies(&self.store, &docs);
        Ok(())
    }

    fn delete_shelf(&self, id: &str) -> Result<(), LumenError> {
        let shelf_ids = subtree_ids(id, &self.nodes()?);
        let conn = self.pool.get()?;
        let docs = documents_in_shelf(&conn, id)?;
        remove_documents(&conn, &docs)?;
        delete_shelves(&conn, &shelf_ids)?;
        remove_copies(&self.store, &docs);
        Ok(())
    }

    fn delete_library(&self) -> Result<(), LumenError> {
        let conn = self.pool.get()?;
        let docs = all_documents(&conn)?;
        remove_documents(&conn, &docs)?;
        conn.execute("DELETE FROM shelves", [])?;
        remove_copies(&self.store, &docs);
        Ok(())
    }

    fn delete_if_empty(&self, id: &str) -> Result<(), LumenError> {
        let conn = self.pool.get()?;
        let docs = documents_in_shelf(&conn, id)?;
        if docs.is_empty() && child_shelf_count(&conn, id)? == 0 {
            conn.execute("DELETE FROM shelves WHERE id = ?1", params![id])?;
        }
        Ok(())
    }
}

fn child_shelf_count(conn: &Connection, id: &str) -> Result<i64, LumenError> {
    Ok(conn.query_row(
        "SELECT COUNT(*) FROM shelves WHERE parent_id = ?1",
        params![id],
        |row| row.get(0),
    )?)
}

fn crumbs(conn: &Connection, id: &str) -> Result<Vec<Shelf>, LumenError> {
    let mut chain = Vec::new();
    let mut current = Some(id.to_string());
    for _ in 0..64 {
        let Some(id) = current else { break };
        let Some(shelf) = load_shelf(conn, &id)? else {
            break;
        };
        current = shelf.parent_id.clone();
        chain.push(shelf);
    }
    chain.reverse();
    Ok(chain)
}

fn load_shelf(conn: &Connection, id: &str) -> Result<Option<Shelf>, LumenError> {
    Ok(conn
        .query_row(
            "SELECT id, parent_id, name, position, (SELECT COUNT(*) FROM pdf_documents WHERE shelf_id = shelves.id) FROM shelves WHERE id = ?1",
            params![id],
            row_to_shelf,
        )
        .optional()?)
}

fn shelves_in(conn: &Connection, parent_id: Option<&str>) -> Result<Vec<Shelf>, LumenError> {
    let mut stmt = conn.prepare(
        "SELECT id, parent_id, name, position, (SELECT COUNT(*) FROM pdf_documents WHERE shelf_id = shelves.id) FROM shelves WHERE parent_id IS ?1 ORDER BY position, name",
    )?;
    let shelves = stmt
        .query_map(params![parent_id], row_to_shelf)?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(shelves)
}

fn documents_in(
    conn: &Connection,
    parent_id: Option<&str>,
) -> Result<Vec<(i32, String, PdfDocument)>, LumenError> {
    let mut stmt = conn.prepare(&format!(
        "SELECT {DOC_COLUMNS} FROM pdf_documents WHERE shelf_id IS ?1 ORDER BY position, file_name"
    ))?;
    let docs = stmt
        .query_map(params![parent_id], |row| {
            let document = row_to_doc(row)?;
            let position = row.get::<_, i64>(9)? as i32;
            Ok((position, document.file_name.clone(), document))
        })?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(docs)
}

fn next_position(conn: &Connection, parent_id: Option<&str>) -> Result<i32, LumenError> {
    let shelf_max: i64 = conn.query_row(
        "SELECT COALESCE(MAX(position), -1) FROM shelves WHERE parent_id IS ?1",
        params![parent_id],
        |row| row.get(0),
    )?;
    let doc_max: i64 = conn.query_row(
        "SELECT COALESCE(MAX(position), -1) FROM pdf_documents WHERE shelf_id IS ?1",
        params![parent_id],
        |row| row.get(0),
    )?;
    Ok(i32::try_from(shelf_max.max(doc_max) + 1).unwrap_or(i32::MAX))
}

fn documents_by_ids(conn: &Connection, ids: &[String]) -> Result<Vec<LocatedDocument>, LumenError> {
    let mut docs = Vec::new();
    for id in ids {
        if let Some(doc) = conn
            .query_row(
                "SELECT id, file_path, original_path FROM pdf_documents WHERE id = ?1",
                params![id],
                row_to_located,
            )
            .optional()?
        {
            docs.push(doc);
        }
    }
    Ok(docs)
}

fn documents_in_shelf(
    conn: &Connection,
    shelf_id: &str,
) -> Result<Vec<LocatedDocument>, LumenError> {
    let mut stmt = conn.prepare("SELECT id, parent_id FROM shelves")?;
    let nodes = stmt
        .query_map([], |row| {
            Ok(ShelfNode {
                id: row.get(0)?,
                parent_id: row.get(1)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;
    let shelf_ids = subtree_ids(shelf_id, &nodes);
    let mut docs = Vec::new();
    for id in shelf_ids {
        let mut stmt = conn.prepare(
            "SELECT id, file_path, original_path FROM pdf_documents WHERE shelf_id = ?1",
        )?;
        let found = stmt
            .query_map(params![id], row_to_located)?
            .collect::<Result<Vec<_>, _>>()?;
        docs.extend(found);
    }
    Ok(docs)
}

fn all_documents(conn: &Connection) -> Result<Vec<LocatedDocument>, LumenError> {
    let mut stmt = conn.prepare("SELECT id, file_path, original_path FROM pdf_documents")?;
    let docs = stmt
        .query_map([], row_to_located)?
        .collect::<Result<Vec<_>, _>>()?;
    Ok(docs)
}

fn preview_for(conn: &Connection, docs: &[LocatedDocument]) -> Result<DeletionPreview, LumenError> {
    let mut note_count = 0_u32;
    let mut vocabulary_context_count = 0_u32;
    for doc in docs {
        note_count += count_owned(conn, "notes", doc)? as u32;
        vocabulary_context_count += count_owned(conn, "vocabulary_entries", doc)? as u32;
    }
    Ok(DeletionPreview {
        book_count: docs.len() as u32,
        note_count,
        vocabulary_context_count,
        document_ids: docs.iter().map(|doc| doc.id.clone()).collect(),
    })
}

fn count_owned(conn: &Connection, table: &str, doc: &LocatedDocument) -> Result<i64, LumenError> {
    owned_statement(conn, table, doc, "SELECT COUNT(*)")
}

fn owned_statement(
    conn: &Connection,
    table: &str,
    doc: &LocatedDocument,
    select: &str,
) -> Result<i64, LumenError> {
    if let Some(original) = &doc.original_path {
        let sql = format!(
            "{select} FROM {table} WHERE document_id = ?1 OR pdf_path = ?2 OR pdf_path = ?3"
        );
        Ok(
            conn.query_row(&sql, params![doc.id, doc.file_path, original], |row| {
                row.get(0)
            })?,
        )
    } else {
        let sql = format!("{select} FROM {table} WHERE document_id = ?1 OR pdf_path = ?2");
        Ok(conn.query_row(&sql, params![doc.id, doc.file_path], |row| row.get(0))?)
    }
}

fn remove_documents(conn: &Connection, docs: &[LocatedDocument]) -> Result<(), LumenError> {
    let tx = conn.unchecked_transaction()?;
    for doc in docs {
        for table in ["notes", "vocabulary_entries"] {
            if let Some(original) = &doc.original_path {
                tx.execute(
                    &format!(
                        "DELETE FROM {table} WHERE document_id = ?1 OR pdf_path = ?2 OR pdf_path = ?3"
                    ),
                    params![doc.id, doc.file_path, original],
                )?;
            } else {
                tx.execute(
                    &format!("DELETE FROM {table} WHERE document_id = ?1 OR pdf_path = ?2"),
                    params![doc.id, doc.file_path],
                )?;
            }
        }
        tx.execute("DELETE FROM pdf_documents WHERE id = ?1", params![doc.id])?;
    }
    tx.commit()?;
    Ok(())
}

fn delete_shelves(conn: &Connection, ids: &[String]) -> Result<(), LumenError> {
    for id in ids.iter().rev() {
        conn.execute("DELETE FROM shelves WHERE id = ?1", params![id])?;
    }
    Ok(())
}

fn remove_copies(store: &LibraryStore, docs: &[LocatedDocument]) {
    for doc in docs {
        if is_library_path(&doc.file_path, &store.root_str()) {
            let _ = store.remove(&doc.id);
        }
    }
}

fn row_to_shelf(row: &rusqlite::Row<'_>) -> rusqlite::Result<Shelf> {
    Ok(Shelf {
        id: row.get(0)?,
        parent_id: row.get(1)?,
        name: row.get(2)?,
        position: row.get::<_, i64>(3)? as i32,
        book_count: row.get::<_, i64>(4)? as u32,
    })
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::infrastructure::db::{self, migration};

    #[test]
    fn root_page_lists_a_book_that_has_no_shelf() {
        let dir = std::env::temp_dir().join(format!("lumen-shelf-{}", Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let db_path = dir.join("data.db");
        let conn = Connection::open(&db_path).unwrap();
        migration::run(&conn).unwrap();
        conn.execute(
            "INSERT INTO pdf_documents
                (id, file_path, file_name, total_pages, last_page, last_scroll_offset, opened_at, added_at)
             VALUES ('a', '/tmp/a.pdf', 'a.pdf', 1, 0, 0.0, 1, 1)",
            [],
        )
        .unwrap();
        drop(conn);

        let pool = db::create_pool(db_path.to_str().unwrap()).unwrap();
        let repo = SqliteShelfRepo::new(pool, LibraryStore::new(dir.join("Library")));
        let page = repo.page(None).unwrap();
        assert!(page.crumbs.is_empty());
        assert!(matches!(
            page.children.as_slice(),
            [ShelfChild::Document { .. }]
        ));
        let _ = std::fs::remove_dir_all(dir);
    }
}

fn row_to_located(row: &rusqlite::Row<'_>) -> rusqlite::Result<LocatedDocument> {
    Ok(LocatedDocument {
        id: row.get(0)?,
        file_path: row.get(1)?,
        original_path: row.get(2)?,
    })
}
