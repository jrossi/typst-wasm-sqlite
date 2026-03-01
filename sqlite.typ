// SQLite Plugin for Typst
// Allows querying SQLite databases at compile time

#let _plugin = plugin("zig-out/bin/typst_sqlite_zig.wasm")

/// Open a SQLite database from a file path
/// Returns a database object with query methods
///
/// Example:
/// ```typst
/// #let db = sqlite("data.sqlite")
/// #let cities = db.query("SELECT * FROM cities")
/// ```
#let sqlite(path) = {
  let db_bytes = read(path, encoding: none)

  (
    /// Execute a SQL query and return results
    /// Returns a dictionary with `columns` and `rows` keys
    query: (sql) => {
      let result_bytes = _plugin.query(db_bytes, bytes(sql))
      let result = json(result_bytes)
      if "error" in result {
        panic("SQLite error: " + result.error)
      }
      result
    },

    /// List all table names in the database
    tables: () => {
      let result_bytes = _plugin.tables(db_bytes)
      json(result_bytes)
    },

    /// Get schema information for a table
    schema: (table_name) => {
      let result_bytes = _plugin.schema(db_bytes, bytes(table_name))
      let result = json(result_bytes)
      if "error" in result {
        panic("SQLite error: " + result.error)
      }
      result
    },

    /// Raw database bytes (for advanced use)
    _bytes: db_bytes,
  )
}

/// Execute a query and format as a Typst table
///
/// Example:
/// ```typst
/// #let db = sqlite("data.sqlite")
/// #sqlite-table(db.query("SELECT name, population FROM cities"))
/// ```
#let sqlite-table(result, ..args) = {
  if "error" in result {
    [*Error:* #result.error]
  } else {
    table(
      columns: result.columns.len(),
      ..args,
      ..result.columns.map(c => [*#c*]),
      ..result.rows.flatten().map(v => [#v])
    )
  }
}

/// Query a database and return results as table-ready data
/// Convenience function combining query and table formatting
///
/// Example:
/// ```typst
/// #let db = sqlite("data.sqlite")
/// #table(
///   columns: 2,
///   ..db.query-table("SELECT name, pop FROM cities")
/// )
/// ```
#let query-table(db, sql) = {
  let result = db.query(sql)
  if "error" in result {
    ([*Error:* #result.error],)
  } else {
    (
      ..result.columns.map(c => [*#c*]),
      ..result.rows.flatten().map(v => [#v])
    )
  }
}
