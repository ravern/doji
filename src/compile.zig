const std = @import("std");
const bytecode = @import("bytecode.zig");
const codegen = @import("compile/codegen.zig");
const heap = @import("heap.zig");
const Parser = @import("compile/Parser.zig");
const Source = @import("Source.zig");
const Value = @import("Value.zig");

pub const Error = error{
    CompileFailed,
    OutOfMemory,
};

pub const Context = struct {
    allocator: std.mem.Allocator,
    gc: *heap.GC,
    string_pool: *heap.StringPool,
    globals_map: *[]*heap.String,
};

pub fn compile(context: *Context, source: *const Source) !bytecode.Chunk {
    var parser = Parser.init(context, source);
    var module = try parser.parse();
    defer module.deinit(context.allocator);

    const chunk = try codegen.generate(context, &module);

    // TODO: return closure instead.
    return chunk;
}
