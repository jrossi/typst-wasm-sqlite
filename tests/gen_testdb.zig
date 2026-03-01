const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

fn exec(db: *c.sqlite3, sql: [*:0]const u8) void {
    var err_msg: [*c]u8 = null;
    const rc = c.sqlite3_exec(db, sql, null, null, &err_msg);
    if (rc != c.SQLITE_OK) {
        if (err_msg == null) {
            std.debug.print("SQL error: unknown error\n", .{});
            c.sqlite3_free(err_msg);
            std.process.exit(1);
        }
        const msg: [*:0]const u8 = @ptrCast(err_msg);
        std.debug.print("SQL error: {s}\n", .{msg});
        c.sqlite3_free(err_msg);
        std.process.exit(1);
    }
}

fn bindAndStep(db: *c.sqlite3, stmt: *c.sqlite3_stmt) void {
    const rc = c.sqlite3_step(stmt);
    if (rc != c.SQLITE_DONE) {
        const msg = c.sqlite3_errmsg(db);
        std.debug.print("Step error: {s}\n", .{std.mem.span(msg)});
        std.process.exit(1);
    }
    _ = c.sqlite3_reset(stmt);
}

fn prepare(db: *c.sqlite3, sql: [*:0]const u8) *c.sqlite3_stmt {
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK) {
        const msg = c.sqlite3_errmsg(db);
        std.debug.print("Prepare error: {s}\n", .{std.mem.span(msg)});
        std.process.exit(1);
    }
    return stmt.?;
}

