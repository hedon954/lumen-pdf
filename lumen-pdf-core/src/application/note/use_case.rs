use crate::domain::note::{
    entity::{NoteEntry, SaveNoteRequest, UpdateNoteRequest},
    repository::NoteRepository,
};
use crate::error::LumenError;
use std::sync::Arc;

pub struct NoteUseCase {
    repo: Arc<dyn NoteRepository>,
}

impl NoteUseCase {
    pub fn new(repo: Arc<dyn NoteRepository>) -> Self {
        Self { repo }
    }

    pub fn save(&self, req: SaveNoteRequest) -> Result<NoteEntry, LumenError> {
        self.repo.save(&req)
    }

    pub fn list(&self) -> Result<Vec<NoteEntry>, LumenError> {
        self.repo.list()
    }

    pub fn list_by_pdf(&self, pdf_path: &str) -> Result<Vec<NoteEntry>, LumenError> {
        self.repo.list_by_pdf(pdf_path)
    }

    pub fn delete(&self, id: &str) -> Result<(), LumenError> {
        self.repo.delete(id)
    }

    pub fn update(&self, req: UpdateNoteRequest) -> Result<NoteEntry, LumenError> {
        self.repo.update(&req)
    }

    /// Export notes as Markdown
    pub fn export_markdown(&self, pdf_path: Option<&str>) -> Result<String, LumenError> {
        let notes = match pdf_path {
            Some(path) => self.repo.list_by_pdf(path)?,
            None => self.repo.list()?,
        };

        if notes.is_empty() {
            return Ok("# 笔记导出\n\n暂无笔记。".to_string());
        }

        // Group notes by PDF
        let mut pdf_groups: std::collections::HashMap<String, Vec<&NoteEntry>> =
            std::collections::HashMap::new();
        for note in &notes {
            pdf_groups
                .entry(note.pdf_name.clone())
                .or_default()
                .push(note);
        }

        let mut markdown = String::from("# 笔记导出 - LumenPDF\n\n");

        for (pdf_name, pdf_notes) in pdf_groups {
            markdown.push_str(&format!("## 📄 {}\n\n", pdf_name));

            for note in pdf_notes {
                markdown.push_str(&format!("### Page {}\n\n", note.page_index + 1));
                markdown.push_str(&format!("> {}\n\n", note.content));

                if !note.note.is_empty() {
                    markdown.push_str(&format!("**笔记：** {}\n\n", note.note));
                }

                markdown.push_str("---\n\n");
            }
        }

        Ok(markdown)
    }
}
