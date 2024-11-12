const std = @import("std");
const bytecode = @import("bytecode.zig");
const Value = @import("Value.zig");

const Self = @This();

allocator: std.mem.Allocator,
stack: std.ArrayListUnmanaged(Value) = .{},

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.stack.deinit(self.allocator);
    self.* = undefined;
}

pub fn push(self: *Self, value: Value) !void {
    try self.stack.append(self.allocator, value);
}

pub fn pop(self: *Self) ?Value {
    return self.stack.popOrNull();
}

pub fn getLocal(self: *Self, slot: usize) Value {
    // FIXME: add check
    return self.stack.items[slot];
}
