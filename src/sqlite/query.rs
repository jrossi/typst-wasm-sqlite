//! Query execution and results

use super::value::Value;

/// Result of a query execution
#[derive(Debug)]
pub struct QueryResult {
    /// Column names
    pub columns: Vec<String>,
    /// Row data
    pub rows: Vec<Vec<Value>>,
}

impl QueryResult {
    /// Convert the result to JSON
    pub fn to_json(&self) -> String {
        let mut json = String::from("{\"columns\":[");

        // Add column names
        for (i, col) in self.columns.iter().enumerate() {
            if i > 0 {
                json.push(',');
            }
            json.push('"');
            json.push_str(&escape_json(col));
            json.push('"');
        }

        json.push_str("],\"rows\":[");

        // Add rows
        for (i, row) in self.rows.iter().enumerate() {
            if i > 0 {
                json.push(',');
            }
            json.push('[');

            for (j, value) in row.iter().enumerate() {
                if j > 0 {
                    json.push(',');
                }
                json.push_str(&value.to_json());
            }

            json.push(']');
        }

        json.push_str("]}");
        json
    }

    /// Get the number of rows
    pub fn row_count(&self) -> usize {
        self.rows.len()
    }

    /// Get the number of columns
    pub fn column_count(&self) -> usize {
        self.columns.len()
    }
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
