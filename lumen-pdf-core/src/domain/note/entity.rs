#[derive(Debug, Clone, uniffi::Record)]
pub struct NoteEntry {
    pub id: String,
    pub pdf_path: String,
    pub pdf_name: String,
    pub page_index: u32,
    pub content: String,
    pub note: String,
    pub bounds_str: String,
    /// JSON-encoded per-page line geometry for selections that span pages.
    /// Empty for legacy single-page notes, which continue to use `page_index` + `bounds_str`.
    pub page_markups: String,
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
    pub page_markups: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct UpdateNoteRequest {
    pub id: String,
    pub note: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn save_request_preserves_cross_page_markup_payload() {
        let payload = r#"[{"pageIndex":4,"boundsStr":"{{1, 2}, {3, 4}}"},{"pageIndex":5,"boundsStr":"{{5, 6}, {7, 8}}"}]"#;
        let request = SaveNoteRequest {
            pdf_path: "/tmp/book.pdf".to_string(),
            pdf_name: "book.pdf".to_string(),
            page_index: 4,
            content: "selection".to_string(),
            note: "note".to_string(),
            bounds_str: "{{1, 2}, {3, 4}}".to_string(),
            page_markups: payload.to_string(),
        };

        assert_eq!(request.page_markups, payload);
    }
}
