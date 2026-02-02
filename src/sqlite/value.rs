//! SQLite value types

use std::fmt;

/// Represents a value stored in SQLite
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    /// NULL value
    Null,
    /// Integer value (1, 2, 3, 4, 6, or 8 bytes)
    Integer(i64),
    /// Floating point value (8 bytes IEEE 754)
    Real(f64),
    /// Text value (UTF-8)
    Text(String),
    /// BLOB value
    Blob(Vec<u8>),
}

impl Value {
    /// Returns true if this value is NULL
    pub fn is_null(&self) -> bool {
        matches!(self, Value::Null)
    }

    /// Convert to JSON representation
    pub fn to_json(&self) -> String {
        match self {
            Value::Null => "null".into(),
            Value::Integer(i) => format!("{}", i),
            Value::Real(f) => {
                if f.is_nan() {
                    "null".into()
                } else if f.is_infinite() {
                    if *f > 0.0 {
                        "1e308".into()
                    } else {
                        "-1e308".into()
                    }
                } else {
                    format!("{}", f)
                }
            }
            Value::Text(s) => {
                let escaped = escape_json_string(s);
                format!("\"{}\"", escaped)
            }
            Value::Blob(b) => {
                // Encode as base64-like hex string
                let hex: String = b.iter().map(|byte| format!("{:02x}", byte)).collect();
                format!("\"blob:{}\"", hex)
            }
        }
    }
}

impl fmt::Display for Value {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Value::Null => write!(f, "NULL"),
            Value::Integer(i) => write!(f, "{}", i),
            Value::Real(r) => write!(f, "{}", r),
            Value::Text(s) => write!(f, "{}", s),
            Value::Blob(b) => write!(f, "BLOB({} bytes)", b.len()),
        }
    }
}

/// Escape a string for JSON
fn escape_json_string(s: &str) -> String {
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

/// Read a variable-length integer (varint) from bytes
/// Returns (value, bytes_consumed)
pub fn read_varint(data: &[u8]) -> Option<(i64, usize)> {
    if data.is_empty() {
        return None;
    }

    let mut result: u64 = 0;
    let mut bytes_read = 0;

    for (i, &byte) in data.iter().enumerate().take(9) {
        bytes_read = i + 1;

        if i == 8 {
            // 9th byte uses all 8 bits
            result = (result << 8) | (byte as u64);
            break;
        }

        result = (result << 7) | ((byte & 0x7f) as u64);

        if byte & 0x80 == 0 {
            break;
        }
    }

    Some((result as i64, bytes_read))
}

/// Decode a SQLite serial type to a Value
pub fn decode_value(serial_type: i64, data: &[u8]) -> Option<(Value, usize)> {
    match serial_type {
        0 => Some((Value::Null, 0)),
        1 => {
            if data.is_empty() {
                return None;
            }
            Some((Value::Integer(data[0] as i8 as i64), 1))
        }
        2 => {
            if data.len() < 2 {
                return None;
            }
            let val = i16::from_be_bytes([data[0], data[1]]);
            Some((Value::Integer(val as i64), 2))
        }
        3 => {
            if data.len() < 3 {
                return None;
            }
            let val = ((data[0] as i32) << 16) | ((data[1] as i32) << 8) | (data[2] as i32);
            // Sign extend from 24 bits
            let val = if val & 0x800000 != 0 {
                val | !0xffffff
            } else {
                val
            };
            Some((Value::Integer(val as i64), 3))
        }
        4 => {
            if data.len() < 4 {
                return None;
            }
            let val = i32::from_be_bytes([data[0], data[1], data[2], data[3]]);
            Some((Value::Integer(val as i64), 4))
        }
        5 => {
            if data.len() < 6 {
                return None;
            }
            let mut bytes = [0u8; 8];
            bytes[2..8].copy_from_slice(&data[0..6]);
            let val = i64::from_be_bytes(bytes);
            // Sign extend from 48 bits
            let val = if val & 0x800000000000 != 0 {
                val | !0xffffffffffff
            } else {
                val
            };
            Some((Value::Integer(val), 6))
        }
        6 => {
            if data.len() < 8 {
                return None;
            }
            let val = i64::from_be_bytes([
                data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7],
            ]);
            Some((Value::Integer(val), 8))
        }
        7 => {
            if data.len() < 8 {
                return None;
            }
            let val = f64::from_be_bytes([
                data[0], data[1], data[2], data[3], data[4], data[5], data[6], data[7],
            ]);
            Some((Value::Real(val), 8))
        }
        8 => Some((Value::Integer(0), 0)),
        9 => Some((Value::Integer(1), 0)),
        n if n >= 12 && n % 2 == 0 => {
            // BLOB
            let len = ((n - 12) / 2) as usize;
            if data.len() < len {
                return None;
            }
            Some((Value::Blob(data[..len].to_vec()), len))
        }
        n if n >= 13 && n % 2 == 1 => {
            // TEXT
            let len = ((n - 13) / 2) as usize;
            if data.len() < len {
                return None;
            }
            let text = core::str::from_utf8(&data[..len])
                .map(|s| s.to_string())
                .unwrap_or_else(|_| String::from_utf8_lossy(&data[..len]).into_owned());
            Some((Value::Text(text), len))
        }
        _ => None,
    }
}
