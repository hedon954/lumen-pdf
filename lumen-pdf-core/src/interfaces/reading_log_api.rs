use crate::application::reading_log::use_case::ReadingLogUseCase;
use crate::domain::reading_log::entity::{ReadBook, ReadingSignal};
use crate::error::LumenError;
use crate::infrastructure::activity_log::JsonlActivityLog;
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};

static READING_LOG: Mutex<Option<ReadingLogUseCase>> = Mutex::new(None);

/// 阅读窗口发生的事，由 Swift 上报。只带文档 id、路径、文件名和页码，从不带 PDF 正文。
#[derive(Debug, Clone, uniffi::Enum)]
pub enum ReadingEvent {
    Open {
        document_id: String,
        file_path: String,
        file_name: String,
        page_index: u32,
    },
    Page {
        page_index: u32,
    },
    Input,
    Front {
        is_front: bool,
    },
    Tick,
    Close,
    Quit,
}

impl From<ReadingEvent> for ReadingSignal {
    fn from(event: ReadingEvent) -> Self {
        match event {
            ReadingEvent::Open {
                document_id,
                file_path,
                file_name,
                page_index,
            } => ReadingSignal::Open {
                book: ReadBook {
                    id: document_id,
                    path: file_path,
                    title: file_name,
                },
                page_index,
            },
            ReadingEvent::Page { page_index } => ReadingSignal::Page { page_index },
            ReadingEvent::Input => ReadingSignal::Input,
            ReadingEvent::Front { is_front } => ReadingSignal::Front { is_front },
            ReadingEvent::Tick => ReadingSignal::Tick,
            ReadingEvent::Close => ReadingSignal::Close,
            ReadingEvent::Quit => ReadingSignal::Quit,
        }
    }
}

fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |elapsed| elapsed.as_millis() as i64)
}

fn lock_error() -> LumenError {
    LumenError::DatabaseError {
        message: "reading log lock poisoned".into(),
    }
}

/// 在数据库旁边启用阅读日志，并在日志还不存在时写 `log_started`。由 `initialize` 调用一次。
pub(crate) fn start_reading_log(db_path: &str) -> Result<(), LumenError> {
    let folder = Path::new(db_path).parent().unwrap_or(Path::new("."));
    let sink = Arc::new(JsonlActivityLog::new(
        folder.join(JsonlActivityLog::FILE_NAME),
    ));
    let use_case = ReadingLogUseCase::new(sink);
    use_case.start(now_ms())?;
    *READING_LOG.lock().map_err(|_| lock_error())? = Some(use_case);
    Ok(())
}

/// 上报一个阅读事件。日志未启用时什么也不做。
#[uniffi::export]
pub fn record_reading_event(event: ReadingEvent) -> Result<(), LumenError> {
    let mut guard = READING_LOG.lock().map_err(|_| lock_error())?;
    match guard.as_mut() {
        Some(use_case) => use_case.handle(event.into(), now_ms()),
        None => Ok(()),
    }
}
