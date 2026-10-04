use crate::domain::reading_log::{
    entity::ReadingSignal, repository::ReadingLogSink, tracker::ReadingTracker,
};
use crate::error::LumenError;
use std::sync::Arc;

/// 把阅读窗口的事件交给计时器，把产生的行追加到日志。
pub struct ReadingLogUseCase {
    tracker: ReadingTracker,
    sink: Arc<dyn ReadingLogSink>,
}

impl ReadingLogUseCase {
    pub fn new(sink: Arc<dyn ReadingLogSink>) -> Self {
        Self {
            tracker: ReadingTracker::new(),
            sink,
        }
    }

    pub fn start(&self, now_ms: i64) -> Result<(), LumenError> {
        self.sink.ensure_started(now_ms.div_euclid(1000))
    }

    pub fn handle(&mut self, signal: ReadingSignal, now_ms: i64) -> Result<(), LumenError> {
        let lines = self.tracker.handle(signal, now_ms);
        if lines.is_empty() {
            return Ok(());
        }
        self.sink.ensure_started(now_ms.div_euclid(1000))?;
        self.sink.append(&lines)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::reading_log::entity::{ReadBook, ReadLine};
    use std::sync::Mutex;

    #[derive(Default)]
    struct FakeSink {
        started: Mutex<Vec<i64>>,
        lines: Mutex<Vec<ReadLine>>,
    }

    impl ReadingLogSink for FakeSink {
        fn ensure_started(&self, now_secs: i64) -> Result<(), LumenError> {
            self.started.lock().unwrap().push(now_secs);
            Ok(())
        }

        fn append(&self, lines: &[ReadLine]) -> Result<(), LumenError> {
            self.lines.lock().unwrap().extend_from_slice(lines);
            Ok(())
        }
    }

    #[test]
    fn writes_lines_only_when_the_tracker_produces_them() {
        let sink = Arc::new(FakeSink::default());
        let mut use_case = ReadingLogUseCase::new(sink.clone());
        let t0 = 1_790_000_000_000;
        use_case.start(t0).unwrap();
        use_case
            .handle(ReadingSignal::Front { is_front: true }, t0)
            .unwrap();
        use_case
            .handle(
                ReadingSignal::Open {
                    book: ReadBook {
                        id: "doc".into(),
                        path: "/fixture/doc.pdf".into(),
                        title: "doc.pdf".into(),
                    },
                    page_index: 0,
                },
                t0,
            )
            .unwrap();
        assert!(sink.lines.lock().unwrap().is_empty());

        use_case.handle(ReadingSignal::Quit, t0 + 30_000).unwrap();

        let lines = sink.lines.lock().unwrap();
        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].secs, 30);
        assert_eq!(
            *sink.started.lock().unwrap(),
            vec![1_790_000_000, 1_790_000_030]
        );
    }
}
