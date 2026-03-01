const std = @import("std");

pub const JsonWriter = struct {
    buf: []u8,
    pos: usize,
    overflow: bool,

    pub fn init(buffer: []u8) JsonWriter {
        return .{ .buf = buffer, .pos = 0, .overflow = false };
    }

    pub fn write(self: *JsonWriter, data: []const u8) void {
        if (self.overflow) return;
        const remaining = self.buf.len - self.pos;
        if (data.len > remaining) {
            self.overflow = true;
            return;
        }
        @memcpy(self.buf[self.pos..][0..data.len], data);
        self.pos += data.len;
    }

    pub fn writeChar(self: *JsonWriter, c: u8) void {
        if (self.overflow) return;
        if (self.pos >= self.buf.len) {
            self.overflow = true;
            return;
        }
        self.buf[self.pos] = c;
        self.pos += 1;
    }

    pub fn writeEscaped(self: *JsonWriter, s: []const u8) void {
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

    pub fn writeInt(self: *JsonWriter, value: i64) void {
        var buf: [21]u8 = undefined;
        const neg = value < 0;
        var v: u64 = @abs(value);
        var i: usize = buf.len;
        if (v == 0) {
            i -= 1;
            buf[i] = '0';
        } else {
            while (v > 0) {
                i -= 1;
                buf[i] = @intCast(v % 10 + '0');
                v = v / 10;
            }
        }
        if (neg) {
            i -= 1;
            buf[i] = '-';
        }
        self.write(buf[i..]);
    }

    pub fn writeFloat(self: *JsonWriter, value: f64) void {
        if (std.math.isNan(value) or std.math.isInf(value)) {
            self.write("null");
            return;
        }
        var buf: [32]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, "{d}", .{value}) catch {
            self.write("0");
            return;
        };
        self.write(result);
    }

    pub fn getResult(self: *JsonWriter) ?[]const u8 {
        if (self.overflow) return null;
        return self.buf[0..self.pos];
    }
};
