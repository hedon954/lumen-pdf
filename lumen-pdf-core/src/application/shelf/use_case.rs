use crate::domain::shelf::entity::{DeletionPreview, Shelf, ShelfPage, ShelfPlacement, ShelfRule};
use crate::domain::shelf::repository::ShelfRepository;
use crate::domain::shelf::service::{normalized_name, parent_is_descendant};
use crate::error::LumenError;
use std::sync::Arc;

pub struct ShelfUseCase {
    repo: Arc<dyn ShelfRepository>,
}

impl ShelfUseCase {
    pub fn new(repo: Arc<dyn ShelfRepository>) -> Self {
        Self { repo }
    }

    pub fn page(&self, parent_id: Option<&str>) -> Result<ShelfPage, LumenError> {
        self.repo.page(parent_id)
    }

    pub fn create(&self, parent_id: Option<&str>, name: &str) -> Result<Shelf, LumenError> {
        let name = normalize(name)?;
        self.repo.create(parent_id, &name)
    }

    pub fn rename(&self, id: &str, name: &str) -> Result<Shelf, LumenError> {
        let name = normalize(name)?;
        self.repo.rename(id, &name)
    }

    pub fn move_shelf(&self, id: &str, parent_id: Option<&str>) -> Result<(), LumenError> {
        let nodes = self.repo.nodes()?;
        if parent_is_descendant(id, parent_id, &nodes) {
            return Err(rule(ShelfRule::MovesIntoItself));
        }
        self.repo.move_shelf(id, parent_id)
    }

    pub fn move_document(&self, id: &str, parent_id: Option<&str>) -> Result<(), LumenError> {
        self.repo.move_document(id, parent_id)
    }

    pub fn reorder(
        &self,
        parent_id: Option<&str>,
        order: &[ShelfPlacement],
    ) -> Result<(), LumenError> {
        self.repo.reorder(parent_id, order)
    }

    pub fn place_document(&self, id: &str, parent_id: Option<&str>) -> Result<(), LumenError> {
        self.repo.place_document(id, parent_id)
    }

    pub fn preview_documents(&self, ids: &[String]) -> Result<DeletionPreview, LumenError> {
        self.repo.preview_documents(ids)
    }

    pub fn preview_shelf(&self, id: &str) -> Result<DeletionPreview, LumenError> {
        self.repo.preview_shelf(id)
    }

    pub fn preview_library(&self) -> Result<DeletionPreview, LumenError> {
        self.repo.preview_library()
    }

    pub fn delete_documents(&self, ids: &[String]) -> Result<(), LumenError> {
        self.repo.delete_documents(ids)
    }

    pub fn delete_shelf(&self, id: &str) -> Result<(), LumenError> {
        self.repo.delete_shelf(id)
    }

    pub fn delete_library(&self) -> Result<(), LumenError> {
        self.repo.delete_library()
    }

    pub fn delete_if_empty(&self, id: &str) -> Result<(), LumenError> {
        self.repo.delete_if_empty(id)
    }
}

fn normalize(name: &str) -> Result<String, LumenError> {
    normalized_name(name).map_err(rule)
}

fn rule(rule: ShelfRule) -> LumenError {
    let message = match rule {
        ShelfRule::EmptyName => "书架名字不能是空的",
        ShelfRule::MovesIntoItself => "不能把书架放进它自己里面",
    };
    LumenError::DatabaseError {
        message: message.to_string(),
    }
}
