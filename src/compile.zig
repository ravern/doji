const std = @import("std");
const code = @import("code.zig");
const GC = @import("gc.zig").GC;
const Value = @import("value.zig").Value;
const StringPool = @import("vm.zig").StringPool;
const Source = @import("source.zig").Source;

pub const Context = struct {
    allocator: std.mem.Allocator,
    gc: *GC,
    string_pool: *StringPool,
    globals: []const []const u8,
};

pub const Result = struct {
    globals: []const []const u8,
    chunk: *const code.Chunk,
};

pub fn compile(ctx: Context, source: *const Source) !Result {
    const insts = [_]code.Instruction{
        .{ .op = .int, .arg = 5 },
        .{ .op = .foreign_fn, .arg = 0 },
        .{ .op = .int, .arg = 6 },
        .{ .op = .int, .arg = 7 },
        .{ .op = .int, .arg = 8 },
        .{ .op = .mul },
        .{ .op = .call, .arg = 2 },
        .{ .op = .sub },
        .{ .op = .ret },
    };
    const constants = [_]Value{
        Value.nil,
    };
    const chunks = [_]*const code.Chunk{&code.Chunk.empty};

    const chunk = try ctx.gc.create(code.Chunk);
    chunk.* = .{
        .arity = 0,
        .code = try ctx.allocator.dupe(code.Instruction, &insts),
        .constants = try ctx.allocator.dupe(Value, &constants),
        .chunks = try ctx.allocator.dupe(*const code.Chunk, &chunks),
        .trace_items = .{ .path = source.path, .locations = &.{} },
    };

    return .{
        .globals = ctx.globals,
        .chunk = chunk,
    };
}
