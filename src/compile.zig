const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const GC = @import("gc.zig").GC;
const Input = @import("input.zig").Input;

pub const Context = struct {
    allocator: std.mem.Allocator,
    gc: *GC,
    string_pool: *StringPool,
    prelude: Prelude,
};

pub const Prelude = struct {
    globals: []const []const u8,
};

pub fn compile(ctx: Context, input: Input) Chunk {}
