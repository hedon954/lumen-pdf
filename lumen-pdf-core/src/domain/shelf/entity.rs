use crate::domain::pdf_document::entity::PdfDocument;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ShelfRule {
    EmptyName,
    MovesIntoItself,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct Shelf {
    pub id: String,
    pub parent_id: Option<String>,
    pub name: String,
    pub position: i32,
    /// 直接放在这个书架上的 PDF 数量，不含里面的子书架。
    pub book_count: u32,
}

#[derive(Debug, Clone, uniffi::Enum)]
pub enum ShelfChild {
    Shelf { shelf: Shelf },
    Document { document: PdfDocument },
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ShelfPage {
    /// 从文库根往下，直到当前书架。在根上时为空。
    pub crumbs: Vec<Shelf>,
    pub children: Vec<ShelfChild>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum ShelfItemKind {
    Shelf,
    Document,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct ShelfPlacement {
    pub kind: ShelfItemKind,
    pub id: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct DeletionPreview {
    pub book_count: u32,
    pub note_count: u32,
    pub vocabulary_context_count: u32,
    pub document_ids: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ShelfNode {
    pub id: String,
    pub parent_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OwnedRow {
    pub id: String,
    pub document_id: Option<String>,
}
