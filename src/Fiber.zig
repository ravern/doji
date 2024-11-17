const std = @import("std");
const bytecode = @import("bytecode.zig");
const Value = @import("Value.zig");

const Self = @This();

pub const CallFrame = struct {
    chunk: *bytecode.Chunk, // TODO: should be replaced by closure (which contains the chunk)
    ip: usize,
    bp: usize, // TODO: can we use a pointer instead?
};

allocator: std.mem.Allocator,
stack: std.ArrayListUnmanaged(Value) = .{},
frames: std.ArrayListUnmanaged(CallFrame) = .{},

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.stack.deinit(self.allocator);
    self.frames.deinit(self.allocator);
    self.* = undefined;
}

pub fn push(self: *Self, value: Value) !void {
    try self.stack.append(self.allocator, value);
}

pub fn pop(self: *Self) !Value {
    return self.stack.popOrNull() orelse return error.BytecodeCorrupted;
}

pub fn pushFrame(self: *Self, chunk: *bytecode.Chunk, arity: usize) !void {
    const frame = CallFrame{
        .chunk = chunk,
        .ip = 0,
        .bp = self.stack.items.len - arity,
    };
    try self.frames.append(self.allocator, frame);
}

pub fn popFrame(self: *Self) !void {
    _ = self.frames.popOrNull() orelse return error.BytecodeCorrupted;
}

pub fn getLocal(self: *Self, slot: usize) !Value {
    const frame = self.frames.getLastOrNull() orelse return error.BytecodeCorrupted;
    return self.stack.items[frame.bp + slot];
}

pub fn step(self: *Self) !bytecode.Instruction {
    var frame = &self.frames.items[self.frames.items.len - 1];
    if (frame.ip >= frame.chunk.code.items.len) return error.BytecodeCorrupted;
    const instruction = frame.chunk.code.items[frame.ip];
    frame.ip += 1;
    return instruction;
}
