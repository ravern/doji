const std = @import("std");
const Value = @import("value.zig").Value;

pub const Chunk = struct {
    code: []const Instruction,
    constants: []const Constant,
};

pub const Op = enum(u8) {
    nop,

    int,

    add,

    ret,
};

pub const Instruction = packed struct {
    op: Op,
    arg: u24,
};

test Instruction {
    try std.testing.expectEqual(32, @bitSizeOf(Instruction));
}

pub const Constant = union(enum) {
    value: Value,
    function: Function,
};

pub const Function = struct {
    arity: u8,
    chunk: *Chunk,
};
