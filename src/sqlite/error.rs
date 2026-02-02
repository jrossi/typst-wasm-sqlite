//! Error types for the SQLite reader

use core::fmt;

/// Result type alias
pub type Result<T> = core::result::Result<T, Error>;

/// Errors that can occur when reading SQLite databases
#[derive(Debug, Clone)]
pub enum Error {
    /// Invalid SQLite file format
    InvalidFormat(String),
    /// Unsupported SQLite feature
    UnsupportedFeature(String),
    /// Table not found
    TableNotFound(String),
    /// Invalid page number
    InvalidPage(u32),
    /// Invalid record format
    InvalidRecord,
    /// UTF-8 decoding error
    Utf8Error,
    /// Integer overflow
    IntegerOverflow,
    /// Invalid varint encoding
    InvalidVarint,
    /// SQL query error
    QueryError(String),
    /// Column not found
    ColumnNotFound(String),
    /// Database too small
    TooSmall,
    /// Invalid page type
    InvalidPageType(u8),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::InvalidFormat(msg) => write!(f, "Invalid SQLite format: {}", msg),
            Error::UnsupportedFeature(msg) => write!(f, "Unsupported feature: {}", msg),
            Error::TableNotFound(name) => write!(f, "Table not found: {}", name),
            Error::InvalidPage(num) => write!(f, "Invalid page number: {}", num),
            Error::InvalidRecord => write!(f, "Invalid record format"),
            Error::Utf8Error => write!(f, "UTF-8 decoding error"),
            Error::IntegerOverflow => write!(f, "Integer overflow"),
            Error::InvalidVarint => write!(f, "Invalid varint encoding"),
            Error::QueryError(msg) => write!(f, "Query error: {}", msg),
            Error::ColumnNotFound(name) => write!(f, "Column not found: {}", name),
            Error::TooSmall => write!(f, "Database file too small"),
            Error::InvalidPageType(t) => write!(f, "Invalid page type: 0x{:02x}", t),
        }
    }
}
