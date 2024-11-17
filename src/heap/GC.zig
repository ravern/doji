const std = @import("std");

const Self = @This();

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
    };
}

pub fn create(self: *Self, comptime T: type) !*T {
    return try self.allocator.create(T);
}
