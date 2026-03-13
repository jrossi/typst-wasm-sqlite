// API-level tests — sqlite.typ wrapper
#import "../sqlite.typ": sqlite, sqlite-table, query-table

#let db = sqlite(read("test.sqlite", encoding: none))

// =============================================================================
// db.query()
// =============================================================================

#let result = (db.query)("SELECT name, population FROM cities ORDER BY name LIMIT 3")
#assert.eq(result.columns, ("name", "population"))
#assert.eq(result.rows.len(), 3)
#assert.eq(result.rows.at(0).at(0), "Delhi")

// =============================================================================
// db.tables()
// =============================================================================

#let tables = (db.tables)()
#assert(type(tables) == array, message: "tables should return array")
#assert.eq(tables.len(), 8)
#assert(tables.contains("cities"), message: "should contain cities")

// =============================================================================
// db.schema()
// =============================================================================

#let schema = (db.schema)("cities")
#assert.eq(schema.columns.len(), 3)
#assert.eq(schema.columns.at(0).name, "name")

// =============================================================================
// sqlite-table() renders without panic
// =============================================================================

// Just verify it produces content without panicking
#let rendered = sqlite-table((db.query)("SELECT name FROM cities LIMIT 2"))
#assert(rendered != none, message: "sqlite-table should produce content")

// =============================================================================
// query-table() returns correct array
// =============================================================================

#let qt = query-table(db, "SELECT name FROM cities LIMIT 2")
#assert(type(qt) == array, message: "query-table should return array")
// Should have header + 2 data cells = 3 items
#assert.eq(qt.len(), 3)