pub fn main() !void {
    // Ensure test/ directory exists
    std.fs.cwd().makePath("test") catch {};

    var db: ?*c.sqlite3 = null;
    const rc = c.sqlite3_open("test/test.sqlite", &db);
    if (rc != c.SQLITE_OK) {
        std.debug.print("Cannot open database\n", .{});
        return error.DatabaseOpen;
    }
    defer _ = c.sqlite3_close(db);
    const d = db.?;

    // =========================================================================
    // cities — backward compat with existing test.typ
    // =========================================================================
    exec(d, "DROP TABLE IF EXISTS cities");
    exec(d,
        \\CREATE TABLE cities (
        \\  name TEXT NOT NULL,
        \\  country TEXT NOT NULL,
        \\  population INTEGER NOT NULL
        \\)
    );
    {
        const stmt = prepare(d, "INSERT INTO cities VALUES (?, ?, ?)");
        defer _ = c.sqlite3_finalize(stmt);

        const cities = [_]struct { name: [*:0]const u8, country: [*:0]const u8, pop: i64 }{
            .{ .name = "Tokyo", .country = "Japan", .pop = 13960000 },
            .{ .name = "Delhi", .country = "India", .pop = 11030000 },
            .{ .name = "Shanghai", .country = "China", .pop = 24870000 },
            .{ .name = "Sao Paulo", .country = "Brazil", .pop = 12330000 },
            .{ .name = "Mexico City", .country = "Mexico", .pop = 9210000 },
        };

        for (cities) |city| {
            _ = c.sqlite3_bind_text(stmt, 1, city.name, -1, null);
            _ = c.sqlite3_bind_text(stmt, 2, city.country, -1, null);
            _ = c.sqlite3_bind_int64(stmt, 3, city.pop);
            bindAndStep(d, stmt);
        }
    }

    // =========================================================================
    // types_test — INTEGER, REAL, TEXT, BLOB, NULL with edge values
    // =========================================================================
    exec(d, "DROP TABLE IF EXISTS types_test");
    exec(d,
        \\CREATE TABLE types_test (
        \\  id INTEGER PRIMARY KEY,
        \\  int_val INTEGER,
        \\  real_val REAL,
        \\  text_val TEXT,
        \\  blob_val BLOB
        \\)
    );
    {
        const stmt = prepare(d, "INSERT INTO types_test VALUES (?, ?, ?, ?, ?)");
        defer _ = c.sqlite3_finalize(stmt);

        // Row 1: normal values
        _ = c.sqlite3_bind_int64(stmt, 1, 1);
        _ = c.sqlite3_bind_int64(stmt, 2, 42);
        _ = c.sqlite3_bind_double(stmt, 3, 3.14);
        _ = c.sqlite3_bind_text(stmt, 4, "hello", -1, null);
        _ = c.sqlite3_bind_blob(stmt, 5, "binary", 6, null);
        bindAndStep(d, stmt);

        // Row 2: zeros
        _ = c.sqlite3_bind_int64(stmt, 1, 2);
        _ = c.sqlite3_bind_int64(stmt, 2, 0);
        _ = c.sqlite3_bind_double(stmt, 3, 0.0);
        _ = c.sqlite3_bind_text(stmt, 4, "", -1, null);
        _ = c.sqlite3_bind_blob(stmt, 5, "", 0, null);
        bindAndStep(d, stmt);

        // Row 3: large values
        _ = c.sqlite3_bind_int64(stmt, 1, 3);
        _ = c.sqlite3_bind_int64(stmt, 2, std.math.maxInt(i64));
        _ = c.sqlite3_bind_double(stmt, 3, 1.7976931348623157e+308);
        _ = c.sqlite3_bind_text(stmt, 4, "large text value", -1, null);
        _ = c.sqlite3_bind_null(stmt, 5);
        bindAndStep(d, stmt);

        // Row 4: negative values
        _ = c.sqlite3_bind_int64(stmt, 1, 4);
        _ = c.sqlite3_bind_int64(stmt, 2, std.math.minInt(i64));
        _ = c.sqlite3_bind_double(stmt, 3, -1.5);
        _ = c.sqlite3_bind_text(stmt, 4, "negative", -1, null);
        _ = c.sqlite3_bind_null(stmt, 5);
        bindAndStep(d, stmt);

        // Row 5: all NULLs (except id)
        _ = c.sqlite3_bind_int64(stmt, 1, 5);
        _ = c.sqlite3_bind_null(stmt, 2);
        _ = c.sqlite3_bind_null(stmt, 3);
        _ = c.sqlite3_bind_null(stmt, 4);
        _ = c.sqlite3_bind_null(stmt, 5);
        bindAndStep(d, stmt);
    }

    // =========================================================================
    // text_escaping — quotes, backslash, newline, tab, etc.
    // =========================================================================
    exec(d, "DROP TABLE IF EXISTS text_escaping");
    exec(d,
        \\CREATE TABLE text_escaping (
        \\  id INTEGER PRIMARY KEY,
        \\  label TEXT,
        \\  value TEXT
        \\)
    );
    {
        const stmt = prepare(d, "INSERT INTO text_escaping VALUES (?, ?, ?)");
        defer _ = c.sqlite3_finalize(stmt);

        const cases = [_]struct { id: i64, label: [*:0]const u8, value: [*:0]const u8 }{
            .{ .id = 1, .label = "double_quote", .value = "say \"hello\"" },
            .{ .id = 2, .label = "backslash", .value = "path\\to\\file" },
            .{ .id = 3, .label = "newline", .value = "line1\nline2" },
            .{ .id = 4, .label = "tab", .value = "col1\tcol2" },
            .{ .id = 5, .label = "carriage_return", .value = "before\rafter" },
            .{ .id = 6, .label = "unicode", .value = "caf\xc3\xa9" },
            .{ .id = 7, .label = "emoji", .value = "\xf0\x9f\x8e\x89" },
            .{ .id = 8, .label = "mixed", .value = "a\"b\\c\nd" },
            .{ .id = 9, .label = "empty", .value = "" },
            .{ .id = 10, .label = "plain", .value = "just plain text" },
        };

        for (cases) |case| {
            _ = c.sqlite3_bind_int64(stmt, 1, case.id);
            _ = c.sqlite3_bind_text(stmt, 2, case.label, -1, null);
            _ = c.sqlite3_bind_text(stmt, 3, case.value, -1, null);
            bindAndStep(d, stmt);
        }
    }

    // =========================================================================
    // numbers — edge numeric values
    // =========================================================================
    exec(d, "DROP TABLE IF EXISTS numbers");
    exec(d,
        \\CREATE TABLE numbers (
        \\  id INTEGER PRIMARY KEY,
        \\  label TEXT,
        \\  int_val INTEGER,
        \\  real_val REAL
        \\)
    );
    {
        const stmt = prepare(d, "INSERT INTO numbers VALUES (?, ?, ?, ?)");
        defer _ = c.sqlite3_finalize(stmt);

        // zero
        _ = c.sqlite3_bind_int64(stmt, 1, 1);
        _ = c.sqlite3_bind_text(stmt, 2, "zero", -1, null);
        _ = c.sqlite3_bind_int64(stmt, 3, 0);
        _ = c.sqlite3_bind_double(stmt, 4, 0.0);
        bindAndStep(d, stmt);

        // positive one
        _ = c.sqlite3_bind_int64(stmt, 1, 2);
        _ = c.sqlite3_bind_text(stmt, 2, "pos_one", -1, null);
        _ = c.sqlite3_bind_int64(stmt, 3, 1);
        _ = c.sqlite3_bind_double(stmt, 4, 1.0);
        bindAndStep(d, stmt);

        // negative one
        _ = c.sqlite3_bind_int64(stmt, 1, 3);
        _ = c.sqlite3_bind_text(stmt, 2, "neg_one", -1, null);
        _ = c.sqlite3_bind_int64(stmt, 3, -1);
        _ = c.sqlite3_bind_double(stmt, 4, -1.0);
        bindAndStep(d, stmt);

        // i64 max
        _ = c.sqlite3_bind_int64(stmt, 1, 4);
        _ = c.sqlite3_bind_text(stmt, 2, "i64_max", -1, null);
        _ = c.sqlite3_bind_int64(stmt, 3, std.math.maxInt(i64));
        _ = c.sqlite3_bind_double(stmt, 4, 1.7976931348623157e+308);
        bindAndStep(d, stmt);

        // i64 min
        _ = c.sqlite3_bind_int64(stmt, 1, 5);
        _ = c.sqlite3_bind_text(stmt, 2, "i64_min", -1, null);
        _ = c.sqlite3_bind_int64(stmt, 3, std.math.minInt(i64));
        _ = c.sqlite3_bind_double(stmt, 4, -1.7976931348623157e+308);
        bindAndStep(d, stmt);

        // small float
        _ = c.sqlite3_bind_int64(stmt, 1, 6);
        _ = c.sqlite3_bind_text(stmt, 2, "small_float", -1, null);
        _ = c.sqlite3_bind_null(stmt, 3);
        _ = c.sqlite3_bind_double(stmt, 4, 0.001);
        bindAndStep(d, stmt);

        // null numeric
        _ = c.sqlite3_bind_int64(stmt, 1, 7);
        _ = c.sqlite3_bind_text(stmt, 2, "null_num", -1, null);
        _ = c.sqlite3_bind_null(stmt, 3);
        _ = c.sqlite3_bind_null(stmt, 4);
        bindAndStep(d, stmt);
    }

    // =========================================================================
    // empty_table — schema only
    // =========================================================================
    exec(d, "DROP TABLE IF EXISTS empty_table");
    exec(d,
        \\CREATE TABLE empty_table (
        \\  id INTEGER PRIMARY KEY,
        \\  name TEXT,
        \\  value REAL
        \\)
    );

    // =========================================================================
    // wide_table — 50 columns
    // =========================================================================
    exec(d, "DROP TABLE IF EXISTS wide_table");
    {
        var create_buf: [4096]u8 = undefined;
        var pos: usize = 0;
        const prefix = "CREATE TABLE wide_table (";
        @memcpy(create_buf[pos..][0..prefix.len], prefix);
        pos += prefix.len;

        for (0..50) |col| {
            if (col > 0) {
                create_buf[pos] = ',';
                pos += 1;
            }
            const written = std.fmt.bufPrint(create_buf[pos..], "c{d} TEXT", .{col}) catch unreachable;
            pos += written.len;
        }
        create_buf[pos] = ')';
        pos += 1;
        create_buf[pos] = 0;
        pos += 1;
        exec(d, @ptrCast(create_buf[0..pos].ptr));

        // Insert one row
        var insert_buf: [4096]u8 = undefined;
        var ipos: usize = 0;
        const ins_prefix = "INSERT INTO wide_table VALUES (";
        @memcpy(insert_buf[ipos..][0..ins_prefix.len], ins_prefix);
        ipos += ins_prefix.len;
        for (0..50) |col| {
            if (col > 0) {
                insert_buf[ipos] = ',';
                ipos += 1;
            }
            const written = std.fmt.bufPrint(insert_buf[ipos..], "'val_{d}'", .{col}) catch unreachable;
            ipos += written.len;
        }
        insert_buf[ipos] = ')';
        ipos += 1;
        insert_buf[ipos] = 0;
        ipos += 1;
        exec(d, @ptrCast(insert_buf[0..ipos].ptr));
    }

    // =========================================================================
    // many_rows — 500 rows for volume testing
    // =========================================================================
    exec(d, "DROP TABLE IF EXISTS many_rows");
    exec(d,
        \\CREATE TABLE many_rows (
        \\  id INTEGER PRIMARY KEY,
        \\  value TEXT
        \\)
    );
    {
        const stmt = prepare(d, "INSERT INTO many_rows VALUES (?, ?)");
        defer _ = c.sqlite3_finalize(stmt);

        exec(d, "BEGIN TRANSACTION");
        for (1..501) |i| {
            _ = c.sqlite3_bind_int64(stmt, 1, @intCast(i));
            var label_buf: [32]u8 = undefined;
            const label = std.fmt.bufPrint(&label_buf, "row_{d}", .{i}) catch unreachable;
            _ = c.sqlite3_bind_text(stmt, 2, @ptrCast(label.ptr), @intCast(label.len), null);
            bindAndStep(d, stmt);
        }
        exec(d, "COMMIT");
    }

    // =========================================================================
    // single_col — minimal table
    // =========================================================================
    exec(d, "DROP TABLE IF EXISTS single_col");
    exec(d, "CREATE TABLE single_col (x INTEGER)");
    exec(d, "INSERT INTO single_col VALUES (1)");

    std.debug.print("Generated test/test.sqlite with 8 tables\n", .{});
}
