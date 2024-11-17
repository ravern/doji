const std = @import("std");

const Self = @This();

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{ .allocator = allocator };
}

pub fn internString(self: *Self, string: []const u8) ![]const u8 {
    return try self.allocator.dupe(u8, string);
}
