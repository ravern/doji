const std = @import("std");
const GC = @import("gc.zig").GC;
const Value = @import("value.zig").Value;

pub const Chunk = struct {
    arity: usize,
    code: []const Instruction,
    constants: []const Value,
    chunks: []const *const Chunk,

    pub const empty = Chunk{
        .arity = 0,
        .code = &.{},
        .constants = &.{},
        .chunks = &.{},
    };

    pub fn deinit(self: *Chunk, allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        allocator.free(self.constants);
        allocator.free(self.chunks);
        self.* = undefined;
    }

    pub fn trace(self: *const Chunk, tracer: *GC.Tracer) !void {
        for (self.constants) |constant| {
            try constant.trace(tracer);
        }
        for (self.chunks) |chunk| {
            try chunk.trace(tracer);
        }
    }
};

pub const Instruction = packed struct {
    op: Op,
    arg: u24 = 0,

    pub const Op = enum(u8) {
        int,
        constant,
        add,
        sub,
        mul,
        div,
        ret,
    };
};
