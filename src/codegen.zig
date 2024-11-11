const std = @import("std");
const ast = @import("ast.zig");
const bytecode = @import("bytecode.zig");

pub fn generate(allocator: std.mem.Allocator, root: ast.Root) !bytecode.Chunk {
    var chunk = bytecode.Chunk{};
    _ = try chunk.appendInstArg(allocator, .int, @intCast(root.root.int.int));
    return chunk;
}
