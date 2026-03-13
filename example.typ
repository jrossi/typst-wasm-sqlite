// Example usage of the SQLite plugin for Typst

#import "sqlite.typ": sqlite, sqlite-table

= City Population Data

#let db = sqlite(read("test.sqlite", encoding: none))

== All Cities
#sqlite-table((db.query)("SELECT * FROM cities"))

== Top 3 by Population (ORDER BY + LIMIT)
#sqlite-table(
  (db.query)("SELECT name, country, population FROM cities ORDER BY population DESC LIMIT 3"),
  fill: (x, y) => if y == 0 { gray.lighten(70%) },
)

== Cities with Population > 25 Million (WHERE)
#sqlite-table((db.query)("SELECT name, population FROM cities WHERE population > 25000000"))

== Asian Cities (WHERE with text)
#sqlite-table((db.query)("SELECT * FROM cities WHERE country = 'Japan' OR country = 'India' OR country = 'China'"))

== Cities Starting with 'S' (LIKE)
#sqlite-table((db.query)("SELECT name, country FROM cities WHERE name LIKE 'S%'"))

== Skip First 2, Take Next 2 (OFFSET)
#sqlite-table((db.query)("SELECT name FROM cities ORDER BY name LIMIT 2 OFFSET 2"))

== Database Info

Tables: #(db.tables)().join(", ")

#let schema = (db.schema)("cities")
Columns: #schema.columns.map(c => c.name + " (" + c.type + ")").join(", ")
