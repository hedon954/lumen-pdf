pub fn disk_image_name(version: &str) -> String {
    format!("LumenPDF-{version}.dmg")
}

pub fn checksum_name(version: &str) -> String {
    format!("LumenPDF-{version}.dmg.sha256")
}

/// Accept a bare SHA-256 digest or one `shasum` line for the expected disk image.
pub fn parse_checksum_body(body: &str, disk_image_name: &str) -> Option<String> {
    let line = body.lines().map(str::trim).find(|line| !line.is_empty())?;
    let mut parts = line.split_whitespace();
    let hex = parts.next()?;
    if hex.len() != 64 || !hex.chars().all(|character| character.is_ascii_hexdigit()) {
        return None;
    }
    if let Some(name) = parts.next() {
        let name = name.strip_prefix('*').unwrap_or(name);
        let base = name.rsplit(['/', '\\']).next().unwrap_or(name);
        if base != disk_image_name {
            return None;
        }
    }
    if parts.next().is_some() {
        return None;
    }
    Some(hex.to_ascii_lowercase())
}

#[cfg(test)]
mod tests {
    use super::parse_checksum_body;

    fn digest() -> String {
        "ab".repeat(32)
    }

    #[test]
    fn accepts_bare_digest_and_shasum_lines() {
        let expected = digest();
        let image = "LumenPDF-1.0.34.dmg";
        assert_eq!(
            parse_checksum_body(&expected, image).as_deref(),
            Some(expected.as_str())
        );
        assert_eq!(
            parse_checksum_body(&format!("{expected}  {image}"), image).as_deref(),
            Some(expected.as_str())
        );
        assert_eq!(
            parse_checksum_body(&format!("{expected} *{image}"), image).as_deref(),
            Some(expected.as_str())
        );
    }

    #[test]
    fn rejects_wrong_file_and_short_digest() {
        let image = "LumenPDF-1.0.34.dmg";
        assert!(parse_checksum_body(&format!("{}  other.dmg", digest()), image).is_none());
        assert!(parse_checksum_body("abcd", image).is_none());
        assert!(parse_checksum_body(&format!("{} extra tokens", digest()), image).is_none());
    }
}
