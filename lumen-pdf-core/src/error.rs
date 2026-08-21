use thiserror::Error;

#[derive(Debug, Error, uniffi::Error)]
pub enum LumenError {
    #[error("Config not initialized — call initialize() first")]
    ConfigNotInitialized,

    #[error("Database error: {message}")]
    DatabaseError { message: String },

    #[error("LLM API error: {message}")]
    LlmApiError {
        message: String,
        http_request: String,
    },

    #[error("Fallback API error: {message}")]
    FallbackApiError { message: String },

    #[error("Serialization error: {message}")]
    SerializationError {
        message: String,
        http_request: String,
    },

    #[error("Not found: {message}")]
    NotFound { message: String },
}

impl From<rusqlite::Error> for LumenError {
    fn from(e: rusqlite::Error) -> Self {
        Self::DatabaseError {
            message: e.to_string(),
        }
    }
}

impl From<r2d2::Error> for LumenError {
    fn from(e: r2d2::Error) -> Self {
        Self::DatabaseError {
            message: e.to_string(),
        }
    }
}

impl From<serde_json::Error> for LumenError {
    fn from(e: serde_json::Error) -> Self {
        Self::serialization(e.to_string())
    }
}

impl LumenError {
    pub fn llm_api(message: impl Into<String>) -> Self {
        Self::LlmApiError {
            message: message.into(),
            http_request: String::new(),
        }
    }

    pub fn serialization(message: impl Into<String>) -> Self {
        Self::SerializationError {
            message: message.into(),
            http_request: String::new(),
        }
    }

    pub fn with_http_request(self, http_request: String) -> Self {
        match self {
            Self::LlmApiError { message, .. } => Self::LlmApiError {
                message,
                http_request,
            },
            Self::SerializationError { message, .. } => Self::SerializationError {
                message,
                http_request,
            },
            other => other,
        }
    }

    pub fn http_request(&self) -> &str {
        match self {
            Self::LlmApiError { http_request, .. }
            | Self::SerializationError { http_request, .. } => http_request,
            _ => "",
        }
    }

    /// Short Chinese hint for UI when an operation fails (e.g. LLM before fallback).
    pub fn user_hint_zh(&self) -> String {
        match self {
            LumenError::ConfigNotInitialized => {
                "LLM 未就绪：请先在「设置」中填写 API Base URL、API Key 与模型并保存。".to_string()
            }
            LumenError::DatabaseError { message } => format!("数据库错误：{}", message),
            LumenError::LlmApiError { message, .. } => format!("LLM 接口失败：{}", message),
            LumenError::FallbackApiError { message } => format!("兜底翻译接口失败：{}", message),
            LumenError::SerializationError { message, .. } => format!("译文解析失败：{}", message),
            LumenError::NotFound { message } => format!("未找到：{}", message),
        }
    }
}
