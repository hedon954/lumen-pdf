use super::entity::{ImportedPdf, PdfDocument, UpsertPdfRequest};
use crate::error::LumenError;

pub trait PdfDocumentRepository: Send + Sync {
    fn upsert(&self, req: UpsertPdfRequest) -> Result<PdfDocument, LumenError>;
    /// 导入原文件：复制进书库（内容相同则复用已有的书），从不修改或移动原文件。
    fn import(&self, req: UpsertPdfRequest) -> Result<ImportedPdf, LumenError>;
    fn save_reading_position(
        &self,
        file_path: &str,
        page: u32,
        scroll_offset: f64,
    ) -> Result<(), LumenError>;
    fn list(&self) -> Result<Vec<PdfDocument>, LumenError>;
    /// 移出文库，并删除这本书在书库里的副本。笔记和单词保留。
    fn delete(&self, file_path: &str) -> Result<(), LumenError>;
}
