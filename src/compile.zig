const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const codegen = @import("./compile/codegen.zig");
const lex = @import("./compile/lex.zig");
const parse = @import("./compile/parse.zig");
const Parser = parse.Parser;
const DojiError = @import("./errors.zig").DojiError;
const Environment = @import("./global.zig").Environment;
const bytecode = @import("./vm/bytecode.zig");
const Chunk = bytecode.Chunk;

pub fn compile(allocator: Allocator, env: *Environment, source: []const u8) !Chunk {
    var parser = Parser.init(env, source);
    const file = try parser.parse(allocator);
    defer file.deinit(allocator);
    return codegen.generate(allocator, env, &file);
}

test {
    testing.refAllDecls(@This());
}
