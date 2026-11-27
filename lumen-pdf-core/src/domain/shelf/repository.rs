use super::entity::{DeletionPreview, Shelf, ShelfNode, ShelfPage, ShelfPlacement};
use crate::error::LumenError;

pub trait ShelfRepository: Send + Sync {
    fn page(&self, parent_id: Option<&str>) -> Result<ShelfPage, LumenError>;
    fn nodes(&self) -> Result<Vec<ShelfNode>, LumenError>;
    fn create(&self, parent_id: Option<&str>, name: &str) -> Result<Shelf, LumenError>;
    fn rename(&self, id: &str, name: &str) -> Result<Shelf, LumenError>;
    fn move_shelf(&self, id: &str, parent_id: Option<&str>) -> Result<(), LumenError>;
    fn move_document(&self, id: &str, parent_id: Option<&str>) -> Result<(), LumenError>;
    fn reorder(&self, parent_id: Option<&str>, order: &[ShelfPlacement]) -> Result<(), LumenError>;
    fn place_document(&self, id: &str, parent_id: Option<&str>) -> Result<(), LumenError>;
    fn preview_documents(&self, ids: &[String]) -> Result<DeletionPreview, LumenError>;
    fn preview_shelf(&self, id: &str) -> Result<DeletionPreview, LumenError>;
    fn preview_library(&self) -> Result<DeletionPreview, LumenError>;
    fn delete_documents(&self, ids: &[String]) -> Result<(), LumenError>;
    fn delete_shelf(&self, id: &str) -> Result<(), LumenError>;
    fn delete_library(&self) -> Result<(), LumenError>;
    fn delete_if_empty(&self, id: &str) -> Result<(), LumenError>;
}
