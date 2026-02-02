const std = @import("std");
const sqlite = @cImport({
    @cInclude("sqlite3.h");
});

// =============================================================================
// Typst Plugin Protocol
// =============================================================================

extern fn wasm_minimal_protocol_write_args_to_buffer(ptr: [*]u8) void;
extern fn wasm_minimal_protocol_send_result_to_host(ptr: [*]const u8, len: usize) void;

fn sendResult(data: []const u8) void {
    wasm_minimal_protocol_send_result_to_host(data.ptr, data.len);
}

fn sendError(msg: []const u8) void {
    var buf: [512]u8 = undefined;
    const result = std.fmt.bufPrint(&buf, "{{\"error\": \"{s}\"}}", .{msg}) catch {
        sendResult("{\"error\": \"format error\"}");
        return;
    };
    sendResult(result);
}

// =============================================================================
// Memory Allocator for WASM
// =============================================================================

var heap: [16 * 1024 * 1024]u8 = undefined; // 16MB heap
var heap_offset: usize = 0;

fn wasmAlloc(size: usize) ?[*]u8 {
    const aligned_size = (size + 7) & ~@as(usize, 7);
    if (heap_offset + aligned_size > heap.len) return null;
    const ptr = heap[heap_offset..].ptr;
    heap_offset += aligned_size;
    return ptr;
}

fn resetHeap() void {
    heap_offset = 0;
}

// =============================================================================
// SQLite Memory VFS (In-Memory Only)
// =============================================================================

const MemFile = struct {
    base: sqlite.sqlite3_file,
    data: [*]const u8,
    size: usize,
    pos: usize,
};

fn memClose(file: *sqlite.sqlite3_file) callconv(.C) c_int {
    _ = file;
    return sqlite.SQLITE_OK;
}

fn memRead(file: *sqlite.sqlite3_file, buf: ?*anyopaque, amt: c_int, offset: sqlite.sqlite3_int64) callconv(.C) c_int {
    const f: *MemFile = @ptrCast(@alignCast(file));
    const off: usize = @intCast(offset);
    const amount: usize = @intCast(amt);

    if (off >= f.size) {
        const dest: [*]u8 = @ptrCast(buf);
        @memset(dest[0..amount], 0);
        return sqlite.SQLITE_IOERR_SHORT_READ;
    }

    const available = f.size - off;
    const to_read = @min(amount, available);
    const dest: [*]u8 = @ptrCast(buf);
    @memcpy(dest[0..to_read], f.data[off..][0..to_read]);

    if (to_read < amount) {
        @memset(dest[to_read..amount], 0);
        return sqlite.SQLITE_IOERR_SHORT_READ;
    }

    return sqlite.SQLITE_OK;
}

fn memWrite(_: *sqlite.sqlite3_file, _: ?*const anyopaque, _: c_int, _: sqlite.sqlite3_int64) callconv(.C) c_int {
    return sqlite.SQLITE_READONLY;
}

fn memTruncate(_: *sqlite.sqlite3_file, _: sqlite.sqlite3_int64) callconv(.C) c_int {
    return sqlite.SQLITE_READONLY;
}

fn memSync(_: *sqlite.sqlite3_file, _: c_int) callconv(.C) c_int {
    return sqlite.SQLITE_OK;
}

fn memFileSize(file: *sqlite.sqlite3_file, size: *sqlite.sqlite3_int64) callconv(.C) c_int {
    const f: *MemFile = @ptrCast(@alignCast(file));
    size.* = @intCast(f.size);
    return sqlite.SQLITE_OK;
}

fn memLock(_: *sqlite.sqlite3_file, _: c_int) callconv(.C) c_int {
    return sqlite.SQLITE_OK;
}

fn memUnlock(_: *sqlite.sqlite3_file, _: c_int) callconv(.C) c_int {
    return sqlite.SQLITE_OK;
}

fn memCheckReservedLock(_: *sqlite.sqlite3_file, out: *c_int) callconv(.C) c_int {
    out.* = 0;
    return sqlite.SQLITE_OK;
}

fn memFileControl(_: *sqlite.sqlite3_file, _: c_int, _: ?*anyopaque) callconv(.C) c_int {
    return sqlite.SQLITE_NOTFOUND;
}

fn memSectorSize(_: *sqlite.sqlite3_file) callconv(.C) c_int {
    return 4096;
}

fn memDeviceCharacteristics(_: *sqlite.sqlite3_file) callconv(.C) c_int {
    return sqlite.SQLITE_IOCAP_IMMUTABLE;
}

