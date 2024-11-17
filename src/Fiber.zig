const std = @import("std");
const bytecode = @import("bytecode.zig");
const Value = @import("Value.zig");

const Self = @This();

pub const CallFrame = struct {
    chunk: bytecode.Chunk, // TODO: should be replaced by closure (which contains the chunk)
    ip: usize,
    bp: usize, // TODO: can we use a pointer instead?
};

stack: std.ArrayList(Value),
call_frames: std.ArrayList(CallFrame),

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .stack = std.ArrayList(Value).init(allocator),
        .call_frames = std.ArrayList(CallFrame).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.stack.deinit();
    self.call_frames.deinit();
    self.* = undefined;
}
