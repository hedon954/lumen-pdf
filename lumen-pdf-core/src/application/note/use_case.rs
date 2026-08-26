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

    pub fn apply_history_snapshot(
        &self,
        remove_ids: Vec<String>,
        restore_notes: Vec<NoteEntry>,
    ) -> Result<(), LumenError> {
        self.repo
            .apply_history_snapshot(&remove_ids, &restore_notes)
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
}
