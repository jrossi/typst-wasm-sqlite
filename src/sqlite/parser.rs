//! SQLite database parser

use std::collections::BTreeMap;

use super::error::{Error, Result};
use super::format::{BTreePageHeader, FileHeader, PageType, MIN_DATABASE_SIZE};
use super::query::QueryResult;
use super::value::{decode_value, read_varint, Value};
use super::{ColumnInfo, TableSchema};

/// A parsed SQLite database
pub struct Database<'a> {
    /// Raw database bytes
    data: &'a [u8],
    /// File header
    header: FileHeader,
    /// Table schemas (name -> schema)
    tables: BTreeMap<String, TableSchema>,
}

/// Parsed SELECT query
#[derive(Debug)]
struct ParsedQuery {
    columns: Vec<String>,
    select_all: bool,
    table_name: String,
    where_clause: Option<WhereClause>,
    order_by: Option<OrderByClause>,
    limit: Option<usize>,
    offset: Option<usize>,
}

/// WHERE clause condition
#[derive(Debug, Clone)]
enum WhereClause {
    Comparison {
        column: String,
        op: CompareOp,
        value: Value,
    },
    IsNull {
        column: String,
        is_null: bool,
    },
    And(Box<WhereClause>, Box<WhereClause>),
    Or(Box<WhereClause>, Box<WhereClause>),
    Not(Box<WhereClause>),
}

/// Comparison operator
#[derive(Debug, Clone, Copy)]
enum CompareOp {
    Eq,
    Ne,
    Lt,
    Le,
    Gt,
    Ge,
    Like,
}

/// ORDER BY clause
#[derive(Debug)]
struct OrderByClause {
    column: String,
    descending: bool,
}

impl<'a> Database<'a> {
    /// Create a database from raw bytes
    pub fn from_bytes(data: &'a [u8]) -> Result<Self> {
        if data.len() < MIN_DATABASE_SIZE {
            return Err(Error::TooSmall);
        }

        let header = FileHeader::parse(data).ok_or_else(|| Error::InvalidFormat("Invalid header".into()))?;

        // Only UTF-8 encoding is supported
        if header.text_encoding != 1 {
            return Err(Error::UnsupportedFeature("Only UTF-8 encoding is supported".into()));
        }

        let mut db = Database {
            data,
            header,
            tables: BTreeMap::new(),
        };

        // Load schema from sqlite_schema table (page 1)
        db.load_schema()?;

        Ok(db)
    }

    /// Get page data by page number (1-indexed)
    fn get_page(&self, page_num: u32) -> Result<&[u8]> {
        if page_num == 0 {
            return Err(Error::InvalidPage(0));
        }

        let page_size = self.header.page_size as usize;
        let offset = (page_num as usize - 1) * page_size;

        if offset + page_size > self.data.len() {
            return Err(Error::InvalidPage(page_num));
        }

        Ok(&self.data[offset..offset + page_size])
    }

    /// Load schema from sqlite_schema (page 1)
    fn load_schema(&mut self) -> Result<()> {
        let page = self.get_page(1)?;
        let records = self.read_table_leaf_page(page, true)?;

        for record in records {
            // sqlite_schema has: type, name, tbl_name, rootpage, sql
            if record.len() < 5 {
                continue;
            }

            let obj_type = match &record[0] {
                Value::Text(s) => s.as_str(),
                _ => continue,
            };

            if obj_type != "table" {
                continue;
            }

            let name = match &record[1] {
                Value::Text(s) => s.clone(),
                _ => continue,
            };

            // Skip internal tables
            if name.starts_with("sqlite_") {
                continue;
            }

            let sql = match &record[4] {
                Value::Text(s) => s.clone(),
                Value::Null => String::new(),
                _ => continue,
            };

            // Parse columns from CREATE TABLE statement
            let columns = parse_create_table_columns(&sql);

            self.tables.insert(
                name.clone(),
                TableSchema {
                    name,
                    columns,
                    sql,
                },
            );
        }

        Ok(())
    }

