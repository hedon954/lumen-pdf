use super::entity::{OwnedRow, ShelfNode, ShelfRule};

pub fn normalized_name(name: &str) -> Result<String, ShelfRule> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        Err(ShelfRule::EmptyName)
    } else {
        Ok(trimmed.to_string())
    }
}

/// `new_parent` 为 `None` 表示放到文库根上。
pub fn parent_is_descendant(shelf_id: &str, new_parent: Option<&str>, nodes: &[ShelfNode]) -> bool {
    let Some(start) = new_parent else {
        return false;
    };
    let mut current = start.to_string();
    if current == shelf_id {
        return true;
    }
    for _ in 0..nodes.len() {
        let Some(node) = nodes.iter().find(|node| node.id == current) else {
            return false;
        };
        match node.parent_id.as_deref() {
            Some(parent) if parent == shelf_id => return true,
            Some(parent) => current = parent.to_string(),
            None => return false,
        }
    }
    true
}

pub fn subtree_ids(root: &str, nodes: &[ShelfNode]) -> Vec<String> {
    let mut ids = vec![root.to_string()];
    let mut index = 0;
    while index < ids.len() {
        let parent = ids[index].clone();
        for node in nodes {
            if node.parent_id.as_deref() == Some(parent.as_str()) && !ids.contains(&node.id) {
                ids.push(node.id.clone());
            }
        }
        index += 1;
    }
    ids
}

pub fn rows_owned_by(rows: &[OwnedRow], document_ids: &[String]) -> Vec<String> {
    rows.iter()
        .filter(|row| {
            row.document_id
                .as_ref()
                .is_some_and(|id| document_ids.iter().any(|document| document == id))
        })
        .map(|row| row.id.clone())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn nodes() -> Vec<ShelfNode> {
        vec![
            ShelfNode {
                id: "a".into(),
                parent_id: None,
            },
            ShelfNode {
                id: "b".into(),
                parent_id: Some("a".into()),
            },
            ShelfNode {
                id: "c".into(),
                parent_id: Some("b".into()),
            },
        ]
    }

    #[test]
    fn empty_name_is_rejected_and_surrounding_space_is_removed() {
        assert_eq!(normalized_name("  "), Err(ShelfRule::EmptyName));
        assert_eq!(normalized_name(" 架构 "), Ok("架构".into()));
    }

    #[test]
    fn a_shelf_cannot_move_into_itself_or_a_descendant() {
        let tree = nodes();
        assert!(parent_is_descendant("a", Some("a"), &tree));
        assert!(parent_is_descendant("a", Some("c"), &tree));
        assert!(!parent_is_descendant("c", Some("a"), &tree));
        assert!(!parent_is_descendant("a", None, &tree));
    }

    #[test]
    fn subtree_includes_the_shelf_and_nested_shelves() {
        assert_eq!(subtree_ids("a", &nodes()), vec!["a", "b", "c"]);
        assert_eq!(subtree_ids("c", &nodes()), vec!["c"]);
    }

    #[test]
    fn deletion_keeps_contexts_that_belong_to_other_books() {
        let rows = vec![
            OwnedRow {
                id: "n1".into(),
                document_id: Some("book-a".into()),
            },
            OwnedRow {
                id: "w1".into(),
                document_id: Some("book-a".into()),
            },
            OwnedRow {
                id: "w2".into(),
                document_id: Some("book-b".into()),
            },
            OwnedRow {
                id: "loose".into(),
                document_id: None,
            },
        ];
        assert_eq!(
            rows_owned_by(&rows, &["book-a".into()]),
            vec!["n1".to_string(), "w1".to_string()]
        );
    }
}
