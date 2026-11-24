use crate::domain::update::{
    is_allowed_update_transport_url, is_github_releases_api_url, is_official_release_asset_url,
    AppVersion, ReleaseFeed, ReleaseFeedError, RemoteAsset, RemoteRelease,
};
use futures_util::StreamExt;
use reqwest::{Client, StatusCode};
use std::error::Error;
use std::fmt;
use std::time::Duration;

pub const RELEASES_URL: &str =
    "https://api.github.com/repos/hedon954/lumen-pdf/releases?per_page=20";

const RELEASE_LIST_LIMIT: usize = 2 * 1024 * 1024;
const CHECKSUM_LIMIT: usize = 512;

pub struct GithubReleaseFeed {
    client: Client,
}

impl GithubReleaseFeed {
    pub fn new() -> Option<Self> {
        let client = Client::builder()
            .connect_timeout(Duration::from_secs(5))
            .timeout(Duration::from_secs(20))
            .user_agent("LumenPDF")
            .redirect(reqwest::redirect::Policy::custom(|attempt| {
                if attempt.previous().len() >= 10
                    || !is_allowed_update_transport_url(attempt.url().as_str())
                {
                    attempt.error(RejectedRedirect)
                } else {
                    attempt.follow()
                }
            }))
            .build()
            .ok()?;
        Some(Self { client })
    }
}

#[async_trait::async_trait]
impl ReleaseFeed for GithubReleaseFeed {
    async fn list_releases(&self) -> Result<Vec<RemoteRelease>, ReleaseFeedError> {
        if !is_github_releases_api_url(RELEASES_URL) {
            return Err(ReleaseFeedError::Unavailable);
        }
        let response = self
            .client
            .get(RELEASES_URL)
            .header("Accept", "application/vnd.github+json")
            .header("X-GitHub-Api-Version", "2022-11-28")
            .send()
            .await
            .map_err(|_| ReleaseFeedError::Unavailable)?;
        let bytes = read_limited(response, RELEASE_LIST_LIMIT).await?;
        let text = String::from_utf8(bytes).map_err(|_| ReleaseFeedError::Unavailable)?;
        parse_release_list(&text)
    }

    async fn read_checksum(&self, url: &str) -> Result<String, ReleaseFeedError> {
        let Some(file_name) = file_name_from_url(url) else {
            return Err(ReleaseFeedError::Unavailable);
        };
        if !is_official_release_asset_url(url, &file_name) {
            return Err(ReleaseFeedError::Unavailable);
        }
        let response = self
            .client
            .get(url)
            .header("Accept", "application/octet-stream")
            .send()
            .await
            .map_err(|_| ReleaseFeedError::Unavailable)?;
        let bytes = read_limited(response, CHECKSUM_LIMIT).await?;
        String::from_utf8(bytes).map_err(|_| ReleaseFeedError::Unavailable)
    }
}

pub fn parse_release_list(body: &str) -> Result<Vec<RemoteRelease>, ReleaseFeedError> {
    let values: Vec<serde_json::Value> =
        serde_json::from_str(body).map_err(|_| ReleaseFeedError::Unavailable)?;
    Ok(values.iter().filter_map(parse_release).collect())
}

fn parse_release(value: &serde_json::Value) -> Option<RemoteRelease> {
    let version = AppVersion::parse(value.get("tag_name")?.as_str()?)?;
    let notes = match value.get("body") {
        None | Some(serde_json::Value::Null) => String::new(),
        Some(body) => body.as_str()?.to_string(),
    };
    let assets = value
        .get("assets")?
        .as_array()?
        .iter()
        .filter_map(parse_asset)
        .collect();
    Some(RemoteRelease {
        version,
        draft: value.get("draft")?.as_bool()?,
        prerelease: value.get("prerelease")?.as_bool()?,
        notes,
        assets,
    })
}

fn parse_asset(value: &serde_json::Value) -> Option<RemoteAsset> {
    let name = value.get("name")?.as_str()?.trim();
    if name.is_empty() {
        return None;
    }
    Some(RemoteAsset {
        name: name.to_string(),
        download_url: value.get("browser_download_url")?.as_str()?.to_string(),
        size_bytes: value
            .get("size")
            .and_then(serde_json::Value::as_u64)
            .unwrap_or(0),
    })
}

fn file_name_from_url(url: &str) -> Option<String> {
    let path = url.split('?').next()?;
    let segment = path.rsplit('/').next()?;
    let decoded = urlencoding::decode(segment).ok()?.into_owned();
    if decoded.is_empty() {
        None
    } else {
        Some(decoded)
    }
}

async fn read_limited(
    response: reqwest::Response,
    max_bytes: usize,
) -> Result<Vec<u8>, ReleaseFeedError> {
    if response.status() == StatusCode::NOT_FOUND {
        return Err(ReleaseFeedError::NotFound);
    }
    if !response.status().is_success() {
        return Err(ReleaseFeedError::Unavailable);
    }
    let mut body = Vec::new();
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|_| ReleaseFeedError::Unavailable)?;
        if body.len().saturating_add(chunk.len()) > max_bytes {
            return Err(ReleaseFeedError::Unavailable);
        }
        body.extend_from_slice(&chunk);
    }
    Ok(body)
}

#[derive(Debug)]
struct RejectedRedirect;

impl fmt::Display for RejectedRedirect {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("rejected update redirect")
    }
}

impl Error for RejectedRedirect {}

#[cfg(test)]
mod tests {
    use super::{parse_release_list, RELEASES_URL};
    use crate::domain::update::is_github_releases_api_url;

    #[test]
    fn releases_endpoint_stays_on_the_official_api() {
        assert!(is_github_releases_api_url(RELEASES_URL));
    }

    #[test]
    fn parses_a_release_and_skips_an_unusable_tag() {
        let body = r#"[
            {
                "tag_name": "v1.0.34",
                "draft": false,
                "prerelease": false,
                "body": "说明",
                "assets": [
                    {
                        "name": "LumenPDF-1.0.34.dmg",
                        "browser_download_url": "https://github.com/hedon954/lumen-pdf/releases/download/v1.0.34/LumenPDF-1.0.34.dmg",
                        "size": 99
                    },
                    {
                        "name": " ",
                        "browser_download_url": "https://github.com/hedon954/lumen-pdf/releases/download/v1.0.34/blank",
                        "size": 1
                    }
                ]
            },
            {
                "tag_name": "nightly",
                "draft": false,
                "prerelease": false,
                "body": null,
                "assets": []
            }
        ]"#;

        let releases = parse_release_list(body).expect("json");

        assert_eq!(releases.len(), 1);
        assert_eq!(releases[0].version.to_string(), "1.0.34");
        assert_eq!(releases[0].notes, "说明");
        assert_eq!(releases[0].assets.len(), 1);
        assert_eq!(releases[0].assets[0].size_bytes, 99);
        assert!(!releases[0].draft);
    }
}