    /// Read records from a table leaf page
    fn read_table_leaf_page(&self, page: &[u8], is_first_page: bool) -> Result<Vec<Vec<Value>>> {
        let header = BTreePageHeader::parse(page, is_first_page)
            .ok_or_else(|| Error::InvalidFormat("Invalid page header".into()))?;

        if header.page_type != PageType::LeafTable {
            return Ok(Vec::new());
        }

        let header_offset = if is_first_page { 100 } else { 0 };
        let cell_ptr_offset = header_offset + header.header_size();

        let mut records = Vec::new();

        for i in 0..header.cell_count as usize {
            let ptr_offset = cell_ptr_offset + i * 2;
            if ptr_offset + 2 > page.len() {
                break;
            }

            let cell_offset = u16::from_be_bytes([page[ptr_offset], page[ptr_offset + 1]]) as usize;

            if cell_offset >= page.len() {
                continue;
            }

            if let Some(record) = self.parse_table_leaf_cell(&page[cell_offset..]) {
                records.push(record);
            }
        }

        Ok(records)
    }

    /// Parse a table leaf cell and return the record values
    fn parse_table_leaf_cell(&self, cell: &[u8]) -> Option<Vec<Value>> {
        // Table leaf cell: payload_size (varint), rowid (varint), payload
        let (payload_size, n1) = read_varint(cell)?;
        let (_rowid, n2) = read_varint(&cell[n1..])?;

        let payload_start = n1 + n2;
        let payload_end = payload_start + payload_size as usize;

        if payload_end > cell.len() {
            return None;
        }

        let payload = &cell[payload_start..payload_end];
        self.parse_record(payload)
    }

    /// Parse a record payload into values
    fn parse_record(&self, payload: &[u8]) -> Option<Vec<Value>> {
        // Record format: header_size (varint), type codes (varints), values
        let (header_size, mut offset) = read_varint(payload)?;
        let header_end = header_size as usize;

        if header_end > payload.len() {
            return None;
        }

        // Read serial types
        let mut serial_types = Vec::new();
        while offset < header_end {
            let (serial_type, n) = read_varint(&payload[offset..])?;
            serial_types.push(serial_type);
            offset += n;
        }

        // Read values
        let mut values = Vec::new();
        let mut data_offset = header_end;

        for serial_type in serial_types {
            let (value, size) = decode_value(serial_type, &payload[data_offset..])?;
            values.push(value);
            data_offset += size;
        }

        Some(values)
    }

    /// Get all table names
    pub fn table_names(&self) -> Vec<String> {
        self.tables.keys().cloned().collect()
    }

    /// Get schema for a table
    pub fn get_table_schema(&self, name: &str) -> Option<TableSchema> {
        self.tables.get(name).cloned()
    }

