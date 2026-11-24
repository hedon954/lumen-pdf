use crate::domain::update::{AppUpdateStatus, ReleaseFeed, UpdateDomainService};

pub struct AppUpdateUseCase<F> {
    service: UpdateDomainService<F>,
}

impl<F: ReleaseFeed> AppUpdateUseCase<F> {
    pub fn new(feed: F) -> Self {
        Self {
            service: UpdateDomainService::new(feed),
        }
    }

    pub async fn check(&self, current_version: String) -> AppUpdateStatus {
        self.service.check(&current_version).await
    }
}
