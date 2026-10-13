#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct AppUpdateOffer {
    pub version: String,
    pub notes: String,
    pub download_url: String,
    pub sha256: String,
    pub size_bytes: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum AppUpdateFailure {
    UnparseableCurrentVersion,
    FeedUnavailable,
    NoStableRelease,
    MissingDiskImage,
    MissingChecksum,
    UntrustedAssetUrl,
    ChecksumUnavailable,
    InvalidChecksum,
}

#[derive(Debug, Clone, PartialEq, Eq, uniffi::Enum)]
pub enum AppUpdateStatus {
    UpToDate,
    Available { offer: AppUpdateOffer },
    Failed { reason: AppUpdateFailure },
}