    /// Execute a SELECT query
    pub fn execute_query(&self, query: &str) -> Result<QueryResult> {
        let parsed = self.parse_query(query)?;

        // Get table schema
        let schema = self
            .tables
            .get(&parsed.table_name)
            .ok_or_else(|| Error::TableNotFound(parsed.table_name.clone()))?;

        // Determine which columns to select
        let column_names: Vec<String> = if parsed.select_all {
            schema.columns.iter().map(|c| c.name.clone()).collect()
        } else {
            parsed.columns.clone()
        };

        // Map column names to indices
        let column_indices: Vec<usize> = column_names
            .iter()
            .filter_map(|name| {
                schema.columns.iter().position(|c| c.name.eq_ignore_ascii_case(name))
            })
            .collect();

        // Create column name to index mapping for WHERE evaluation
        let col_map: BTreeMap<String, usize> = schema
            .columns
            .iter()
            .enumerate()
            .map(|(i, c)| (c.name.to_lowercase(), i))
            .collect();

        // Read all records from the table
        let records = self.read_all_table_records(&parsed.table_name)?;

        // Filter by WHERE clause
        let mut filtered: Vec<Vec<Value>> = if let Some(ref where_clause) = parsed.where_clause {
            records
                .into_iter()
                .filter(|record| evaluate_where(where_clause, record, &col_map))
                .collect()
        } else {
            records
        };

        // Sort by ORDER BY
        if let Some(ref order_by) = parsed.order_by {
            if let Some(&col_idx) = col_map.get(&order_by.column.to_lowercase()) {
                filtered.sort_by(|a, b| {
                    let val_a = a.get(col_idx).unwrap_or(&Value::Null);
                    let val_b = b.get(col_idx).unwrap_or(&Value::Null);
                    let cmp = compare_values(val_a, val_b);
                    if order_by.descending {
                        cmp.reverse()
                    } else {
                        cmp
                    }
                });
            }
        }

        // Apply OFFSET
        if let Some(offset) = parsed.offset {
            if offset < filtered.len() {
                filtered = filtered.into_iter().skip(offset).collect();
            } else {
                filtered.clear();
            }
        }

        // Apply LIMIT
        if let Some(limit) = parsed.limit {
            filtered.truncate(limit);
        }

        // Project columns
        let rows: Vec<Vec<Value>> = filtered
            .into_iter()
            .map(|record| {
                if parsed.select_all {
                    record
                } else {
                    column_indices
                        .iter()
                        .map(|&i| record.get(i).cloned().unwrap_or(Value::Null))
                        .collect()
                }
            })
            .collect();

        Ok(QueryResult {
            columns: column_names,
            rows,
        })
    }

    /// Parse a SELECT query string
    fn parse_query(&self, query: &str) -> Result<ParsedQuery> {
        let query = query.trim().trim_end_matches(';');
        let query_upper = query.to_uppercase();

        if !query_upper.starts_with("SELECT ") {
            return Err(Error::QueryError("Only SELECT queries are supported".into()));
        }

        // Find FROM clause
        let from_pos = query_upper.find(" FROM ")
            .ok_or_else(|| Error::QueryError("Missing FROM clause".into()))?;

        // Extract columns part
        let columns_part = query[7..from_pos].trim();
        let select_all = columns_part == "*";
        let columns: Vec<String> = if select_all {
            Vec::new()
        } else {
            columns_part
                .split(',')
                .map(|s| s.trim().to_string())
                .collect()
        };

        // Find the end of table name (WHERE, ORDER, LIMIT, or end)
        let after_from = &query[from_pos + 6..];
        let after_from_upper = after_from.to_uppercase();

        let table_end = after_from_upper
            .find(" WHERE ")
            .or_else(|| after_from_upper.find(" ORDER "))
            .or_else(|| after_from_upper.find(" LIMIT "))
            .unwrap_or(after_from.len());

        let table_name = after_from[..table_end].trim().to_string();

        // Parse WHERE clause
        let where_clause = if let Some(where_pos) = after_from_upper.find(" WHERE ") {
            let where_start = where_pos + 7;
            let where_end = after_from_upper[where_start..]
                .find(" ORDER ")
                .or_else(|| after_from_upper[where_start..].find(" LIMIT "))
                .map(|p| where_start + p)
                .unwrap_or(after_from.len());

            let where_str = after_from[where_start..where_end].trim();
            Some(parse_where_clause(where_str)?)
        } else {
            None
        };

        // Parse ORDER BY clause
        let order_by = if let Some(order_pos) = after_from_upper.find(" ORDER BY ") {
            let order_start = order_pos + 10;
            let order_end = after_from_upper[order_start..]
                .find(" LIMIT ")
                .map(|p| order_start + p)
                .unwrap_or(after_from.len());

            let order_str = after_from[order_start..order_end].trim();
            Some(parse_order_by(order_str))
        } else {
            None
        };

        // Parse LIMIT and OFFSET
        let (limit, offset) = if let Some(limit_pos) = after_from_upper.find(" LIMIT ") {
            let limit_start = limit_pos + 7;
            let limit_str = after_from[limit_start..].trim();
            parse_limit_offset(limit_str)
        } else {
            (None, None)
        };

        Ok(ParsedQuery {
            columns,
            select_all,
            table_name,
            where_clause,
            order_by,
            limit,
            offset,
        })
    }

