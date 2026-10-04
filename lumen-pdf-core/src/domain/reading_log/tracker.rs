use super::entity::{ReadBook, ReadLine, ReadingSignal};

/// 最近一次输入之后多久算空闲。
pub const IDLE_AFTER_MS: i64 = 2 * 60 * 1000;
/// 长时间阅读时每隔多久写一行。
pub const FLUSH_EVERY_MS: i64 = 5 * 60 * 1000;
/// 不足这么多秒的不写。
pub const MIN_LINE_SECS: i64 = 5;

/// 只计有效阅读时间：书开着、阅读窗口在最前面、最近 2 分钟内有过输入。
/// 每行的 `secs` 是距上一行的增量。纯状态机，不做 I/O；时间由调用方传入（毫秒）。
#[derive(Debug, Default)]
pub struct ReadingTracker {
    open: Option<OpenBook>,
    front: bool,
    last_input_ms: Option<i64>,
}

#[derive(Debug)]
struct OpenBook {
    book: ReadBook,
    page: u32,
    /// 还没写进日志的有效毫秒数。
    pending_ms: i64,
    /// `pending_ms` 里最早那一段开始的时间。
    started_ms: Option<i64>,
    /// 正在计时的这一段从何时开始；暂停时为 None。
    active_since_ms: Option<i64>,
}

impl ReadingTracker {
    pub fn new() -> Self {
        Self::default()
    }

    /// 处理一个事件，返回需要写入日志的行（可能为空）。
    pub fn handle(&mut self, signal: ReadingSignal, now_ms: i64) -> Vec<ReadLine> {
        let mut lines = Vec::new();
        self.advance(now_ms);
        match signal {
            ReadingSignal::Open { book, page_index } => {
                if self.open.as_ref().map(|open| &open.book.id) == Some(&book.id) {
                    self.set_page(page_index);
                } else {
                    lines.extend(self.finish(now_ms));
                    self.open = Some(OpenBook {
                        book,
                        page: page_index + 1,
                        pending_ms: 0,
                        started_ms: None,
                        active_since_ms: None,
                    });
                }
                self.note_input(now_ms);
            }
            ReadingSignal::Page { page_index } => {
                self.set_page(page_index);
                self.note_input(now_ms);
            }
            ReadingSignal::Input => self.note_input(now_ms),
            ReadingSignal::Front { is_front } => {
                self.front = is_front;
                if is_front {
                    // 切回阅读窗口本身就是一次输入（点击或 ⌘Tab）。
                    self.note_input(now_ms);
                } else if let Some(open) = self.open.as_mut() {
                    open.active_since_ms = None;
                }
            }
            ReadingSignal::Tick => {
                if self.is_idle(now_ms) {
                    lines.extend(self.flush(now_ms, false));
                }
            }
            ReadingSignal::Close | ReadingSignal::Quit => {
                lines.extend(self.finish(now_ms));
            }
        }
        if self
            .open
            .as_ref()
            .is_some_and(|open| open.pending_ms >= FLUSH_EVERY_MS)
        {
            lines.extend(self.flush(now_ms, false));
        }
        lines
    }

    /// 把到 `now_ms` 为止的有效时间计入 `pending_ms`。空闲之后的时间不算。
    fn advance(&mut self, now_ms: i64) {
        let idle_at = self.last_input_ms.map(|input| input + IDLE_AFTER_MS);
        let Some(open) = self.open.as_mut() else {
            return;
        };
        let Some(since) = open.active_since_ms else {
            return;
        };
        let end = idle_at.map_or(now_ms, |idle| idle.min(now_ms));
        if end > since {
            open.pending_ms += end - since;
            open.started_ms.get_or_insert(since);
        }
        open.active_since_ms = if idle_at.is_some_and(|idle| now_ms >= idle) {
            None
        } else {
            Some(now_ms.max(since))
        };
    }

    fn note_input(&mut self, now_ms: i64) {
        self.last_input_ms = Some(now_ms);
        let front = self.front;
        if let Some(open) = self.open.as_mut() {
            if front && open.active_since_ms.is_none() {
                open.active_since_ms = Some(now_ms);
            }
        }
    }

    fn set_page(&mut self, page_index: u32) {
        if let Some(open) = self.open.as_mut() {
            open.page = page_index + 1;
        }
    }

    fn is_idle(&self, now_ms: i64) -> bool {
        self.last_input_ms
            .is_none_or(|input| now_ms >= input + IDLE_AFTER_MS)
    }

    /// 关闭、切换、退出：写最后一行，不足 5 秒的丢弃，然后关闭这本书。
    fn finish(&mut self, now_ms: i64) -> Option<ReadLine> {
        let line = self.flush(now_ms, true);
        self.open = None;
        line
    }

