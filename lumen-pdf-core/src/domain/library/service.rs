//! LumenPDF 自己的书库：导入时把 PDF 复制到 `<数据目录>/Library/<文档 id>/<原文件名>`，
//! 之后原文件改名、移动或删除都不影响阅读进度和标记。这里只放不做 I/O 的规则。

/// 书库里保存的文件名：只取原文件名的最后一段，去掉路径分隔符和开头的点，并保证以 `.pdf` 结尾。
pub fn library_file_name(original_name: &str) -> String {
    let last = original_name.rsplit(['/', '\\']).next().unwrap_or_default();
    let cleaned: String = last
        .chars()
        .map(|c| if c == ':' || c.is_control() { '_' } else { c })
        .collect();
    let trimmed = cleaned.trim().trim_start_matches('.').trim();
    let stem = if trimmed.is_empty() {
        "document.pdf"
    } else {
        trimmed
    };
    if stem.to_ascii_lowercase().ends_with(".pdf") {
        stem.to_string()
    } else {
        format!("{stem}.pdf")
    }
}

/// 书库内的相对路径：`<文档 id>/<文件名>`。
pub fn library_relative_path(document_id: &str, original_name: &str) -> String {
    format!("{document_id}/{}", library_file_name(original_name))
}

/// 文档 id 只能作为书库下的一层目录名，不能逃出书库。
pub fn is_safe_document_id(document_id: &str) -> bool {
    !document_id.is_empty()
        && document_id != "."
        && document_id != ".."
        && !document_id.contains(['/', '\\'])
}

/// `path` 是否已经在书库 `root` 里（迁移和导入据此判断是否已复制过）。
pub fn is_library_path(path: &str, root: &str) -> bool {
    let root = root.trim_end_matches('/');
    !root.is_empty()
        && path.len() > root.len() + 1
        && path.starts_with(root)
        && path.as_bytes()[root.len()] == b'/'
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn library_file_name_keeps_the_original_name() {
        assert_eq!(library_file_name("Example Book.pdf"), "Example Book.pdf");
        assert_eq!(library_file_name("NOTES.PDF"), "NOTES.PDF");
    }

    #[test]
    fn library_file_name_strips_paths_and_hidden_prefixes() {
        assert_eq!(library_file_name("../../etc/passwd"), "passwd.pdf");
        assert_eq!(library_file_name(".hidden.pdf"), "hidden.pdf");
        assert_eq!(library_file_name("a:b.pdf"), "a_b.pdf");
        assert_eq!(library_file_name("  "), "document.pdf");
        assert_eq!(library_file_name(""), "document.pdf");
    }

    #[test]
    fn relative_path_is_id_then_name() {
        assert_eq!(library_relative_path("abc", "Book.pdf"), "abc/Book.pdf");
    }

    #[test]
    fn document_id_cannot_escape_the_library() {
        assert!(is_safe_document_id("3f1c-uuid"));
        assert!(!is_safe_document_id(""));
        assert!(!is_safe_document_id(".."));
        assert!(!is_safe_document_id("a/b"));
    }

    #[test]
    fn library_path_detection_needs_a_real_child() {
        let root = "/Users/x/Library/Application Support/LumenPDF/Library";
        assert!(is_library_path(&format!("{root}/id/Book.pdf"), root));
        assert!(is_library_path(
            &format!("{root}/id/Book.pdf"),
            &format!("{root}/")
        ));
        assert!(!is_library_path(root, root));
        assert!(!is_library_path(&format!("{root}Other/Book.pdf"), root));
        assert!(!is_library_path("/Users/x/Downloads/Book.pdf", root));
        assert!(!is_library_path("/a.pdf", ""));
    }
}
