#let plugin = plugin("zig-out/bin/typst_sqlite_zig.wasm")

= Zig SQLite Plugin Test

== Hello
#str(plugin.hello())

== Load Database
#let db = read("test.sqlite", encoding: none)
DB size: #db.len() bytes

== List Tables
#let tables_json = str(plugin.tables(db))
Tables: #tables_json

== Query Data
#let result_json = str(plugin.query(db, bytes("SELECT name, country, population FROM cities ORDER BY population DESC LIMIT 10")))

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