    /// Read all records from a table
    fn read_all_table_records(&self, table_name: &str) -> Result<Vec<Vec<Value>>> {
        // Find the table's root page from the schema
        let page = self.get_page(1)?;
        let schema_records = self.read_table_leaf_page(page, true)?;

        let mut root_page: Option<u32> = None;

        for record in schema_records {
            if record.len() < 5 {
                continue;
            }

            let obj_type = match &record[0] {
                Value::Text(s) => s.as_str(),
                _ => continue,
            };

            if obj_type != "table" {
                continue;
            }

            let name = match &record[1] {
                Value::Text(s) => s.as_str(),
                _ => continue,
            };

            if name == table_name {
                root_page = match &record[3] {
                    Value::Integer(n) => Some(*n as u32),
                    _ => None,
                };
                break;
            }
        }

        let root_page = root_page.ok_or_else(|| Error::TableNotFound(table_name.to_string()))?;

        // Read all records from the table's B-tree
        self.read_btree_table(root_page)
    }

    /// Read all records from a B-tree table
    fn read_btree_table(&self, root_page_num: u32) -> Result<Vec<Vec<Value>>> {
        let page = self.get_page(root_page_num)?;
        let is_first_page = root_page_num == 1;

        let header = BTreePageHeader::parse(page, is_first_page)
            .ok_or_else(|| Error::InvalidFormat("Invalid page header".into()))?;

        match header.page_type {
            PageType::LeafTable => self.read_table_leaf_page(page, is_first_page),
            PageType::InteriorTable => {
                // For interior pages, we need to traverse child pages
                let mut all_records = Vec::new();
                let header_offset = if is_first_page { 100 } else { 0 };
                let cell_ptr_offset = header_offset + header.header_size();

                for i in 0..header.cell_count as usize {
                    let ptr_offset = cell_ptr_offset + i * 2;
                    if ptr_offset + 2 > page.len() {
                        break;
                    }

                    let cell_offset =
                        u16::from_be_bytes([page[ptr_offset], page[ptr_offset + 1]]) as usize;

                    if cell_offset + 4 > page.len() {
                        continue;
                    }

                    // Interior table cell: left_child (4 bytes), rowid (varint)
                    let left_child = u32::from_be_bytes([
                        page[cell_offset],
                        page[cell_offset + 1],
                        page[cell_offset + 2],
                        page[cell_offset + 3],
                    ]);

                    let child_records = self.read_btree_table(left_child)?;
                    all_records.extend(child_records);
                }

                // Don't forget the right-most child
                if let Some(right_child) = header.right_child {
                    let child_records = self.read_btree_table(right_child)?;
                    all_records.extend(child_records);
                }

                Ok(all_records)
            }
            _ => Err(Error::InvalidPageType(header.page_type as u8)),
        }
    }
}

