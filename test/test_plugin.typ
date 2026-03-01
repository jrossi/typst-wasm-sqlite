// Low-level plugin tests — direct WASM plugin calls
#let plugin = plugin("../zig-out/bin/typst_sqlite_zig.wasm")
#let db = read("test.sqlite", encoding: none)

// =============================================================================
// hello()
// =============================================================================

#assert.eq(str(plugin.hello()), "Hello from typst-sqlite-zig!")

// =============================================================================
// tables()
// =============================================================================

#let tbl = json(plugin.tables(db))
#assert(type(tbl) == array, message: "tables() should return an array")
#assert(tbl.contains("cities"), message: "should contain cities table")
#assert(tbl.contains("types_test"), message: "should contain types_test table")
#assert(tbl.contains("empty_table"), message: "should contain empty_table table")
#assert(tbl.contains("many_rows"), message: "should contain many_rows table")
#assert.eq(tbl.len(), 8)

// =============================================================================
// query() — structure and basic data
// =============================================================================

#let result = json(plugin.query(db, bytes("SELECT name, country, population FROM cities ORDER BY name")))
#assert("columns" in result, message: "result should have columns key")
#assert("rows" in result, message: "result should have rows key")
#assert.eq(result.columns, ("name", "country", "population"))
#assert.eq(result.rows.len(), 5)

// Check first city (alphabetical)
#assert.eq(result.rows.at(0).at(0), "Delhi")
#assert.eq(result.rows.at(0).at(1), "India")

// =============================================================================
// query() — type handling
// =============================================================================

#let types = json(plugin.query(db, bytes("SELECT * FROM types_test ORDER BY id")))

// Row 1: normal values
#assert.eq(types.rows.at(0).at(1), 42)
#assert.eq(types.rows.at(0).at(3), "hello")

// Row 2: zeros
#assert.eq(types.rows.at(1).at(1), 0)
#assert.eq(types.rows.at(1).at(3), "")

// Row 5: all NULLs (except id) → none
#assert.eq(types.rows.at(4).at(1), none)
#assert.eq(types.rows.at(4).at(2), none)
#assert.eq(types.rows.at(4).at(3), none)

// =============================================================================
// query() — i64 edge values
// =============================================================================

#let nums = json(plugin.query(db, bytes("SELECT int_val FROM numbers WHERE label = 'i64_max'")))
#assert.eq(nums.rows.at(0).at(0), 9223372036854775807)

#let nums_min = json(plugin.query(db, bytes("SELECT int_val FROM numbers WHERE label = 'i64_min'")))
#assert.eq(nums_min.rows.at(0).at(0), -9223372036854775808)

// =============================================================================
// query() — text escaping round-trip
// =============================================================================

#let esc = json(plugin.query(db, bytes("SELECT label, value FROM text_escaping ORDER BY id")))
#assert.eq(esc.rows.at(0).at(0), "double_quote")
#assert.eq(esc.rows.at(0).at(1), "say \"hello\"")
#assert.eq(esc.rows.at(1).at(1), "path\\to\\file")
#assert.eq(esc.rows.at(2).at(1), "line1\nline2")
#assert.eq(esc.rows.at(3).at(1), "col1\tcol2")
#assert.eq(esc.rows.at(8).at(1), "")
#assert.eq(esc.rows.at(9).at(1), "just plain text")

// =============================================================================
// query() — empty results
// =============================================================================

#let empty = json(plugin.query(db, bytes("SELECT * FROM empty_table")))
#assert.eq(empty.rows.len(), 0)
#assert.eq(empty.columns, ("id", "name", "value"))

// =============================================================================
// query() — COUNT(*)
// =============================================================================

#let count = json(plugin.query(db, bytes("SELECT COUNT(*) FROM many_rows")))
#assert.eq(count.rows.at(0).at(0), 500)

// =============================================================================
// query() — wide table
// =============================================================================

#let wide = json(plugin.query(db, bytes("SELECT * FROM wide_table")))
#assert.eq(wide.columns.len(), 50)
#assert.eq(wide.rows.len(), 1)

// Note: SQL errors (e.g. nonexistent table) cause a Typst compile error
// via the plugin protocol (return code 1), so they cannot be tested as data.
// The error JSON formatting is tested at the Zig unit level.

// =============================================================================
// schema()
// =============================================================================

#let schema = json(plugin.schema(db, bytes("cities")))
#assert("columns" in schema, message: "schema should have columns key")
#assert.eq(schema.columns.len(), 3)
#assert.eq(schema.columns.at(0).name, "name")
#assert.eq(schema.columns.at(0).type, "TEXT")
#assert.eq(schema.columns.at(2).name, "population")
#assert.eq(schema.columns.at(2).type, "INTEGER")

// schema for empty table
#let empty_schema = json(plugin.schema(db, bytes("empty_table")))
#assert.eq(empty_schema.columns.len(), 3)

// Note: schema() injection defense (e.g. "cities; DROP TABLE cities") returns
// error code 1 which causes a Typst compile error. The isValidTableName()
// validation is tested at the Zig unit level.
