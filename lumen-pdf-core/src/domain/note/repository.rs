use super::entity::{NoteEntry, SaveNoteRequest, UpdateNoteRequest};
use crate::error::LumenError;

pub trait NoteRepository: Send + Sync {
    fn save(&self, req: &SaveNoteRequest) -> Result<NoteEntry, LumenError>;
    fn list(&self) -> Result<Vec<NoteEntry>, LumenError>;
    fn list_by_pdf(&self, pdf_path: &str) -> Result<Vec<NoteEntry>, LumenError>;
    fn delete(&self, id: &str) -> Result<(), LumenError>;
    fn update(&self, req: &UpdateNoteRequest) -> Result<NoteEntry, LumenError>;
}
