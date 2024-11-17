const std = @import("std");
const Value = @import("Value.zig");
const ast = @import("compile/ast.zig");

pub const Instruction = packed struct {
    pub const Op = enum(u8) {
        nil,
        true,
        false,
        int,
        constant,

        local,
        store_local,

        dup,
        pop,

        add,
        sub,
        mul,
        div,
        mod,
        pos,
        neg,
        eq,
        neq,
        lt,
        le,
        gt,
        ge,
        log_and,
        log_or,
        log_not,
        bit_and,
        bit_or,
        bit_xor,
        bit_not,
        shl,
        shr,

        ret,
    };

    pub const Arg = u24;

    op: Op,
    arg: Arg,
};

pub const Chunk = struct {
    code: []Instruction,
    constants: []Value,

    pub fn deinit(self: *Chunk, allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        allocator.free(self.constants);
        self.* = undefined;
    }
};