/// Parse a WHERE clause string into a WhereClause tree
fn parse_where_clause(s: &str) -> Result<WhereClause> {
    let s = s.trim();

    // Try to parse OR (lowest precedence)
    if let Some((left, right)) = split_on_keyword(s, " OR ") {
        let left_clause = parse_where_clause(left)?;
        let right_clause = parse_where_clause(right)?;
        return Ok(WhereClause::Or(Box::new(left_clause), Box::new(right_clause)));
    }

    // Try to parse AND
    if let Some((left, right)) = split_on_keyword(s, " AND ") {
        let left_clause = parse_where_clause(left)?;
        let right_clause = parse_where_clause(right)?;
        return Ok(WhereClause::And(Box::new(left_clause), Box::new(right_clause)));
    }

    // Try to parse NOT
    let s_upper = s.to_uppercase();
    if s_upper.starts_with("NOT ") {
        let inner = parse_where_clause(&s[4..])?;
        return Ok(WhereClause::Not(Box::new(inner)));
    }

    // Handle parentheses
    if s.starts_with('(') && s.ends_with(')') {
        return parse_where_clause(&s[1..s.len()-1]);
    }

    // Parse IS NULL / IS NOT NULL
    if let Some(pos) = s_upper.find(" IS NOT NULL") {
        let column = s[..pos].trim().to_string();
        return Ok(WhereClause::IsNull { column, is_null: false });
    }
    if let Some(pos) = s_upper.find(" IS NULL") {
        let column = s[..pos].trim().to_string();
        return Ok(WhereClause::IsNull { column, is_null: true });
    }

    // Parse comparison operators
    let ops = [
        ("!=", CompareOp::Ne),
        ("<>", CompareOp::Ne),
        ("<=", CompareOp::Le),
        (">=", CompareOp::Ge),
        ("<", CompareOp::Lt),
        (">", CompareOp::Gt),
        ("=", CompareOp::Eq),
    ];

    for (op_str, op) in ops {
        if let Some(pos) = s.find(op_str) {
            let column = s[..pos].trim().to_string();
            let value_str = s[pos + op_str.len()..].trim();
            let value = parse_literal(value_str);
            return Ok(WhereClause::Comparison { column, op, value });
        }
    }

    // Try LIKE
    if let Some(pos) = s_upper.find(" LIKE ") {
        let column = s[..pos].trim().to_string();
        let value_str = s[pos + 6..].trim();
        let value = parse_literal(value_str);
        return Ok(WhereClause::Comparison { column, op: CompareOp::Like, value });
    }

    Err(Error::QueryError(format!("Cannot parse WHERE condition: {}", s)))
}

/// Split string on keyword, respecting parentheses
fn split_on_keyword<'a>(s: &'a str, keyword: &str) -> Option<(&'a str, &'a str)> {
    let s_upper = s.to_uppercase();
    let keyword_upper = keyword.to_uppercase();

    let mut depth = 0;
    let mut i = 0;
    let chars: Vec<char> = s.chars().collect();

    while i < chars.len() {
        match chars[i] {
            '(' => depth += 1,
            ')' => depth -= 1,
            _ => {}
        }

        if depth == 0 && s_upper[i..].starts_with(&keyword_upper) {
            return Some((&s[..i], &s[i + keyword.len()..]));
        }

        i += 1;
    }

    None
}

/// Parse a literal value from a string
fn parse_literal(s: &str) -> Value {
    let s = s.trim();

    // NULL
    if s.eq_ignore_ascii_case("NULL") {
        return Value::Null;
    }

    // String literal
    if (s.starts_with('\'') && s.ends_with('\'')) || (s.starts_with('"') && s.ends_with('"')) {
        return Value::Text(s[1..s.len()-1].replace("''", "'").replace("\"\"", "\""));
    }

    // Integer
    if let Ok(i) = s.parse::<i64>() {
        return Value::Integer(i);
    }

    // Float
    if let Ok(f) = s.parse::<f64>() {
        return Value::Real(f);
    }

    // Default to text
    Value::Text(s.to_string())
}

/// Parse ORDER BY clause
fn parse_order_by(s: &str) -> OrderByClause {
    let s_upper = s.to_uppercase();
    let descending = s_upper.ends_with(" DESC");
    let ascending = s_upper.ends_with(" ASC");

    let column = if descending {
        s[..s.len() - 5].trim().to_string()
    } else if ascending {
        s[..s.len() - 4].trim().to_string()
    } else {
        s.trim().to_string()
    };

    OrderByClause { column, descending }
}

