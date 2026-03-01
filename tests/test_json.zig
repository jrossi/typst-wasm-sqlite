const std = @import("std");
const testing = std.testing;
const JsonWriter = @import("json").JsonWriter;

// =============================================================================
// write / writeChar basics
// =============================================================================

test "write appends data" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.write("hello");
    try testing.expectEqualStrings("hello", jw.getResult().?);
}

test "write concatenation" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.write("foo");
    jw.write("bar");
    try testing.expectEqualStrings("foobar", jw.getResult().?);
}

test "writeChar appends single byte" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeChar('A');
    jw.writeChar('B');
    try testing.expectEqualStrings("AB", jw.getResult().?);
}

// =============================================================================
// overflow detection
// =============================================================================

test "exact fit does not overflow" {
    var buf: [5]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.write("hello");
    try testing.expect(!jw.overflow);
    try testing.expectEqualStrings("hello", jw.getResult().?);
}

test "one byte over triggers overflow" {
    var buf: [5]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.write("hello!");
    try testing.expect(jw.overflow);
    try testing.expect(jw.getResult() == null);
}

test "zero-length buffer overflows on any write" {
    var buf: [0]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeChar('x');
    try testing.expect(jw.overflow);
    try testing.expect(jw.getResult() == null);
}

test "overflow persists after being set" {
    var buf: [3]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.write("abcd"); // overflow
    try testing.expect(jw.overflow);
    jw.write("x"); // further writes are no-ops
    try testing.expect(jw.overflow);
    try testing.expect(jw.getResult() == null);
}

test "writeChar overflow on full buffer" {
    var buf: [2]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeChar('a');
    jw.writeChar('b');
    try testing.expect(!jw.overflow);
    jw.writeChar('c');
    try testing.expect(jw.overflow);
}

// =============================================================================
// writeEscaped
// =============================================================================

test "writeEscaped double quote" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeEscaped("say \"hi\"");
    try testing.expectEqualStrings("say \\\"hi\\\"", jw.getResult().?);
}

test "writeEscaped backslash" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeEscaped("a\\b");
    try testing.expectEqualStrings("a\\\\b", jw.getResult().?);
}

test "writeEscaped newline" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeEscaped("line1\nline2");
    try testing.expectEqualStrings("line1\\nline2", jw.getResult().?);
}

test "writeEscaped carriage return" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeEscaped("a\rb");
    try testing.expectEqualStrings("a\\rb", jw.getResult().?);
}

test "writeEscaped tab" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeEscaped("a\tb");
    try testing.expectEqualStrings("a\\tb", jw.getResult().?);
}

test "writeEscaped control chars" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeEscaped(&[_]u8{0x01});
    try testing.expectEqualStrings("\\u0001", jw.getResult().?);
}

test "writeEscaped null byte" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeEscaped(&[_]u8{0x00});
    try testing.expectEqualStrings("\\u0000", jw.getResult().?);
}

test "writeEscaped empty string" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeEscaped("");
    try testing.expectEqualStrings("", jw.getResult().?);
}

test "writeEscaped UTF-8 passthrough" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeEscaped("café");
    try testing.expectEqualStrings("café", jw.getResult().?);
}

test "writeEscaped mixed special chars" {
    var buf: [128]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeEscaped("line1\nline2\t\"quoted\"\\end");
    try testing.expectEqualStrings("line1\\nline2\\t\\\"quoted\\\"\\\\end", jw.getResult().?);
}

// =============================================================================
// writeInt
// =============================================================================

test "writeInt zero" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeInt(0);
    try testing.expectEqualStrings("0", jw.getResult().?);
}

test "writeInt positive 1" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeInt(1);
    try testing.expectEqualStrings("1", jw.getResult().?);
}

test "writeInt negative 1" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeInt(-1);
    try testing.expectEqualStrings("-1", jw.getResult().?);
}

test "writeInt 42" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeInt(42);
    try testing.expectEqualStrings("42", jw.getResult().?);
}

test "writeInt large number" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeInt(1234567890);
    try testing.expectEqualStrings("1234567890", jw.getResult().?);
}

test "writeInt i64 max" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeInt(std.math.maxInt(i64));
    try testing.expectEqualStrings("9223372036854775807", jw.getResult().?);
}

test "writeInt i64 min" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeInt(std.math.minInt(i64));
    try testing.expectEqualStrings("-9223372036854775808", jw.getResult().?);
}

// =============================================================================
// writeFloat
// =============================================================================

test "writeFloat fractional" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeFloat(3.14);
    const result = jw.getResult().?;
    // Should start with "3.14"
    try testing.expect(std.mem.startsWith(u8, result, "3.14"));
}

test "writeFloat negative" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeFloat(-2.5);
    try testing.expectEqualStrings("-2.5", jw.getResult().?);
}

test "writeFloat NaN becomes null" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeFloat(std.math.nan(f64));
    try testing.expectEqualStrings("null", jw.getResult().?);
}

test "writeFloat positive Inf becomes null" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeFloat(std.math.inf(f64));
    try testing.expectEqualStrings("null", jw.getResult().?);
}

test "writeFloat negative Inf becomes null" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeFloat(-std.math.inf(f64));
    try testing.expectEqualStrings("null", jw.getResult().?);
}

test "writeFloat zero" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeFloat(0.0);
    const result = jw.getResult().?;
    // Should represent zero somehow
    try testing.expect(result.len > 0);
    // Parse it back to verify it's 0
    const parsed = try std.fmt.parseFloat(f64, result);
    try testing.expectEqual(@as(f64, 0.0), parsed);
}

test "writeFloat small value" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeFloat(0.001);
    const result = jw.getResult().?;
    try testing.expect(result.len > 0);
}

test "writeFloat large value" {
    var buf: [64]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeFloat(1.0e15);
    const result = jw.getResult().?;
    try testing.expect(result.len > 0);
}

// =============================================================================
// composite JSON structures
// =============================================================================

test "build JSON object" {
    var buf: [256]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.write("{\"name\":\"");
    jw.writeEscaped("Alice");
    jw.write("\",\"age\":");
    jw.writeInt(30);
    jw.writeChar('}');
    try testing.expectEqualStrings("{\"name\":\"Alice\",\"age\":30}", jw.getResult().?);
}

test "build JSON array" {
    var buf: [256]u8 = undefined;
    var jw = JsonWriter.init(&buf);
    jw.writeChar('[');
    jw.writeInt(1);
    jw.writeChar(',');
    jw.writeInt(2);
    jw.writeChar(',');
    jw.writeInt(3);
    jw.writeChar(']');
    try testing.expectEqualStrings("[1,2,3]", jw.getResult().?);
}
