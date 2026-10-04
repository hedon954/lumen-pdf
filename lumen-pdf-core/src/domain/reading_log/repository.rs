use super::entity::ReadLine;
use crate::error::LumenError;

/// 阅读日志的落盘位置。实现必须整行追加，每行以 `\n` 结尾。
pub trait ReadingLogSink: Send + Sync {
    /// 日志还不存在时写一行 `log_started`，只写一次。
    fn ensure_started(&self, now_secs: i64) -> Result<(), LumenError>;
    fn append(&self, lines: &[ReadLine]) -> Result<(), LumenError>;
}
