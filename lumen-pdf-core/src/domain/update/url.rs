const REPOSITORY: &str = "hedon954/lumen-pdf";
const DOWNLOAD_HOSTS: &[&str] = &[
    "objects.githubusercontent.com",
    "release-assets.githubusercontent.com",
    "github-releases.githubusercontent.com",
];

struct HttpsUrl {
    host: String,
    path: String,
    has_query: bool,
}

/// `https://api.github.com/repos/hedon954/lumen-pdf/releases...`
pub fn is_github_releases_api_url(raw: &str) -> bool {
    let Some(url) = split_https(raw) else {
        return false;
    };
    if url.host != "api.github.com" {
        return false;
    }
    let path = url.path.trim_end_matches('/');
    path == format!("/repos/{REPOSITORY}/releases")
        || path == format!("/repos/{REPOSITORY}/releases/latest")
        || path.starts_with(&format!("/repos/{REPOSITORY}/releases/"))
}

/// Initial asset URL or a later hop on a known GitHub release host.
pub fn is_trusted_update_url(raw: &str) -> bool {
    let Some(url) = split_https(raw) else {
        return false;
    };
    if url.host == "github.com" {
        return is_release_download_path(&url.path);
    }
    DOWNLOAD_HOSTS.contains(&url.host.as_str())
}

/// Disk image and checksum URLs published on the official release.
pub fn is_official_release_asset_url(raw: &str, file_name: &str) -> bool {
    if file_name.is_empty() || file_name.contains('/') || file_name.contains('\\') {
        return false;
    }
    let Some(url) = split_https(raw) else {
        return false;
    };
    if url.host != "github.com" || url.has_query || !is_release_download_path(&url.path) {
        return false;
    }
    let mut segments = url.path.split('/').skip(1);
    let owner = segments.next();
    let repo = segments.next();
    let releases = segments.next();
    let download = segments.next();
    let tag = segments.next();
    let file = segments.next();
    if segments.next().is_some()
        || owner != Some("hedon954")
        || repo != Some("lumen-pdf")
        || releases != Some("releases")
        || download != Some("download")
    {
        return false;
    }
    let Some(tag) = tag.and_then(decode_segment) else {
        return false;
    };
    let Some(file) = file.and_then(decode_segment) else {
        return false;
    };
    !tag.is_empty() && file == file_name
}

pub fn is_allowed_update_transport_url(raw: &str) -> bool {
    is_github_releases_api_url(raw) || is_trusted_update_url(raw)
}

fn is_release_download_path(path: &str) -> bool {
    let expected = format!("/{REPOSITORY}/releases/download/");
    if !path.starts_with(&expected) {
        return false;
    }
    let rest = &path[expected.len()..];
    let mut segments = rest.split('/');
    let tag = segments.next().unwrap_or("");
    let file = segments.next().unwrap_or("");
    segments.next().is_none()
        && decode_segment(tag).is_some_and(|tag| !tag.is_empty())
        && decode_segment(file).is_some_and(|file| !file.is_empty())
}

fn split_https(raw: &str) -> Option<HttpsUrl> {
    let raw = raw.trim();
    if raw.is_empty()
        || raw.len() > 2048
        || raw
            .chars()
            .any(|character| character.is_whitespace() || character.is_control())
    {
        return None;
    }
    let rest = raw.strip_prefix("https://")?;
    let authority_end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    let authority = &rest[..authority_end];
    if authority.is_empty()
        || authority.contains('@')
        || authority.contains(':')
        || !authority.chars().all(|character| {
            character.is_ascii_alphanumeric() || character == '.' || character == '-'
        })
    {
        return None;
    }
    let host = authority.to_ascii_lowercase();
    let after = &rest[authority_end..];
    if after.contains('#') {
        return None;
    }
    let (path, has_query) = if let Some(query_at) = after.find('?') {
        (&after[..query_at], true)
    } else if after.is_empty() {
        ("/", false)
    } else {
        (after, false)
    };
    if !path.starts_with('/') || path.split('/').skip(1).any(|segment| segment.is_empty()) {
        return None;
    }
    if path.split('/').any(|segment| segment == "..") {
        return None;
    }
    Some(HttpsUrl {
        host,
        path: path.to_string(),
        has_query,
    })
}

fn decode_segment(segment: &str) -> Option<String> {
    if segment.is_empty() {
        return None;
    }
    let decoded = urlencoding::decode(segment).ok()?.into_owned();
    if decoded.is_empty()
        || decoded.contains('/')
        || decoded.contains('\\')
        || decoded.contains('\0')
        || decoded == "."
        || decoded == ".."
    {
        return None;
    }
    Some(decoded)
}

#[cfg(test)]
mod tests {
    use super::{
        is_allowed_update_transport_url, is_github_releases_api_url, is_official_release_asset_url,
        is_trusted_update_url,
    };

    const DMG: &str =
        "https://github.com/hedon954/lumen-pdf/releases/download/v1.0.34/LumenPDF-1.0.34.dmg";

    #[test]
    fn accepts_official_release_asset_and_cdn_redirect() {
        assert!(is_official_release_asset_url(DMG, "LumenPDF-1.0.34.dmg"));
        assert!(is_trusted_update_url(DMG));
        assert!(is_trusted_update_url(
            "https://release-assets.githubusercontent.com/github-production-release-asset/123/LumenPDF-1.0.34.dmg?jwt=token"
        ));
        assert!(!is_official_release_asset_url(
            "https://objects.githubusercontent.com/asset/LumenPDF-1.0.34.dmg",
            "LumenPDF-1.0.34.dmg"
        ));
    }

    #[test]
    fn rejects_other_hosts_queries_and_path_escapes() {
        assert!(!is_official_release_asset_url(
            "https://github.com/other/lumen-pdf/releases/download/v1.0.34/LumenPDF-1.0.34.dmg",
            "LumenPDF-1.0.34.dmg"
        ));
        assert!(!is_official_release_asset_url(
            "https://github.com.evil.com/hedon954/lumen-pdf/releases/download/v1.0.34/LumenPDF-1.0.34.dmg",
            "LumenPDF-1.0.34.dmg"
        ));
        assert!(!is_trusted_update_url(
            "http://github.com/hedon954/lumen-pdf/releases/download/v1.0.34/LumenPDF-1.0.34.dmg"
        ));
        assert!(!is_official_release_asset_url(
            &format!("{DMG}?extra=1"),
            "LumenPDF-1.0.34.dmg"
        ));
        assert!(!is_trusted_update_url(
            "https://github.com/hedon954/lumen-pdf/releases/download/v1.0.34/%2e%2e/LumenPDF-1.0.34.dmg"
        ));
        assert!(!is_official_release_asset_url(
            "https://user:pass@github.com/hedon954/lumen-pdf/releases/download/v1.0.34/LumenPDF-1.0.34.dmg",
            "LumenPDF-1.0.34.dmg"
        ));
    }

    #[test]
    fn releases_api_stays_on_the_official_repository() {
        assert!(is_github_releases_api_url(
            "https://api.github.com/repos/hedon954/lumen-pdf/releases?per_page=20"
        ));
        assert!(is_allowed_update_transport_url(
            "https://api.github.com/repos/hedon954/lumen-pdf/releases/latest"
        ));
        assert!(!is_github_releases_api_url(
            "https://api.github.com/repos/other/lumen-pdf/releases"
        ));
        assert!(!is_trusted_update_url(
            "https://api.github.com/repos/hedon954/lumen-pdf/releases"
        ));
    }
}
