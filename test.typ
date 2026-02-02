#let plugin = plugin("target/wasm32-unknown-unknown/release/typst_sqlite.wasm")

= SQLite Plugin Test

== Basic Test
Hello message: #str(plugin.hello())

== Load Database
#let db = read("test.sqlite", encoding: none)

== List Tables
#let tables_json = str(plugin.tables(db))
Tables: #tables_json

== Query Data
#let result_json = str(plugin.query(db, bytes("SELECT name, population FROM cities")))
Result: #result_json

== Parse and Display
#let result = json.decode(result_json)

#if "error" in result [
  *Error:* #result.error
] else [
  #table(
    columns: result.columns.len(),
    ..result.columns.map(c => [*#c*]),
    ..result.rows.flatten().map(v => [#v])
  )
]
