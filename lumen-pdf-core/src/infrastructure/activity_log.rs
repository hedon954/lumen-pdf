use crate::domain::reading_log::{entity::ReadLine, repository::ReadingLogSink};
use crate::error::LumenError;
use serde::Serialize;
use std::fs::OpenOptions;
use std::io::{ErrorKind, Write};
use std::path::PathBuf;

/// `~/Library/Application Support/LumenPDF/activity.jsonl`：每次一整段追加，每行以 `\n` 结尾，写入后从不修改。
pub struct JsonlActivityLog {
    path: PathBuf,
}

impl JsonlActivityLog {
    pub const FILE_NAME: &'static str = "activity.jsonl";

    pub fn new(path: PathBuf) -> Self {
        Self { path }
    }

    /// 用 O_APPEND 一次写完整段，避免和其它写入交错出半行。
    fn append_bytes(&self, bytes: &[u8], create_new: bool) -> std::io::Result<()> {
        let mut options = OpenOptions::new();
        if create_new {
            options.write(true).create_new(true);
        } else {
            options.append(true).create(true);
        }
        let mut file = options.open(&self.path)?;
        file.write_all(bytes)?;
        file.flush()
    }
}

#[derive(Serialize)]
struct LogStartedLine<'a> {
    v: u8,
    ts: i64,
    app: &'a str,
    action: &'a str,
}

#[derive(Serialize)]
struct ReadJsonLine<'a> {
    v: u8,
    ts: i64,
    app: &'a str,
    id: &'a str,
    item: &'a str,
    title: &'a str,
    action: &'a str,
    started: i64,
    secs: i64,
    page: u32,
}

pub fn read_line_json(line: &ReadLine) -> Result<String, LumenError> {
    let mut json = serde_json::to_string(&ReadJsonLine {
        v: 1,
        ts: line.ts,
        app: "lumenpdf",
        id: &line.book.id,
        item: &line.book.path,
        title: &line.book.title,
        action: "read",
        started: line.started,
        secs: line.secs,
        page: line.page,
    })?;
    json.push('\n');
    Ok(json)
}

pub fn log_started_json(now_secs: i64) -> Result<String, LumenError> {
    let mut json = serde_json::to_string(&LogStartedLine {
        v: 1,
        ts: now_secs,
        app: "lumenpdf",
        action: "log_started",
    })?;
    json.push('\n');
    Ok(json)
}

fn io_error(error: std::io::Error) -> LumenError {
    LumenError::DatabaseError {
        message: format!("activity log: {error}"),
    }
}

impl ReadingLogSink for JsonlActivityLog {
    fn ensure_started(&self, now_secs: i64) -> Result<(), LumenError> {
        if self.path.exists() {
            return Ok(());
        }
        match self.append_bytes(log_started_json(now_secs)?.as_bytes(), true) {
            Err(error) if error.kind() == ErrorKind::AlreadyExists => Ok(()),
            other => other.map_err(io_error),
        }
    }

    fn append(&self, lines: &[ReadLine]) -> Result<(), LumenError> {
        if lines.is_empty() {
            return Ok(());
        }
        let mut buffer = String::new();
        for line in lines {
            buffer.push_str(&read_line_json(line)?);
        }
        self.append_bytes(buffer.as_bytes(), false)
            .map_err(io_error)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::reading_log::entity::ReadBook;

    fn temp_log() -> (PathBuf, JsonlActivityLog) {
        let dir = std::env::temp_dir().join(format!("lumenpdf-log-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join(JsonlActivityLog::FILE_NAME);
        (dir, JsonlActivityLog::new(path))
    }

    fn line(secs: i64, title: &str) -> ReadLine {
        ReadLine {
            ts: 1_790_000_300,
            book: ReadBook {
                id: "doc-1".into(),
                path: "/fixture/Book \"quoted\".pdf".into(),
                title: title.into(),
            },
            started: 1_790_000_000,
            secs,
            page: 12,
        }
    }

    #[test]
    fn every_line_is_valid_json_with_a_trailing_newline() {
        let (dir, log) = temp_log();
        log.ensure_started(1_790_000_000).unwrap();
        log.ensure_started(1_790_000_999).unwrap();
        log.append(&[line(300, "Book \"quoted\".pdf"), line(42, "第二本\n书.pdf")])
            .unwrap();
        log.append(&[line(7, "Book.pdf")]).unwrap();

        let text = std::fs::read_to_string(&log.path).unwrap();
        assert!(text.ends_with('\n'));
        let lines: Vec<&str> = text.split_terminator('\n').collect();
        assert_eq!(lines.len(), 4);
        let values: Vec<serde_json::Value> = lines
            .iter()
            .map(|line| serde_json::from_str(line).expect("valid JSON"))
            .collect();
        assert_eq!(values[0]["action"], "log_started");
        assert_eq!(
            values[0]["ts"], 1_790_000_000,
            "log_started is written once"
        );
        assert_eq!(
            values
                .iter()
                .filter(|value| value["action"] == "log_started")
                .count(),
            1
        );
        assert_eq!(values[1]["v"], 1);
        assert_eq!(values[1]["app"], "lumenpdf");
        assert_eq!(values[1]["id"], "doc-1");
        assert_eq!(values[1]["item"], "/fixture/Book \"quoted\".pdf");
        assert_eq!(values[1]["action"], "read");
        assert_eq!(values[1]["started"], 1_790_000_000);
        assert_eq!(values[1]["secs"], 300);
        assert_eq!(values[1]["page"], 12);
        assert_eq!(values[2]["title"], "第二本\n书.pdf");
        assert_eq!(values[3]["secs"], 7);
        std::fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn fields_are_in_the_documented_order() {
        let json = read_line_json(&line(30, "Book.pdf")).unwrap();
        assert_eq!(
            json,
            "{\"v\":1,\"ts\":1790000300,\"app\":\"lumenpdf\",\"id\":\"doc-1\",\"item\":\"/fixture/Book \\\"quoted\\\".pdf\",\"title\":\"Book.pdf\",\"action\":\"read\",\"started\":1790000000,\"secs\":30,\"page\":12}\n"
        );
        assert_eq!(
            log_started_json(5).unwrap(),
            "{\"v\":1,\"ts\":5,\"app\":\"lumenpdf\",\"action\":\"log_started\"}\n"
        );
    }

    #[test]
    fn append_without_a_started_log_creates_the_file() {
        let (dir, log) = temp_log();
        log.append(&[line(10, "Book.pdf")]).unwrap();
        let text = std::fs::read_to_string(&log.path).unwrap();
        assert_eq!(text.lines().count(), 1);
        std::fs::remove_dir_all(dir).unwrap();
    }
}
