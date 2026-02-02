//! SQLite file format parser
//!
//! A pure Rust implementation for reading SQLite database files from bytes.
//! Supports basic SELECT queries on tables.

mod error;
mod format;
mod parser;
mod query;
mod value;

pub use error::{Error, Result};
pub use parser::Database;
pub use query::QueryResult;
pub use value::Value;

/// Table schema information
#[derive(Debug, Clone)]
pub struct TableSchema {
    pub name: String,
    pub columns: Vec<ColumnInfo>,
    pub sql: String,
}

impl TableSchema {
    pub fn to_json(&self) -> String {
        let cols = self
            .columns
            .iter()
            .map(|c| {
                format!(
                    "{{\"name\":\"{}\",\"type\":\"{}\"}}",
                    escape_json(&c.name),
                    escape_json(&c.type_name)
                )
            })
            .collect::<Vec<_>>()
            .join(",");

        format!(
            "{{\"table\":\"{}\",\"columns\":[{}]}}",
            escape_json(&self.name),
            cols
        )
    }
}

/// Column information
#[derive(Debug, Clone)]
pub struct ColumnInfo {
    pub name: String,
    pub type_name: String,
}

/// Escape a string for JSON output
fn escape_json(s: &str) -> String {
    let mut result = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '"' => result.push_str("\\\""),
            '\\' => result.push_str("\\\\"),
            '\n' => result.push_str("\\n"),
            '\r' => result.push_str("\\r"),
            '\t' => result.push_str("\\t"),
            c if c.is_control() => {
                result.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => result.push(c),
        }
    }
    result
}
