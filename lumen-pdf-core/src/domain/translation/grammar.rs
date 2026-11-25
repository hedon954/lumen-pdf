use super::entity::SentenceChunk;

/// Prunes a sentence breakdown into a tree the reader can render.
///
/// Empty nodes are dropped. A child that is not a contiguous span of its
/// parent is dropped. Nodes deeper than [`MAX_DEPTH`] lose their children.
/// A flat list is left flat: this does not invent parent links.
pub struct GrammarTree;

impl GrammarTree {
    pub const MAX_DEPTH: usize = 4;

    pub fn normalize(nodes: Vec<SentenceChunk>) -> Vec<SentenceChunk> {
        nodes
            .into_iter()
            .filter_map(|node| normalize_node(node, 0))
            .collect()
    }
}

fn normalize_node(mut node: SentenceChunk, depth: usize) -> Option<SentenceChunk> {
    let original = node.original.trim();
    if original.is_empty() {
        return None;
    }
    node.original = original.to_string();
    if node.explanation.trim().is_empty() && !node.grammar.trim().is_empty() {
        node.explanation = node.grammar.trim().to_string();
    }
    if depth >= GrammarTree::MAX_DEPTH {
        node.children.clear();
        return Some(node);
    }

    let parent = node.original.clone();
    let mut children = Vec::new();
    for child in node.children {
        let child_text = child.original.trim();
        if child_text.is_empty() || !parent.contains(child_text) {
            continue;
        }
        if let Some(normalized) = normalize_node(child, depth + 1) {
            children.push(normalized);
        }
    }
    children.sort_by_key(|child| parent.find(child.original.trim()).unwrap_or(usize::MAX));
    node.children = children;
    Some(node)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn chunk(original: &str, children: Vec<SentenceChunk>) -> SentenceChunk {
        SentenceChunk {
            original: original.to_string(),
            children,
            ..SentenceChunk::default()
        }
    }

    #[test]
    fn drops_empty_nodes_and_keeps_a_flat_list_flat() {
        let tree = GrammarTree::normalize(vec![
            chunk("", vec![]),
            chunk("distinguish activities from those", vec![]),
        ]);
        assert_eq!(tree.len(), 1);
        assert!(tree[0].children.is_empty());
    }

    #[test]
    fn drops_a_child_that_is_not_inside_its_parent() {
        let tree = GrammarTree::normalize(vec![chunk(
            "distinguish activities from those",
            vec![chunk("unrelated clause", vec![])],
        )]);
        assert!(tree[0].children.is_empty());
    }

    #[test]
    fn keeps_from_between_the_two_objects() {
        let sentence = "Organizations must distinguish managerial activities from those";
        let tree = GrammarTree::normalize(vec![chunk(
            sentence,
            vec![
                chunk("those", vec![]),
                chunk("managerial activities", vec![]),
            ],
        )]);
        let parent = &tree[0].original;
        let first = parent.find(&tree[0].children[0].original).unwrap();
        let second = parent.find(&tree[0].children[1].original).unwrap();
        assert!(first < second);
        assert!(parent[first + tree[0].children[0].original.len()..second].contains("from"));
    }

    #[test]
    fn drops_children_past_the_depth_limit() {
        let mut node = chunk("a", vec![]);
        for _ in 0..6 {
            node = chunk("a", vec![node]);
        }
        let tree = GrammarTree::normalize(vec![node]);
        let mut depth = 0;
        let mut current = &tree[0];
        while !current.children.is_empty() {
            depth += 1;
            current = &current.children[0];
        }
        assert!(depth <= GrammarTree::MAX_DEPTH);
    }

    #[test]
    fn a_simple_leaf_has_no_children() {
        let tree = GrammarTree::normalize(vec![chunk("He left.", vec![])]);
        assert!(tree[0].children.is_empty());
    }
}
