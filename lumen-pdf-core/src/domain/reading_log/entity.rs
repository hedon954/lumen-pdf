/// 正在读的一本书：文档 id、文件路径和文件名。阅读日志只写这些，不写 PDF 正文。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReadBook {
    pub id: String,
    pub path: String,
    pub title: String,
}

/// `activity.jsonl` 里的一行 `read`。`secs` 是距这本书上一行以来的有效秒数（增量，不是累计）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ReadLine {
    pub ts: i64,
    pub book: ReadBook,
    /// 这段计时开始的时间（Unix 秒）。
    pub started: i64,
    pub secs: i64,
    /// 从 1 开始的页码。
    pub page: u32,
}

/// 阅读窗口发生的事。时间由调用方给出（毫秒），便于测试。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ReadingSignal {
    /// 打开或切换到一本书；`page_index` 从 0 开始。
    Open { book: ReadBook, page_index: u32 },
    /// 翻到另一页；也算一次输入。
    Page { page_index: u32 },
    /// 键盘、鼠标、滚动等输入。
    Input,
    /// 阅读窗口是否在最前面（App 激活、窗口为主窗口、停在阅读页）。
    Front { is_front: bool },
    /// 定时检查：空闲和每 5 分钟落盘。
    Tick,
    /// 关闭这本书。
    Close,
    /// App 退出。
    Quit,
}
