use std::cmp::Ordering;
use std::fmt;

/// Numeric application version such as `1.0.33`.
///
/// A leading `v` is accepted and discarded. Pre-release and build metadata are
/// rejected so a stable check cannot treat `1.0.34-beta` as newer than `1.0.33`.
#[derive(Debug, Clone)]
pub struct AppVersion {
    components: Vec<u64>,
}

impl AppVersion {
    pub fn parse(raw: &str) -> Option<Self> {
        let trimmed = raw.trim();
        let bare = trimmed
            .strip_prefix('v')
            .or_else(|| trimmed.strip_prefix('V'))
            .unwrap_or(trimmed);
        if bare.is_empty() || bare.len() > 32 {
            return None;
        }
        let mut components = Vec::new();
        for part in bare.split('.') {
            if part.is_empty() || part.len() > 18 || !part.chars().all(|c| c.is_ascii_digit()) {
                return None;
            }
            let value = part.parse::<u64>().ok()?;
            components.push(value);
        }
        if components.is_empty() || components.len() > 4 {
            return None;
        }
        Some(Self { components })
    }

    fn padded(&self) -> [u64; 4] {
        let mut padded = [0; 4];
        for (index, component) in self.components.iter().take(4).enumerate() {
            padded[index] = *component;
        }
        padded
    }
}

impl PartialEq for AppVersion {
    fn eq(&self, other: &Self) -> bool {
        self.cmp(other) == Ordering::Equal
    }
}

impl Eq for AppVersion {}

impl PartialOrd for AppVersion {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for AppVersion {
    fn cmp(&self, other: &Self) -> Ordering {
        self.padded().cmp(&other.padded())
    }
}

impl fmt::Display for AppVersion {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for (index, component) in self.components.iter().enumerate() {
            if index > 0 {
                write!(f, ".")?;
            }
            write!(f, "{component}")?;
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::AppVersion;

    #[test]
    fn parses_release_tag_and_compares_numerically() {
        let older = AppVersion::parse("v1.0.9").expect("older");
        let newer = AppVersion::parse("1.0.10").expect("newer");
        assert!(older < newer);
        assert_eq!(older.to_string(), "1.0.9");
        assert_eq!(newer.to_string(), "1.0.10");
    }

    #[test]
    fn missing_components_compare_as_zero() {
        let short = AppVersion::parse("1.0").expect("short");
        let padded = AppVersion::parse("1.0.0").expect("padded");
        assert_eq!(short, padded);
    }

    #[test]
    fn rejects_prerelease_and_empty_versions() {
        assert!(AppVersion::parse("1.0.34-beta").is_none());
        assert!(AppVersion::parse("1.0.34+build").is_none());
        assert!(AppVersion::parse("").is_none());
        assert!(AppVersion::parse("v").is_none());
        assert!(AppVersion::parse("1.2.3.4.5").is_none());
        assert!(AppVersion::parse("1..2").is_none());
    }
}
