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
        let client = crate::infrastructure::net::proxy::configure(Client::builder())
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
            return Err(unavailable("更新地址不在官方发布接口上"));
        }
        let response = self
            .client
            .get(RELEASES_URL)
            .header("Accept", "application/vnd.github+json")
            .header("X-GitHub-Api-Version", "2022-11-28")
            .send()
            .await
            .map_err(|error| unavailable(error.to_string()))?;
        let bytes = read_limited(response, RELEASE_LIST_LIMIT).await?;
        let text =
            String::from_utf8(bytes).map_err(|_| unavailable("更新服务返回的内容不是文本"))?;
        parse_release_list(&text)
    }

    async fn read_checksum(&self, url: &str) -> Result<String, ReleaseFeedError> {
        let Some(file_name) = file_name_from_url(url) else {
            return Err(unavailable("校验地址里没有文件名"));
        };
        if !is_official_release_asset_url(url, &file_name) {
            return Err(unavailable("校验地址不在官方发布资源上"));
        }
        let response = self
            .client
            .get(url)
            .header("Accept", "application/octet-stream")
            .send()
            .await
            .map_err(|error| unavailable(error.to_string()))?;
        let bytes = read_limited(response, CHECKSUM_LIMIT).await?;
        String::from_utf8(bytes).map_err(|_| unavailable("校验文件不是文本"))
    }
}

pub fn parse_release_list(body: &str) -> Result<Vec<RemoteRelease>, ReleaseFeedError> {
    let values: Vec<serde_json::Value> = serde_json::from_str(body)
        .map_err(|_| unavailable(format!("更新服务返回的内容无法解析：{}", clip_detail(body))))?;
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

const ERROR_BODY_LIMIT: usize = 1024;
const DETAIL_CHAR_LIMIT: usize = 400;

fn unavailable(detail: impl Into<String>) -> ReleaseFeedError {
    ReleaseFeedError::Unavailable(clip_detail(detail.into()))
}

fn clip_detail(text: impl AsRef<str>) -> String {
    text.as_ref()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
        .chars()
        .take(DETAIL_CHAR_LIMIT)
        .collect()
}

/// GitHub's own `message`, prefixed with the HTTP status. Empty bodies keep the status.
pub(crate) fn api_error_detail(status: StatusCode, body: &[u8]) -> String {
    let text = String::from_utf8_lossy(body);
    let message = serde_json::from_str::<serde_json::Value>(&text)
        .ok()
        .and_then(|value| {
            value
                .get("message")
                .and_then(serde_json::Value::as_str)
                .map(str::to_string)
        })
        .filter(|message| !message.is_empty())
        .unwrap_or_else(|| text.trim().to_string());
    let message = clip_detail(message);
    if message.is_empty() {
        format!("HTTP {}", status.as_u16())
    } else {
        format!("HTTP {}: {}", status.as_u16(), message)
    }
}

/// A reached host that refuses the call for quota is not a connection failure.
/// GitHub signals that with 429, or with 403 once `x-ratelimit-remaining` is 0
/// or `retry-after` is present.
pub(crate) fn is_rate_limited(status: StatusCode, headers: &reqwest::header::HeaderMap) -> bool {
    let remaining_is_zero = headers
        .get("x-ratelimit-remaining")
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| value.trim() == "0");
    let asked_to_wait = headers.get("retry-after").is_some();
    status == StatusCode::TOO_MANY_REQUESTS
        || (status == StatusCode::FORBIDDEN && (remaining_is_zero || asked_to_wait))
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
        let status = response.status();
        let limited = is_rate_limited(status, response.headers());
        let body = read_error_body(response).await;
        let detail = api_error_detail(status, &body);
        return Err(if limited {
            ReleaseFeedError::RateLimited(detail)
        } else {
            unavailable(detail)
        });
    }
    let mut body = Vec::new();
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = chunk.map_err(|error| unavailable(error.to_string()))?;
        if body.len().saturating_add(chunk.len()) > max_bytes {
            return Err(unavailable("更新服务返回的内容过长"));
        }
        body.extend_from_slice(&chunk);
    }
    Ok(body)
}

async fn read_error_body(response: reqwest::Response) -> Vec<u8> {
    let mut body = Vec::new();
    let mut stream = response.bytes_stream();
    while let Some(chunk) = stream.next().await {
        let Ok(chunk) = chunk else { break };
        let room = ERROR_BODY_LIMIT.saturating_sub(body.len());
        if room == 0 {
            break;
        }
        let take = chunk.len().min(room);
        body.extend_from_slice(&chunk[..take]);
    }
    body
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
    use super::{api_error_detail, is_rate_limited, parse_release_list, RELEASES_URL};
    use crate::domain::update::is_github_releases_api_url;
    use reqwest::StatusCode;

    #[test]
    fn exhausted_quota_is_not_a_connection_failure() {
        use reqwest::header::{HeaderMap, HeaderValue};

        let mut exhausted = HeaderMap::new();
        exhausted.insert("x-ratelimit-remaining", HeaderValue::from_static("0"));
        assert!(is_rate_limited(StatusCode::FORBIDDEN, &exhausted));

        let mut waiting = HeaderMap::new();
        waiting.insert("retry-after", HeaderValue::from_static("60"));
        assert!(is_rate_limited(StatusCode::TOO_MANY_REQUESTS, &waiting));

        let mut forbidden = HeaderMap::new();
        forbidden.insert("x-ratelimit-remaining", HeaderValue::from_static("12"));
        assert!(!is_rate_limited(StatusCode::FORBIDDEN, &forbidden));
        assert!(!is_rate_limited(StatusCode::BAD_GATEWAY, &HeaderMap::new()));
    }

    #[test]
    fn api_error_keeps_the_server_message() {
        let body = br#"{"message":"API rate limit exceeded for 74.2.4.80.","documentation_url":"https://docs.github.com"}"#;
        assert_eq!(
            api_error_detail(StatusCode::FORBIDDEN, body),
            "HTTP 403: API rate limit exceeded for 74.2.4.80."
        );
        assert_eq!(api_error_detail(StatusCode::BAD_GATEWAY, b""), "HTTP 502");
    }

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