/// Parse LIMIT and OFFSET
fn parse_limit_offset(s: &str) -> (Option<usize>, Option<usize>) {
    let s_upper = s.to_uppercase();

    // Check for OFFSET keyword
    if let Some(offset_pos) = s_upper.find(" OFFSET ") {
        let limit_str = s[..offset_pos].trim();
        let offset_str = s[offset_pos + 8..].trim();

        let limit = limit_str.parse().ok();
        let offset = offset_str.parse().ok();

        return (limit, offset);
    }

    // Check for comma syntax: LIMIT offset, count
    if let Some(comma_pos) = s.find(',') {
        let offset_str = s[..comma_pos].trim();
        let limit_str = s[comma_pos + 1..].trim();

        let limit = limit_str.parse().ok();
        let offset = offset_str.parse().ok();

        return (limit, offset);
    }

    // Just LIMIT
    let limit = s.trim().parse().ok();
    (limit, None)
}

/// Evaluate a WHERE clause against a record
fn evaluate_where(clause: &WhereClause, record: &[Value], col_map: &BTreeMap<String, usize>) -> bool {
    match clause {
        WhereClause::Comparison { column, op, value } => {
            let col_idx = match col_map.get(&column.to_lowercase()) {
                Some(&idx) => idx,
                None => return false,
            };

            let record_value = match record.get(col_idx) {
                Some(v) => v,
                None => return false,
            };

            match op {
                CompareOp::Eq => values_equal(record_value, value),
                CompareOp::Ne => !values_equal(record_value, value),
                CompareOp::Lt => compare_values(record_value, value) == std::cmp::Ordering::Less,
                CompareOp::Le => compare_values(record_value, value) != std::cmp::Ordering::Greater,
                CompareOp::Gt => compare_values(record_value, value) == std::cmp::Ordering::Greater,
                CompareOp::Ge => compare_values(record_value, value) != std::cmp::Ordering::Less,
                CompareOp::Like => match_like(record_value, value),
            }
        }
        WhereClause::IsNull { column, is_null } => {
            let col_idx = match col_map.get(&column.to_lowercase()) {
                Some(&idx) => idx,
                None => return false,
            };

            let record_value = record.get(col_idx);
            let is_null_actual = matches!(record_value, None | Some(Value::Null));

            is_null_actual == *is_null
        }
        WhereClause::And(left, right) => {
            evaluate_where(left, record, col_map) && evaluate_where(right, record, col_map)
        }
        WhereClause::Or(left, right) => {
            evaluate_where(left, record, col_map) || evaluate_where(right, record, col_map)
        }
        WhereClause::Not(inner) => {
            !evaluate_where(inner, record, col_map)
        }
    }
}

/// Check if two values are equal
fn values_equal(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Null, Value::Null) => true,
        (Value::Integer(x), Value::Integer(y)) => x == y,
        (Value::Integer(x), Value::Real(y)) => (*x as f64) == *y,
        (Value::Real(x), Value::Integer(y)) => *x == (*y as f64),
        (Value::Real(x), Value::Real(y)) => x == y,
        (Value::Text(x), Value::Text(y)) => x.eq_ignore_ascii_case(y),
        (Value::Blob(x), Value::Blob(y)) => x == y,
        _ => false,
    }
}

/// Compare two values for ordering
fn compare_values(a: &Value, b: &Value) -> std::cmp::Ordering {
    use std::cmp::Ordering;

    match (a, b) {
        (Value::Null, Value::Null) => Ordering::Equal,
        (Value::Null, _) => Ordering::Less,
        (_, Value::Null) => Ordering::Greater,
        (Value::Integer(x), Value::Integer(y)) => x.cmp(y),
        (Value::Integer(x), Value::Real(y)) => (*x as f64).partial_cmp(y).unwrap_or(Ordering::Equal),
        (Value::Real(x), Value::Integer(y)) => x.partial_cmp(&(*y as f64)).unwrap_or(Ordering::Equal),
        (Value::Real(x), Value::Real(y)) => x.partial_cmp(y).unwrap_or(Ordering::Equal),
        (Value::Text(x), Value::Text(y)) => x.cmp(y),
        (Value::Blob(x), Value::Blob(y)) => x.cmp(y),
        _ => Ordering::Equal,
    }
}

