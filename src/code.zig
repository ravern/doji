const std = @import("std");
const Value = @import("value.zig").Value;

pub const Chunk = struct {
    code: []const Instruction,
    arity: usize,
    constants: []const Value,
    chunks: []const Chunk,
    upvalues: []const Upvalue,
};

pub const Instruction = packed struct {
    op: Op,
    arg: Arg,

    pub const Op = enum(u8) {
        nop,

        nil,
        true,
        false,
        int,
        constant,

        list,
        map,
        closure,
        foreign_fn,

        load,
        store,
        duplicate,
        pop,

        add,
        sub,
        mul,
        div,
        rem,
        neg,

        eq,
        ne,
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

        upvalue_load,
        upvalue_store,
        upvalue_close,

        object_get,
        object_set,

        call,
        ret,
    };

    pub const Arg = u24;
};

pub const Upvalue = union(enum) {
    local: u32,
    upvalue: u32,
};