    /// 把攒下的整秒写成一行。不足 5 秒时：书还开着就留到下一行，`dropping_short` 时丢弃。
    fn flush(&mut self, now_ms: i64, dropping_short: bool) -> Option<ReadLine> {
        let open = self.open.as_mut()?;
        let secs = open.pending_ms / 1000;
        if secs < MIN_LINE_SECS {
            if dropping_short {
                open.pending_ms = 0;
                open.started_ms = None;
            }
            return None;
        }
        let started_ms = open.started_ms.unwrap_or(now_ms);
        open.pending_ms -= secs * 1000;
        open.started_ms = (open.pending_ms > 0).then_some(now_ms);
        Some(ReadLine {
            ts: now_ms.div_euclid(1000),
            book: open.book.clone(),
            started: started_ms.div_euclid(1000),
            secs,
            page: open.page,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SEC: i64 = 1000;
    const MIN: i64 = 60 * SEC;
    const T0: i64 = 1_790_000_000 * SEC;

    fn book(id: &str) -> ReadBook {
        ReadBook {
            id: id.into(),
            path: format!("/fixture/{id}.pdf"),
            title: format!("{id}.pdf"),
        }
    }

    fn open(tracker: &mut ReadingTracker, id: &str, at: i64) -> Vec<ReadLine> {
        let mut lines = tracker.handle(ReadingSignal::Front { is_front: true }, at);
        lines.extend(tracker.handle(
            ReadingSignal::Open {
                book: book(id),
                page_index: 0,
            },
            at,
        ));
        lines
    }

    /// 从 `from` 到 `to` 每 `input_every` 一次输入、每 15 秒一次 tick，收集所有行。
    fn read(tracker: &mut ReadingTracker, from: i64, to: i64, input_every: i64) -> Vec<ReadLine> {
        let mut lines = Vec::new();
        let mut t = from;
        while t < to {
            t = (t + 15 * SEC).min(to);
            if (t - from) % input_every == 0 {
                lines.extend(tracker.handle(ReadingSignal::Input, t));
            }
            lines.extend(tracker.handle(ReadingSignal::Tick, t));
        }
        lines
    }

    #[test]
    fn secs_are_deltas_not_running_totals() {
        let mut tracker = ReadingTracker::new();
        open(&mut tracker, "a", T0);
        let mut lines = read(&mut tracker, T0, T0 + 6 * MIN, 30 * SEC);
        lines.extend(tracker.handle(ReadingSignal::Close, T0 + 6 * MIN));

        let secs: Vec<i64> = lines.iter().map(|line| line.secs).collect();
        assert_eq!(secs, vec![300, 60]);
        assert_eq!(lines[1].started, (T0 + 5 * MIN) / SEC);
        assert_eq!(lines[0].started, T0 / SEC);
    }

    #[test]
    fn twelve_minute_read_flushes_every_five_minutes_and_sums_to_twelve() {
        let mut tracker = ReadingTracker::new();
        open(&mut tracker, "a", T0);
        let mut lines = read(&mut tracker, T0, T0 + 12 * MIN, 30 * SEC);
        lines.extend(tracker.handle(ReadingSignal::Close, T0 + 12 * MIN));

        assert_eq!(
            lines.iter().map(|line| line.secs).collect::<Vec<_>>(),
            vec![300, 300, 120]
        );
        assert_eq!(lines.iter().map(|line| line.secs).sum::<i64>(), 12 * 60);
        assert_eq!(lines[0].ts, (T0 + 5 * MIN) / SEC);
        assert_eq!(lines[1].ts, (T0 + 10 * MIN) / SEC);
    }

    #[test]
    fn idle_pauses_counting_and_writes_a_line() {
        let mut tracker = ReadingTracker::new();
        open(&mut tracker, "a", T0);
        tracker.handle(ReadingSignal::Input, T0 + 30 * SEC);
        // 之后没有输入：最后一次输入 2 分钟后算空闲。
        let lines = read(&mut tracker, T0 + 30 * SEC, T0 + 10 * MIN, i64::MAX);

        assert_eq!(lines.len(), 1, "one line when going idle");
        assert_eq!(lines[0].secs, 30 + 120);
        assert_eq!(lines[0].ts, (T0 + 2 * MIN + 30 * SEC) / SEC);

        // 回来继续读 1 分钟：只计这 1 分钟。
        tracker.handle(ReadingSignal::Input, T0 + 20 * MIN);
        let close = tracker.handle(ReadingSignal::Close, T0 + 21 * MIN);
        assert_eq!(
            close.iter().map(|line| line.secs).collect::<Vec<_>>(),
            vec![60]
        );
        assert_eq!(close[0].started, (T0 + 20 * MIN) / SEC);
    }

    #[test]
    fn time_away_from_the_window_does_not_count() {
        let mut tracker = ReadingTracker::new();
        open(&mut tracker, "a", T0);
        tracker.handle(ReadingSignal::Front { is_front: false }, T0 + 40 * SEC);
        // 窗口不在最前面也会空闲，空闲时把已读的 40 秒写成一行。
        let mut lines = tracker.handle(ReadingSignal::Tick, T0 + 5 * MIN);
        tracker.handle(ReadingSignal::Front { is_front: true }, T0 + 6 * MIN);
        lines.extend(tracker.handle(ReadingSignal::Close, T0 + 6 * MIN + 20 * SEC));

        assert_eq!(
            lines.iter().map(|line| line.secs).collect::<Vec<_>>(),
            vec![40, 20]
        );
    }

    #[test]
    fn input_while_in_background_does_not_start_counting() {
        let mut tracker = ReadingTracker::new();
        tracker.handle(
            ReadingSignal::Open {
                book: book("a"),
                page_index: 0,
            },
            T0,
        );
        tracker.handle(ReadingSignal::Input, T0 + 30 * SEC);
        let lines = tracker.handle(ReadingSignal::Close, T0 + MIN);

        assert!(lines.is_empty());
    }

    #[test]
    fn lines_under_five_seconds_are_skipped() {
        let mut tracker = ReadingTracker::new();
        open(&mut tracker, "a", T0);
        assert!(tracker
            .handle(ReadingSignal::Close, T0 + 4 * SEC)
            .is_empty());

        open(&mut tracker, "b", T0 + MIN);
        let lines = tracker.handle(ReadingSignal::Quit, T0 + MIN + 5 * SEC);
        assert_eq!(
            lines.iter().map(|line| line.secs).collect::<Vec<_>>(),
            vec![5]
        );
    }

    #[test]
    fn short_time_before_going_idle_carries_over_while_the_book_stays_open() {
        let mut tracker = ReadingTracker::new();
        open(&mut tracker, "a", T0);
        // 打开后立刻离开 3 秒，再空闲。
        tracker.handle(ReadingSignal::Front { is_front: false }, T0 + 3 * SEC);
        assert!(tracker.handle(ReadingSignal::Tick, T0 + 5 * MIN).is_empty());

        tracker.handle(ReadingSignal::Front { is_front: true }, T0 + 6 * MIN);
        let lines = tracker.handle(ReadingSignal::Close, T0 + 6 * MIN + 4 * SEC);
        assert_eq!(
            lines.iter().map(|line| line.secs).collect::<Vec<_>>(),
            vec![7]
        );
    }

    #[test]
    fn switching_books_flushes_the_previous_book() {
        let mut tracker = ReadingTracker::new();
        open(&mut tracker, "a", T0);
        tracker.handle(ReadingSignal::Page { page_index: 41 }, T0 + 20 * SEC);
        let lines = tracker.handle(
            ReadingSignal::Open {
                book: book("b"),
                page_index: 0,
            },
            T0 + 50 * SEC,
        );

        assert_eq!(lines.len(), 1);
        assert_eq!(lines[0].book.id, "a");
        assert_eq!(lines[0].secs, 50);
        assert_eq!(lines[0].page, 42, "page is 1-based");

        let next = tracker.handle(ReadingSignal::Close, T0 + 80 * SEC);
        assert_eq!(next[0].book.id, "b");
        assert_eq!(next[0].secs, 30);
    }

    #[test]
    fn reopening_the_same_book_keeps_counting() {
        let mut tracker = ReadingTracker::new();
        open(&mut tracker, "a", T0);
        let reopened = tracker.handle(
            ReadingSignal::Open {
                book: book("a"),
                page_index: 3,
            },
            T0 + 30 * SEC,
        );
        assert!(reopened.is_empty());
        let lines = tracker.handle(ReadingSignal::Close, T0 + MIN);
        assert_eq!(lines[0].secs, 60);
        assert_eq!(lines[0].page, 4);
    }

    #[test]
    fn nothing_is_written_without_an_open_book() {
        let mut tracker = ReadingTracker::new();
        tracker.handle(ReadingSignal::Front { is_front: true }, T0);
        tracker.handle(ReadingSignal::Input, T0 + 10 * SEC);
        assert!(tracker
            .handle(ReadingSignal::Tick, T0 + 10 * MIN)
            .is_empty());
        assert!(tracker
            .handle(ReadingSignal::Quit, T0 + 11 * MIN)
            .is_empty());
    }
}
