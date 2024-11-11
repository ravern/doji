const std = @import("std");
const Allocator = std.mem.Allocator;

pub const OpCode = enum(u8) {
    noop = 0x00,
    ext = 0x01,

    nil = 0x10,
    bool = 0x11,
    int = 0x12,
    list = 0x13,
    map = 0x14,

    constant = 0x20,
    closure = 0x21,

    add = 0x30,
    sub = 0x31,
    mul = 0x32,
    div = 0x33,
    rem = 0x34,
    eq = 0x35,
    neq = 0x36,
    neg = 0x37,
    gt = 0x38,
    gte = 0x39,
    lt = 0x3A,
    lte = 0x3B,
    log_and = 0x3C,
    log_or = 0x3D,
    log_not = 0x3E,
    bit_and = 0x3F,
    bit_or = 0x40,
    bit_not = 0x41,
    xor = 0x42,
    shl = 0x43,
    shr = 0x44,

    load = 0x50,
    store = 0x51,
    dup = 0x52,
    pop = 0x53,

    check = 0x60,
    jump = 0x61,

    call = 0x70,
    ret = 0x71,

    upval_load = 0x80,
    upval_store = 0x81,
    upval_close = 0x82,

    obj_get = 0x90,
    obj_set = 0x91,
};

pub const Instruction = struct {
    op: OpCode,
    arg: u8 = 0,
};

pub const Chunk = struct {
    upvals: []const Upvalue,
    code: []const Instruction,

    pub fn deinit(self: Chunk, allocator: Allocator) void {
        allocator.free(self.upvals);
        allocator.free(self.code);
    }
};

pub const Upvalue = union(enum) {
    Local: u32,
    Upvalue: u32,
};