const mem_io_methods = sqlite.sqlite3_io_methods{
    .iVersion = 1,
    .xClose = memClose,
    .xRead = memRead,
    .xWrite = memWrite,
    .xTruncate = memTruncate,
    .xSync = memSync,
    .xFileSize = memFileSize,
    .xLock = memLock,
    .xUnlock = memUnlock,
    .xCheckReservedLock = memCheckReservedLock,
    .xFileControl = memFileControl,
    .xSectorSize = memSectorSize,
    .xDeviceCharacteristics = memDeviceCharacteristics,
    .xShmMap = null,
    .xShmLock = null,
    .xShmBarrier = null,
    .xShmUnmap = null,
    .xFetch = null,
    .xUnfetch = null,
};

// Thread-local storage for database bytes (set before opening)
var current_db_data: [*]const u8 = undefined;
var current_db_size: usize = 0;

fn vfsOpen(_: *sqlite.sqlite3_vfs, _: [*c]const u8, file: *sqlite.sqlite3_file, _: c_int, _: *c_int) callconv(.C) c_int {
    const f: *MemFile = @ptrCast(@alignCast(file));
    f.base.pMethods = &mem_io_methods;
    f.data = current_db_data;
    f.size = current_db_size;
    f.pos = 0;
    return sqlite.SQLITE_OK;
}

fn vfsDelete(_: *sqlite.sqlite3_vfs, _: [*c]const u8, _: c_int) callconv(.C) c_int {
    return sqlite.SQLITE_READONLY;
}

fn vfsAccess(_: *sqlite.sqlite3_vfs, _: [*c]const u8, _: c_int, out: *c_int) callconv(.C) c_int {
    out.* = 1;
    return sqlite.SQLITE_OK;
}

fn vfsFullPathname(_: *sqlite.sqlite3_vfs, name: [*c]const u8, n: c_int, out: [*c]u8) callconv(.C) c_int {
    const len = std.mem.len(name);
    const copy_len = @min(len, @as(usize, @intCast(n - 1)));
    @memcpy(out[0..copy_len], name[0..copy_len]);
    out[copy_len] = 0;
    return sqlite.SQLITE_OK;
}

fn vfsRandomness(_: *sqlite.sqlite3_vfs, n: c_int, out: [*c]u8) callconv(.C) c_int {
    @memset(out[0..@intCast(n)], 0);
    return n;
}

fn vfsSleep(_: *sqlite.sqlite3_vfs, _: c_int) callconv(.C) c_int {
    return sqlite.SQLITE_OK;
}

fn vfsCurrentTime(_: *sqlite.sqlite3_vfs, out: *f64) callconv(.C) c_int {
    out.* = 2440587.5; // Unix epoch as Julian day
    return sqlite.SQLITE_OK;
}

fn vfsGetLastError(_: *sqlite.sqlite3_vfs, _: c_int, _: [*c]u8) callconv(.C) c_int {
    return 0;
}

var mem_vfs = sqlite.sqlite3_vfs{
    .iVersion = 1,
    .szOsFile = @sizeOf(MemFile),
    .mxPathname = 256,
    .pNext = null,
    .zName = "mem",
    .pAppData = null,
    .xOpen = vfsOpen,
    .xDelete = vfsDelete,
    .xAccess = vfsAccess,
    .xFullPathname = vfsFullPathname,
    .xDlOpen = null,
    .xDlError = null,
    .xDlSym = null,
    .xDlClose = null,
    .xRandomness = vfsRandomness,
    .xSleep = vfsSleep,
    .xCurrentTime = vfsCurrentTime,
    .xGetLastError = vfsGetLastError,
    .xCurrentTimeInt64 = null,
    .xSetSystemCall = null,
    .xGetSystemCall = null,
    .xNextSystemCall = null,
};

var vfs_registered = false;

fn initVfs() void {
    if (!vfs_registered) {
        _ = sqlite.sqlite3_vfs_register(&mem_vfs, 0);
        vfs_registered = true;
    }
}

// =============================================================================
// SQLite Helpers
// =============================================================================

fn openDatabase(db_bytes: []const u8) ?*sqlite.sqlite3 {
    initVfs();

    current_db_data = db_bytes.ptr;
    current_db_size = db_bytes.len;

    var db: ?*sqlite.sqlite3 = null;
    const rc = sqlite.sqlite3_open_v2(
        "memory.db",
        &db,
        sqlite.SQLITE_OPEN_READONLY,
        "mem",
    );

    if (rc != sqlite.SQLITE_OK) {
        if (db != null) sqlite.sqlite3_close(db);
        return null;
    }

    return db;
}

// =============================================================================
// JSON Output Helpers
// =============================================================================

