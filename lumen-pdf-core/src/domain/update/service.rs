use super::checksum::{checksum_name, disk_image_name, parse_checksum_body};
use super::entity::{AppUpdateFailure, AppUpdateOffer, AppUpdateStatus};
use super::feed::{ReleaseFeed, ReleaseFeedError, RemoteRelease};
use super::url::is_official_release_asset_url;
use super::version::AppVersion;

const NOTES_LIMIT: usize = 8_000;

pub struct UpdateDomainService<F> {
    feed: F,
}

impl<F: ReleaseFeed> UpdateDomainService<F> {
    pub fn new(feed: F) -> Self {
        Self { feed }
    }

    pub async fn check(&self, current_version: &str) -> AppUpdateStatus {
        let Some(current) = AppVersion::parse(current_version) else {
            return failed(AppUpdateFailure::UnparseableCurrentVersion);
        };
        let releases = match self.feed.list_releases().await {
            Ok(releases) => releases,
            Err(ReleaseFeedError::NotFound) => {
                return failed(AppUpdateFailure::NoStableRelease);
            }
            Err(ReleaseFeedError::Unavailable) => {
                return failed(AppUpdateFailure::FeedUnavailable);
            }
        };
        let Some(release) = newest_stable(&releases) else {
            return failed(AppUpdateFailure::NoStableRelease);
        };
        if release.version <= current {
            return AppUpdateStatus::UpToDate;
        }

        let version = release.version.to_string();
        let image_name = disk_image_name(&version);
        let sum_name = checksum_name(&version);
        let Some(image) = release.asset_named(&image_name) else {
            return failed(AppUpdateFailure::MissingDiskImage);
        };
        let Some(checksum) = release.asset_named(&sum_name) else {
            return failed(AppUpdateFailure::MissingChecksum);
        };
        if !is_official_release_asset_url(&image.download_url, &image_name)
            || !is_official_release_asset_url(&checksum.download_url, &sum_name)
        {
            return failed(AppUpdateFailure::UntrustedAssetUrl);
        }

        let body = match self.feed.read_checksum(&checksum.download_url).await {
            Ok(body) => body,
            Err(_) => return failed(AppUpdateFailure::ChecksumUnavailable),
        };
        let Some(digest) = parse_checksum_body(&body, &image_name) else {
            return failed(AppUpdateFailure::InvalidChecksum);
        };

        AppUpdateStatus::Available {
            offer: AppUpdateOffer {
                version,
                notes: limit_notes(&release.notes),
                download_url: image.download_url.clone(),
                sha256: digest,
                size_bytes: image.size_bytes,
            },
        }
    }
}

fn newest_stable(releases: &[RemoteRelease]) -> Option<&RemoteRelease> {
    releases
        .iter()
        .filter(|release| !release.draft && !release.prerelease)
        .max_by(|left, right| left.version.cmp(&right.version))
}

fn limit_notes(notes: &str) -> String {
    notes.trim().chars().take(NOTES_LIMIT).collect()
}

