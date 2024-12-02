const std = @import("std");
const GC = @import("gc.zig").GC;

pub const String = union(enum) {
    small: [16]u8,
    intern: []const u8,
    gc: []const u8,
};
