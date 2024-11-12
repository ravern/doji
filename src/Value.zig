const std = @import("std");
const Object = @import("Object.zig");

const Self = @This();

raw: u64,

const q_nan: u64 = 0x7ffc000000000000;

const tag_nil: usize = 0x0000000000000000;
const tag_true: usize = 0x0000000000000001;
const tag_false: usize = 0x0000000000000002;
const tag_int: usize = 0x0000000000000003;
const tag_object: usize = 0x8000000000000000;

pub const nil = Self{ .raw = q_nan | tag_nil };

pub fn initBool(b: bool) Self {
    return Self{ .raw = q_nan | (if (b) tag_true else tag_false) };
}

pub fn initInt(int: i48) Self {
    return Self{ .raw = @as(u64, q_nan | tag_int | @as(u64, @bitCast(@as(i64, @intCast(int)) << 2))) };
}

pub fn initFloat(float: f64) Self {
    return Self{ .raw = @bitCast(float) };
}

pub fn isInt(self: Self) bool {
    return !self.isFloat() and !self.isObject() and self.raw & tag_int == tag_int;
}

pub fn isFloat(self: Self) bool {
    return (self.raw & q_nan) != q_nan;
}

pub fn isObject(self: Self) bool {
    return !self.isFloat() and self.raw & tag_object == tag_object;
}

pub fn toInt(self: Self) ?i64 {
    if (!self.isInt()) return null;
    return @as(i64, @bitCast((self.raw ^ q_nan) >> 2));
}

pub fn toFloat(self: Self) ?f64 {
    if (!self.isFloat()) return null;
    return @bitCast(self.raw);
}

pub fn format(self: *const Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = fmt;
    _ = options;

    if (self.isInt()) {
        return writer.print("{d}", .{self.toInt().?});
    } else if (self.isFloat()) {
        return writer.print("{d}", .{self.toFloat().?});
    } else {
        unreachable;
    }
}
