const std = @import("std");
const Value = @import("value.zig").Value;

pub const Chunk = struct {
    arity: u8,
    code: []const Instruction,
    constants: []const Value,
    chunks: []const *Chunk,

    pub fn deinit(self: *Chunk, allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        allocator.free(self.constants);
        self.* = undefined;
    }
};

pub const Instruction = packed struct {
    op: Op,
    arg: u24,
};

pub const Op = enum(u8) {
    nop,

    nil,
    true,
    false,
    int,
    constant,

    add,
    sub,
    mul,
    div,

    call,
    ret,
};
