use super::version::AppVersion;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RemoteAsset {
    pub name: String,
    pub download_url: String,
    pub size_bytes: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RemoteRelease {
    pub version: AppVersion,
    pub draft: bool,
    pub prerelease: bool,
    pub notes: String,
    pub assets: Vec<RemoteAsset>,
}

impl RemoteRelease {
    pub fn asset_named(&self, name: &str) -> Option<&RemoteAsset> {
        self.assets.iter().find(|asset| asset.name == name)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReleaseFeedError {
    Unavailable,
    NotFound,
}

#[async_trait::async_trait]
pub trait ReleaseFeed: Send + Sync {
    async fn list_releases(&self) -> Result<Vec<RemoteRelease>, ReleaseFeedError>;
    async fn read_checksum(&self, url: &str) -> Result<String, ReleaseFeedError>;
}
