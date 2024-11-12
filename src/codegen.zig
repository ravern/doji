const std = @import("std");
const ast = @import("ast.zig");
const bytecode = @import("bytecode.zig");
const Value = @import("Value.zig");

const Frame = struct {
    const Self = @This();

    chunk: bytecode.Chunk = .{},
};

pub fn generate(allocator: std.mem.Allocator, root: ast.Root) !bytecode.Chunk {
    var frame = Frame{};
    try generateExpression(allocator, &frame, root.root);
    return frame.chunk;
}

pub fn generateExpression(allocator: std.mem.Allocator, frame: *Frame, expr: *const ast.Expression) !void {
    switch (expr.*) {
        .int => |int| {
            _ = try frame.chunk.appendInstArg(allocator, .int, @intCast(int.int));
        },
        .float => |float| {
            const index = try frame.chunk.appendConstant(allocator, Value.initFloat(float.float));
            _ = try frame.chunk.appendInstArg(allocator, .constant, @intCast(index));
        },
    }
}
