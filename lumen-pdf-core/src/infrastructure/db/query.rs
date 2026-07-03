use crate::error::LumenError;

pub fn optional<T>(result: rusqlite::Result<T>) -> Result<Option<T>, LumenError> {
    match result {
        Ok(value) => Ok(Some(value)),
        Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
        Err(err) => Err(err.into()),
    }
}
