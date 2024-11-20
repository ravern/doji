const std = @import("std");
const gc = @import("gc.zig");

pub const Value = struct {
    raw: u64,
};

pub const List = struct {
    values: std.ArrayListUnmanaged(Value) = .{},

    pub fn deinit(self: *List, allocator: std.mem.Allocator) void {
        self.values.deinit(allocator);
        self.* = undefined;
    }
};
