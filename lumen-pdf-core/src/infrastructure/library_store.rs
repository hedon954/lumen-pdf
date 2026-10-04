//! 书库文件操作：复制、校验和删除 `<数据目录>/Library/<文档 id>/` 下的副本。
//! 只读原文件，从不修改、移动或删除它。

use crate::domain::library::service::{is_safe_document_id, library_file_name};
use sha2::{Digest, Sha256};
use std::fs::{self, File};
use std::io::{self, ErrorKind, Read};
use std::path::{Path, PathBuf};

pub struct LibraryStore {
    root: PathBuf,
}

impl LibraryStore {
    pub const DIR_NAME: &'static str = "Library";

    pub fn new(root: PathBuf) -> Self {
        Self { root }
    }

    /// 书库放在 `data.db` 同一目录下的 `Library/`。
    pub fn for_database(db_path: &Path) -> Self {
        let dir = db_path.parent().unwrap_or_else(|| Path::new("."));
        Self::new(dir.join(Self::DIR_NAME))
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn root_str(&self) -> String {
        self.root.to_string_lossy().into_owned()
    }

    /// 文件内容的 SHA-256（小写十六进制）。
    pub fn sha256(path: &Path) -> io::Result<String> {
        let mut file = File::open(path)?;
        let mut hasher = Sha256::new();
        let mut buffer = vec![0u8; 1 << 20];
        loop {
            let read = file.read(&mut buffer)?;
            if read == 0 {
                break;
            }
            hasher.update(&buffer[..read]);
        }
        Ok(hex::encode(hasher.finalize()))
    }

    /// 把 `source` 复制成 `Library/<id>/<文件名>` 并返回副本路径。
    /// macOS 上 `fs::copy` 会先尝试 APFS 克隆（`fclonefileat`），不行再普通复制。
    /// 先写到同目录的临时文件，校验内容与 `expected_hash` 一致后再改名，崩溃不会留下半个副本。
    /// 目标已存在且内容一致时直接复用（迁移中途崩溃后重跑）。
    pub fn copy_in(
        &self,
        source: &Path,
        document_id: &str,
        original_name: &str,
        expected_hash: &str,
    ) -> io::Result<PathBuf> {
        let dir = self.document_dir(document_id)?;
        let target = dir.join(library_file_name(original_name));
        if target.is_file() && Self::sha256(&target)? == expected_hash {
            return Ok(target);
        }
        fs::create_dir_all(&dir)?;
        let partial = dir.join(".copy.partial");
        let _ = fs::remove_file(&partial);
        fs::copy(source, &partial)?;
        if Self::sha256(&partial)? != expected_hash {
            let _ = fs::remove_file(&partial);
            return Err(io::Error::other("PDF changed while it was being copied"));
        }
        fs::rename(&partial, &target)?;
        Ok(target)
    }

    /// 删除一本书在书库里的整个目录。目录不存在不算错。
    pub fn remove(&self, document_id: &str) -> io::Result<()> {
        match fs::remove_dir_all(self.document_dir(document_id)?) {
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(()),
            other => other,
        }
    }

    fn document_dir(&self, document_id: &str) -> io::Result<PathBuf> {
        if !is_safe_document_id(document_id) {
            return Err(io::Error::new(
                ErrorKind::InvalidInput,
                "invalid document id",
            ));
        }
        Ok(self.root.join(document_id))
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub(crate) fn temp_dir(label: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("lumenpdf-{label}-{}", uuid::Uuid::new_v4()));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn copy_in_creates_an_identical_copy_and_leaves_the_original() {
        let dir = temp_dir("store");
        let original = dir.join("Book.pdf");
        fs::write(&original, b"%PDF fake one").unwrap();
        let hash = LibraryStore::sha256(&original).unwrap();
        let store = LibraryStore::new(dir.join("Library"));

        let copy = store
            .copy_in(&original, "doc-1", "Book.pdf", &hash)
            .unwrap();

        assert_eq!(copy, dir.join("Library/doc-1/Book.pdf"));
        assert_eq!(fs::read(&copy).unwrap(), b"%PDF fake one");
        assert_eq!(fs::read(&original).unwrap(), b"%PDF fake one");
        assert!(!dir.join("Library/doc-1/.copy.partial").exists());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn copy_in_reuses_an_existing_identical_copy() {
        let dir = temp_dir("store");
        let original = dir.join("Book.pdf");
        fs::write(&original, b"%PDF fake").unwrap();
        let hash = LibraryStore::sha256(&original).unwrap();
        let store = LibraryStore::new(dir.join("Library"));
        let first = store
            .copy_in(&original, "doc-1", "Book.pdf", &hash)
            .unwrap();

        let second = store
            .copy_in(&original, "doc-1", "Book.pdf", &hash)
            .unwrap();

        assert_eq!(first, second);
        assert_eq!(fs::read_dir(dir.join("Library/doc-1")).unwrap().count(), 1);
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn copy_in_rejects_content_that_does_not_match_the_hash() {
        let dir = temp_dir("store");
        let original = dir.join("Book.pdf");
        fs::write(&original, b"%PDF fake").unwrap();
        let store = LibraryStore::new(dir.join("Library"));

        assert!(store
            .copy_in(&original, "doc-1", "Book.pdf", "0000")
            .is_err());
        assert!(!dir.join("Library/doc-1/Book.pdf").exists());
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn remove_deletes_only_that_book() {
        let dir = temp_dir("store");
        let original = dir.join("Book.pdf");
        fs::write(&original, b"%PDF fake").unwrap();
        let hash = LibraryStore::sha256(&original).unwrap();
        let store = LibraryStore::new(dir.join("Library"));
        store.copy_in(&original, "a", "Book.pdf", &hash).unwrap();
        store.copy_in(&original, "b", "Book.pdf", &hash).unwrap();

        store.remove("a").unwrap();
        store.remove("missing").unwrap();

        assert!(!dir.join("Library/a").exists());
        assert!(dir.join("Library/b/Book.pdf").exists());
        assert!(original.exists());
        assert!(store.remove("..").is_err());
        fs::remove_dir_all(dir).unwrap();
    }
}
