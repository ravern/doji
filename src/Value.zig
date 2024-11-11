const std = @import("std");

const Self = @This();

raw: usize,

pub fn initInt(int: i64) Self {
    return Self{ .raw = @intCast(int) };
}

pub fn toInt(self: Self) ?i64 {
    return @intCast(self.raw);
}

pub fn format(self: *const Self, comptime fmt: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    if (fmt.len != 0) {
        std.fmt.invalidFmtError(fmt, self);
    }
    return writer.print("{d}", .{@as(i64, @intCast(self.raw))});
}