fn failed(reason: AppUpdateFailure) -> AppUpdateStatus {
    AppUpdateStatus::Failed { reason }
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;
    use std::sync::Mutex;

    use super::super::feed::{ReleaseFeed, ReleaseFeedError, RemoteAsset, RemoteRelease};
    use super::super::version::AppVersion;
    use super::{AppUpdateFailure, AppUpdateStatus, UpdateDomainService, NOTES_LIMIT};

    struct FakeFeed {
        releases: Mutex<Result<Vec<RemoteRelease>, ReleaseFeedError>>,
        checksums: HashMap<String, Result<String, ReleaseFeedError>>,
    }

    #[async_trait::async_trait]
    impl ReleaseFeed for FakeFeed {
        async fn list_releases(&self) -> Result<Vec<RemoteRelease>, ReleaseFeedError> {
            self.releases.lock().expect("feed").clone()
        }

        async fn read_checksum(&self, url: &str) -> Result<String, ReleaseFeedError> {
            self.checksums
                .get(url)
                .cloned()
                .unwrap_or(Err(ReleaseFeedError::Unavailable))
        }
    }

    fn version(raw: &str) -> AppVersion {
        AppVersion::parse(raw).expect("version")
    }

    fn asset(version: &str, name: &str, size: u64) -> RemoteAsset {
        RemoteAsset {
            name: name.to_string(),
            download_url: format!(
                "https://github.com/hedon954/lumen-pdf/releases/download/v{version}/{name}"
            ),
            size_bytes: size,
        }
    }

    fn digest() -> String {
        "cd".repeat(32)
    }

    fn stable(version_text: &str, notes: &str) -> RemoteRelease {
        let image = format!("LumenPDF-{version_text}.dmg");
        let sum = format!("LumenPDF-{version_text}.dmg.sha256");
        RemoteRelease {
            version: version(version_text),
            draft: false,
            prerelease: false,
            notes: notes.to_string(),
            assets: vec![
                asset(version_text, &image, 4096),
                asset(version_text, &sum, 64),
            ],
        }
    }

    fn checksum_body(version_text: &str) -> String {
        format!("{digest}  LumenPDF-{version_text}.dmg", digest = digest())
    }

    fn feed_for(releases: Vec<RemoteRelease>) -> FakeFeed {
        let mut checksums = HashMap::new();
        for release in &releases {
            let version = release.version.to_string();
            let url = format!(
                "https://github.com/hedon954/lumen-pdf/releases/download/v{version}/LumenPDF-{version}.dmg.sha256"
            );
            checksums.insert(url, Ok(checksum_body(&version)));
        }
        FakeFeed {
            releases: Mutex::new(Ok(releases)),
            checksums,
        }
    }

    fn available_version(status: AppUpdateStatus) -> String {
        match status {
            AppUpdateStatus::Available { offer } => offer.version,
            other => panic!("expected an update offer, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn offers_the_newest_stable_release_with_checksum() {
        let service = UpdateDomainService::new(feed_for(vec![
            stable("1.0.34", "fix reading"),
            stable("1.0.35", "newer"),
        ]));

        let status = service.check("1.0.33").await;

        match status {
            AppUpdateStatus::Available { offer } => {
                assert_eq!(offer.version, "1.0.35");
                assert_eq!(offer.notes, "newer");
                assert_eq!(offer.sha256, digest());
                assert_eq!(offer.size_bytes, 4096);
                assert!(offer.download_url.ends_with("/LumenPDF-1.0.35.dmg"));
            }
            other => panic!("expected an update offer, got {other:?}"),
        }
    }

    #[tokio::test]
    async fn current_or_older_release_is_up_to_date() {
        let service = UpdateDomainService::new(feed_for(vec![stable("1.0.9", "old")]));
        assert_eq!(service.check("v1.0.10").await, AppUpdateStatus::UpToDate);
        assert_eq!(service.check("1.0.9").await, AppUpdateStatus::UpToDate);
    }

    #[tokio::test]
    async fn skips_drafts_and_prereleases() {
        let mut newer = stable("1.0.40", "draft");
        newer.draft = true;
        let mut preview = stable("1.0.39", "preview");
        preview.prerelease = true;
        let service =
            UpdateDomainService::new(feed_for(vec![newer, preview, stable("1.0.34", "stable")]));

        assert_eq!(available_version(service.check("1.0.33").await), "1.0.34");
    }

    #[tokio::test]
    async fn missing_image_or_checksum_fails_closed() {
        let mut image_only = stable("1.0.34", "notes");
        image_only.assets.pop();
        let image_service = UpdateDomainService::new(feed_for(vec![image_only]));
        assert_eq!(
            image_service.check("1.0.33").await,
            AppUpdateStatus::Failed {
                reason: AppUpdateFailure::MissingChecksum
            }
        );

        let mut checksum_only = stable("1.0.34", "notes");
        checksum_only.assets.remove(0);
        let checksum_service = UpdateDomainService::new(feed_for(vec![checksum_only]));
        assert_eq!(
            checksum_service.check("1.0.33").await,
            AppUpdateStatus::Failed {
                reason: AppUpdateFailure::MissingDiskImage
            }
        );
    }

    #[tokio::test]
    async fn untrusted_asset_url_is_rejected() {
        let mut release = stable("1.0.34", "notes");
        release.assets[0].download_url = "https://example.invalid/LumenPDF-1.0.34.dmg".into();
        let service = UpdateDomainService::new(feed_for(vec![release]));

        assert_eq!(
            service.check("1.0.33").await,
            AppUpdateStatus::Failed {
                reason: AppUpdateFailure::UntrustedAssetUrl
            }
        );
    }

    #[tokio::test]
    async fn invalid_or_unavailable_checksum_fails() {
        let release = stable("1.0.34", "notes");
        let mut feed = feed_for(vec![release.clone()]);
        let url = release.assets[1].download_url.clone();
        feed.checksums.insert(url.clone(), Ok("nope".into()));
        let invalid = UpdateDomainService::new(feed);
        assert_eq!(
            invalid.check("1.0.33").await,
            AppUpdateStatus::Failed {
                reason: AppUpdateFailure::InvalidChecksum
            }
        );

        let mut missing = feed_for(vec![release]);
        missing
            .checksums
            .insert(url, Err(ReleaseFeedError::Unavailable));
        let unavailable = UpdateDomainService::new(missing);
        assert_eq!(
            unavailable.check("1.0.33").await,
            AppUpdateStatus::Failed {
                reason: AppUpdateFailure::ChecksumUnavailable
            }
        );
    }

    #[tokio::test]
    async fn feed_and_version_errors_are_distinct() {
        let unavailable = UpdateDomainService::new(FakeFeed {
            releases: Mutex::new(Err(ReleaseFeedError::Unavailable)),
            checksums: HashMap::new(),
        });
        assert_eq!(
            unavailable.check("1.0.33").await,
            AppUpdateStatus::Failed {
                reason: AppUpdateFailure::FeedUnavailable
            }
        );

        let empty = UpdateDomainService::new(feed_for(vec![]));
        assert_eq!(
            empty.check("1.0.33").await,
            AppUpdateStatus::Failed {
                reason: AppUpdateFailure::NoStableRelease
            }
        );
        assert_eq!(
            empty.check("beta").await,
            AppUpdateStatus::Failed {
                reason: AppUpdateFailure::UnparseableCurrentVersion
            }
        );
    }

    #[tokio::test]
    async fn notes_are_trimmed_and_capped() {
        let notes = format!("  {}\n", "字".repeat(NOTES_LIMIT + 20));
        let service = UpdateDomainService::new(feed_for(vec![stable("1.0.34", &notes)]));
        match service.check("1.0.33").await {
            AppUpdateStatus::Available { offer } => {
                assert_eq!(offer.notes.chars().count(), NOTES_LIMIT);
                assert!(!offer.notes.starts_with(' '));
            }
            other => panic!("expected an update offer, got {other:?}"),
        }
    }
}
