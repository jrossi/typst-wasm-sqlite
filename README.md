# typst-wasm-sqlite

A [Typst](https://typst.app) plugin that lets you query [SQLite](https://sqlite.org) databases at compile time. Write SQL in your `.typ` files and render the results as tables, charts, or however you like.

Built with Zig, compiled to WASM via Typst's [plugin protocol](https://typst.app/docs/reference/foundations/plugin/).

> This project was created with AI (Claude Code by Anthropic).

## Quick Start

```typst
#import "sqlite.typ": sqlite, sqlite-table

#let db = sqlite("data.sqlite")

// Query and render as a table
#sqlite-table((db.query)("SELECT name, population FROM cities ORDER BY population DESC"))

// Use raw query results however you want
#let result = (db.query)("SELECT count(*) as n FROM cities")
Total cities: #result.rows.at(0).at(0)
```

## API

### `sqlite(path)` — Open a database

Returns a database object with three methods:

| Method | Returns | Description |
|--------|---------|-------------|
| `query(sql)` | `{columns: [...], rows: [[...], ...]}` | Execute SQL, get results |
| `tables()` | `("table1", "table2", ...)` | List all table names |
| `schema(table)` | `{columns: [{name, type}, ...]}` | Get column info for a table |

### `sqlite-table(result, ..args)` — Render query results as a Typst table

Takes the output of `db.query()` and renders it. Extra arguments are passed through to Typst's `table()`.

```typst
#sqlite-table(
  (db.query)("SELECT * FROM cities"),
  fill: (x, y) => if y == 0 { gray.lighten(70%) },
)
```

### `query-table(db, sql)` — Query and get table-ready cells

Returns a flat array of cells (headers + data) for use with Typst's `table()` directly:

```typst
#table(
  columns: 3,
  ..query-table(db, "SELECT name, country, population FROM cities")
)
```

## How It Works

The plugin compiles SQLite into a ~150KB WASM module. When Typst compiles your document:

1. `sqlite.typ` reads the database file as raw bytes via Typst's `read()`
2. The bytes are passed to the WASM plugin which opens them as an in-memory SQLite database (custom read-only VFS)
3. SQL queries execute against the in-memory database
4. Results come back as JSON, which Typst's `json()` parses into native types

All processing happens at compile time. No network, no filesystem access from WASM — just bytes in, JSON out.

## Building

### Prerequisites

- [Zig](https://ziglang.org) 0.15.2
- [Typst](https://typst.app) 0.14.2

Or use [mise](https://mise.jdx.dev) which handles both:

```bash
mise install
```

### Build

```bash
zig build -Doptimize=ReleaseSmall    # or: mise run build
```

This produces `zig-out/bin/typst_sqlite_zig.wasm`.

### Run the Example

```bash
typst compile example.typ example.pdf
```

### Run the Demo

The demo showcases JOINs, CTEs, window functions, self-joins, subqueries, and more:

```bash
mise run demo
```

## Testing

```bash
mise run test          # Run everything (unit + integration)
mise run test-unit     # Zig unit tests only (~35 tests for JSON serializer)
mise run test-integration  # Build plugin + compile Typst test assertions
```

Git hooks run tests automatically:
- **pre-commit**: unit tests
- **pre-push**: full test suite

## Project Structure

```
src/
  main.zig          # WASM plugin: VFS, query engine, Typst protocol
  json.zig          # JSON serializer (fixed-buffer, no allocator)
sqlite.typ          # Typst API wrapper
example.typ         # Simple usage example
demo.typ            # Complex SQL showcase
test.typ            # Test runner
test/
  test_plugin.typ   # Low-level plugin assertions
  test_api.typ      # sqlite.typ wrapper assertions
tests/
  test_json.zig     # Unit tests for JSON serializer
  gen_testdb.zig    # Generates test database (8 tables)
  gen_demodb.zig    # Generates demo database (5 relational tables)
sqlite3.c/h         # SQLite amalgamation (vendored)
libc-stubs/         # Minimal libc for WASM freestanding target
build.zig           # Zig build config
mise.toml           # Tool versions + task runner
```

## SQL Support

Full SQLite SQL support including:

- SELECT, WHERE, ORDER BY, LIMIT, OFFSET, LIKE
- JOIN (INNER, LEFT, self-joins)
- GROUP BY, HAVING, DISTINCT
- Aggregate functions (COUNT, SUM, AVG, MIN, MAX, GROUP_CONCAT)
- Window functions (RANK, SUM OVER, running totals)
- CTEs (WITH ... AS)
- Subqueries (correlated and uncorrelated)
- CASE expressions
- Date functions (julianday, substr)
- UNION, INTERSECT, EXCEPT

## License

SQLite is in the [public domain](https://sqlite.org/copyright.html). The rest of this project is provided as-is.
