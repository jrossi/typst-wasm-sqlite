//! Typst SQLite Plugin - A WASM plugin for reading SQLite databases in Typst
//!
//! This plugin allows loading SQLite database files and executing queries at compile time.

use wasm_minimal_protocol::*;

mod sqlite;

initiate_protocol!();

/// Query a SQLite database and return results as JSON
///
/// Arguments:
/// - db_bytes: The raw bytes of the SQLite database file
/// - query_bytes: The SQL query string as bytes
///
/// Returns: JSON-encoded query results or error message
#[wasm_func]
pub fn query(db_bytes: &[u8], query_bytes: &[u8]) -> Vec<u8> {
    let query_str = match core::str::from_utf8(query_bytes) {
        Ok(s) => s,
        Err(_) => return b"{\"error\": \"Invalid UTF-8 in query\"}".to_vec(),
    };

    match sqlite::Database::from_bytes(db_bytes) {
        Ok(db) => match db.execute_query(query_str) {
            Ok(results) => results.to_json().into_bytes(),
            Err(e) => format!("{{\"error\": \"{}\"}}", e).into_bytes(),
        },
        Err(e) => format!("{{\"error\": \"{}\"}}", e).into_bytes(),
    }
}

/// List all tables in the database
#[wasm_func]
pub fn tables(db_bytes: &[u8]) -> Vec<u8> {
    match sqlite::Database::from_bytes(db_bytes) {
        Ok(db) => {
            let tables = db.table_names();
            let json = format!(
                "[{}]",
                tables
                    .iter()
                    .map(|t| format!("\"{}\"", t))
                    .collect::<Vec<_>>()
                    .join(",")
            );
            json.into_bytes()
        }
        Err(e) => format!("{{\"error\": \"{}\"}}", e).into_bytes(),
    }
}

/// Get the schema (column names and types) for a table
#[wasm_func]
pub fn schema(db_bytes: &[u8], table_name: &[u8]) -> Vec<u8> {
    let table = match core::str::from_utf8(table_name) {
        Ok(s) => s,
        Err(_) => return b"{\"error\": \"Invalid UTF-8 in table name\"}".to_vec(),
    };

    match sqlite::Database::from_bytes(db_bytes) {
        Ok(db) => match db.get_table_schema(table) {
            Some(schema) => schema.to_json().into_bytes(),
            None => format!("{{\"error\": \"Table not found: {}\"}}", table).into_bytes(),
        },
        Err(e) => format!("{{\"error\": \"{}\"}}", e).into_bytes(),
    }
}

/// Simple test function
#[wasm_func]
pub fn hello() -> Vec<u8> {
    b"Hello from typst-sqlite!".to_vec()
}
