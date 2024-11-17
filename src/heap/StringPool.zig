const std = @import("std");
const heap = @import("../heap.zig");

const Self = @This();

allocator: std.mem.Allocator,
gc: *heap.GC,
strings: std.StringHashMap(*heap.String),

pub fn init(allocator: std.mem.Allocator, gc: *heap.GC) Self {
    return .{
        .allocator = allocator,
        .gc = gc,
        .strings = std.StringHashMap(*heap.String).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.strings.deinit();
}

pub fn intern(self: *Self, str: []const u8) !*heap.String {
    if (self.strings.get(str)) |string| {
        return string;
    }

    const string = try self.gc.create(heap.String);
    string.* = heap.String.init(try self.allocator.dupe(u8, str));
    try self.strings.put(str, string);

    return string;
}