const JsonWriter = struct {
    buf: []u8,
    pos: usize,

    fn init(buffer: []u8) JsonWriter {
        return .{ .buf = buffer, .pos = 0 };
    }

    fn write(self: *JsonWriter, data: []const u8) void {
        const remaining = self.buf.len - self.pos;
        const to_write = @min(data.len, remaining);
        @memcpy(self.buf[self.pos..][0..to_write], data[0..to_write]);
        self.pos += to_write;
    }

    fn writeChar(self: *JsonWriter, c: u8) void {
        if (self.pos < self.buf.len) {
            self.buf[self.pos] = c;
            self.pos += 1;
        }
    }

    fn writeEscaped(self: *JsonWriter, s: []const u8) void {
        for (s) |c| {
            switch (c) {
                '"' => self.write("\\\""),
                '\\' => self.write("\\\\"),
                '\n' => self.write("\\n"),
                '\r' => self.write("\\r"),
                '\t' => self.write("\\t"),
                else => {
                    if (c < 32) {
                        self.write("\\u00");
                        const hex = "0123456789abcdef";
                        self.writeChar(hex[c >> 4]);
                        self.writeChar(hex[c & 0xf]);
                    } else {
                        self.writeChar(c);
                    }
                },
            }
        }
    }

    fn writeInt(self: *JsonWriter, value: i64) void {
        var buf: [21]u8 = undefined;
        var v = value;
        var neg = false;
        if (v < 0) {
            neg = true;
            v = -v;
        }
        var i: usize = buf.len;
        if (v == 0) {
            i -= 1;
            buf[i] = '0';
        } else {
            while (v > 0) {
                i -= 1;
                buf[i] = @intCast((v % 10) + '0');
                v = @divTrunc(v, 10);
            }
        }
        if (neg) {
            i -= 1;
            buf[i] = '-';
        }
        self.write(buf[i..]);
    }

    fn writeFloat(self: *JsonWriter, value: f64) void {
        // Simple float formatting
        var buf: [32]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch {
            self.write("0");
            return;
        };
        self.write(result);
    }

    fn getResult(self: *JsonWriter) []const u8 {
        return self.buf[0..self.pos];
    }
};

// =============================================================================
// Exported Plugin Functions
// =============================================================================

export fn hello() i32 {
    const msg = "Hello from typst-sqlite-zig!";
    sendResult(msg);
    return 0;
}

export fn query(db_len: i32, sql_len: i32) i32 {
    resetHeap();

    const total: usize = @intCast(db_len + sql_len);
    const buf = wasmAlloc(total) orelse {
        sendError("out of memory");
        return 1;
    };
    wasm_minimal_protocol_write_args_to_buffer(buf);

    const db_bytes = buf[0..@intCast(db_len)];
    const sql_bytes = buf[@intCast(db_len)..][0..@intCast(sql_len)];

    const db = openDatabase(db_bytes) orelse {
        sendError("failed to open database");
        return 1;
    };
    defer _ = sqlite.sqlite3_close(db);

    var stmt: ?*sqlite.sqlite3_stmt = null;
    const rc = sqlite.sqlite3_prepare_v2(db, sql_bytes.ptr, @intCast(sql_bytes.len), &stmt, null);
    if (rc != sqlite.SQLITE_OK) {
        const err = sqlite.sqlite3_errmsg(db);
        if (err != null) {
            sendError(std.mem.span(err));
        } else {
            sendError("prepare failed");
        }
        return 1;
    }
    defer _ = sqlite.sqlite3_finalize(stmt);

    // Allocate output buffer
    const out_buf = wasmAlloc(1024 * 1024) orelse { // 1MB output buffer
        sendError("out of memory for output");
        return 1;
    };
    var json = JsonWriter.init(out_buf[0 .. 1024 * 1024]);

    json.write("{\"columns\":[");

    const col_count = sqlite.sqlite3_column_count(stmt);
    var i: c_int = 0;
    while (i < col_count) : (i += 1) {
        if (i > 0) json.writeChar(',');
        json.writeChar('"');
        const name = sqlite.sqlite3_column_name(stmt, i);
        if (name != null) {
            json.writeEscaped(std.mem.span(name));
        }
        json.writeChar('"');
    }

    json.write("],\"rows\":[");

    var first_row = true;
    while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
        if (!first_row) json.writeChar(',');
        first_row = false;

        json.writeChar('[');
        var j: c_int = 0;
        while (j < col_count) : (j += 1) {
            if (j > 0) json.writeChar(',');

            const col_type = sqlite.sqlite3_column_type(stmt, j);
            switch (col_type) {
                sqlite.SQLITE_NULL => json.write("null"),
                sqlite.SQLITE_INTEGER => {
                    const val = sqlite.sqlite3_column_int64(stmt, j);
                    json.writeInt(val);
                },
                sqlite.SQLITE_FLOAT => {
                    const val = sqlite.sqlite3_column_double(stmt, j);
                    json.writeFloat(val);
                },
                sqlite.SQLITE_TEXT => {
                    json.writeChar('"');
                    const text = sqlite.sqlite3_column_text(stmt, j);
                    const len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt, j));
                    if (text != null) {
                        json.writeEscaped(text[0..len]);
                    }
                    json.writeChar('"');
                },
                sqlite.SQLITE_BLOB => {
                    // Encode blob as hex string
                    json.write("\"<blob>\"");
                },
                else => json.write("null"),
            }
        }
        json.writeChar(']');
    }

    json.write("]}");

    sendResult(json.getResult());
    return 0;
}

