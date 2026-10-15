mod checksum;
mod entity;
mod feed;
mod service;
mod url;
mod version;

pub use entity::{AppUpdateFailure, AppUpdateOffer, AppUpdateStatus};
pub use feed::{ReleaseFeed, ReleaseFeedError, RemoteAsset, RemoteRelease};
pub use service::UpdateDomainService;
pub use url::{
    is_allowed_update_transport_url, is_github_releases_api_url, is_official_release_asset_url,
    is_trusted_update_url,
};
pub use version::AppVersion;