/// Match LIKE pattern (supports % and _ wildcards)
fn match_like(value: &Value, pattern: &Value) -> bool {
    let text = match value {
        Value::Text(s) => s.to_lowercase(),
        Value::Integer(i) => i.to_string(),
        Value::Real(f) => f.to_string(),
        _ => return false,
    };

    let pattern = match pattern {
        Value::Text(s) => s.to_lowercase(),
        _ => return false,
    };

    // Convert LIKE pattern to simple matching
    let mut pattern_idx = 0;
    let mut text_idx = 0;
    let pattern_chars: Vec<char> = pattern.chars().collect();
    let text_chars: Vec<char> = text.chars().collect();

    let mut star_idx: Option<usize> = None;
    let mut match_idx = 0;

    while text_idx < text_chars.len() {
        if pattern_idx < pattern_chars.len() &&
           (pattern_chars[pattern_idx] == '_' || pattern_chars[pattern_idx] == text_chars[text_idx]) {
            pattern_idx += 1;
            text_idx += 1;
        } else if pattern_idx < pattern_chars.len() && pattern_chars[pattern_idx] == '%' {
            star_idx = Some(pattern_idx);
            match_idx = text_idx;
            pattern_idx += 1;
        } else if let Some(si) = star_idx {
            pattern_idx = si + 1;
            match_idx += 1;
            text_idx = match_idx;
        } else {
            return false;
        }
    }

    while pattern_idx < pattern_chars.len() && pattern_chars[pattern_idx] == '%' {
        pattern_idx += 1;
    }

    pattern_idx == pattern_chars.len()
}

/// Parse column names from a CREATE TABLE statement
fn parse_create_table_columns(sql: &str) -> Vec<ColumnInfo> {
    let mut columns = Vec::new();

    // Find the opening parenthesis
    let paren_start = match sql.find('(') {
        Some(pos) => pos + 1,
        None => return columns,
    };

    // Find the closing parenthesis
    let paren_end = match sql.rfind(')') {
        Some(pos) => pos,
        None => return columns,
    };

    if paren_start >= paren_end {
        return columns;
    }

    let columns_str = &sql[paren_start..paren_end];

    // Split by comma, but be careful about parentheses in constraints
    let mut depth = 0;
    let mut current = String::new();
    let mut parts = Vec::new();

    for c in columns_str.chars() {
        match c {
            '(' => {
                depth += 1;
                current.push(c);
            }
            ')' => {
                depth -= 1;
                current.push(c);
            }
            ',' if depth == 0 => {
                parts.push(current.trim().to_string());
                current = String::new();
            }
            _ => current.push(c),
        }
    }
    if !current.trim().is_empty() {
        parts.push(current.trim().to_string());
    }

    // Parse each column definition
    for part in parts {
        let part = part.trim();

        // Skip constraints (PRIMARY KEY, FOREIGN KEY, UNIQUE, CHECK, etc.)
        let upper = part.to_uppercase();
        if upper.starts_with("PRIMARY KEY")
            || upper.starts_with("FOREIGN KEY")
            || upper.starts_with("UNIQUE")
            || upper.starts_with("CHECK")
            || upper.starts_with("CONSTRAINT")
        {
            continue;
        }

        // First word is column name, second is type (if present)
        let mut words = part.split_whitespace();
        let name = match words.next() {
            Some(n) => n.trim_matches(|c| c == '"' || c == '`' || c == '[' || c == ']'),
            None => continue,
        };

        let type_name = words.next().unwrap_or("").to_string();

        columns.push(ColumnInfo {
            name: name.to_string(),
            type_name,
        });
    }

    columns
}