export fn tables(db_len: i32) i32 {
    resetHeap();

    const buf = wasmAlloc(@intCast(db_len)) orelse {
        sendError("out of memory");
        return 1;
    };
    wasm_minimal_protocol_write_args_to_buffer(buf);

    const db_bytes = buf[0..@intCast(db_len)];

    const db = openDatabase(db_bytes) orelse {
        sendError("failed to open database");
        return 1;
    };
    defer _ = sqlite.sqlite3_close(db);

    const sql = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name";
    var stmt: ?*sqlite.sqlite3_stmt = null;
    const rc = sqlite.sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != sqlite.SQLITE_OK) {
        sendError("failed to query tables");
        return 1;
    }
    defer _ = sqlite.sqlite3_finalize(stmt);

    const out_buf = wasmAlloc(64 * 1024) orelse {
        sendError("out of memory for output");
        return 1;
    };
    var json = JsonWriter.init(out_buf[0 .. 64 * 1024]);

    json.writeChar('[');
    var first = true;
    while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
        if (!first) json.writeChar(',');
        first = false;

        json.writeChar('"');
        const name = sqlite.sqlite3_column_text(stmt, 0);
        const len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt, 0));
        if (name != null) {
            json.writeEscaped(name[0..len]);
        }
        json.writeChar('"');
    }
    json.writeChar(']');

    sendResult(json.getResult());
    return 0;
}

export fn schema(db_len: i32, table_len: i32) i32 {
    resetHeap();

    const total: usize = @intCast(db_len + table_len);
    const buf = wasmAlloc(total) orelse {
        sendError("out of memory");
        return 1;
    };
    wasm_minimal_protocol_write_args_to_buffer(buf);

    const db_bytes = buf[0..@intCast(db_len)];
    const table_name = buf[@intCast(db_len)..][0..@intCast(table_len)];

    const db = openDatabase(db_bytes) orelse {
        sendError("failed to open database");
        return 1;
    };
    defer _ = sqlite.sqlite3_close(db);

    // Build PRAGMA query
    var pragma_buf: [256]u8 = undefined;
    const pragma = std.fmt.bufPrint(&pragma_buf, "PRAGMA table_info({s})", .{table_name}) catch {
        sendError("table name too long");
        return 1;
    };

    var stmt: ?*sqlite.sqlite3_stmt = null;
    const rc = sqlite.sqlite3_prepare_v2(db, pragma.ptr, @intCast(pragma.len), &stmt, null);
    if (rc != sqlite.SQLITE_OK) {
        sendError("failed to query schema");
        return 1;
    }
    defer _ = sqlite.sqlite3_finalize(stmt);

    const out_buf = wasmAlloc(64 * 1024) orelse {
        sendError("out of memory for output");
        return 1;
    };
    var json = JsonWriter.init(out_buf[0 .. 64 * 1024]);

    json.write("{\"columns\":[");

    var first = true;
    while (sqlite.sqlite3_step(stmt) == sqlite.SQLITE_ROW) {
        if (!first) json.writeChar(',');
        first = false;

        json.write("{\"name\":\"");
        const name = sqlite.sqlite3_column_text(stmt, 1);
        const name_len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt, 1));
        if (name != null) {
            json.writeEscaped(name[0..name_len]);
        }
        json.write("\",\"type\":\"");
        const typ = sqlite.sqlite3_column_text(stmt, 2);
        const typ_len: usize = @intCast(sqlite.sqlite3_column_bytes(stmt, 2));
        if (typ != null) {
            json.writeEscaped(typ[0..typ_len]);
        }
        json.write("\"}");
    }

    json.write("]}");

    sendResult(json.getResult());
    return 0;
}
