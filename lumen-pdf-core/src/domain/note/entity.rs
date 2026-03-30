#[derive(Debug, Clone, uniffi::Record)]
pub struct NoteEntry {
    pub id: String,
    pub pdf_path: String,
    pub pdf_name: String,
    pub page_index: u32,
    pub content: String,
    pub note: String,
    pub bounds_str: String,
    pub created_at: i64,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct SaveNoteRequest {
    pub pdf_path: String,
    pub pdf_name: String,
    pub page_index: u32,
    pub content: String,
    pub note: String,
    pub bounds_str: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct UpdateNoteRequest {
    pub id: String,
    pub note: String,
}
