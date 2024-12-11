const std = @import("std");
const code = @import("code.zig");
const ast = @import("compile/ast.zig");
const scan = @import("compile/scan.zig");
const Scanner = scan.Scanner;
const Token = scan.Token;
const parse = @import("compile/parse.zig");
const codegen = @import("compile/codegen.zig");
const Parser = parse.Parser;
const GC = @import("root.zig").GC;
const Source = @import("source.zig").Source;
const Value = @import("value.zig").Value;
const String = @import("value.zig").String;
const StringPool = @import("vm.zig").StringPool;

pub const Context = struct {
    allocator: std.mem.Allocator,
    gc: *GC,
    string_pool: *StringPool,
    globals: *std.ArrayList(*String),
    source: *const Source,
};

// TODO: remove this
//
// allocator, gc, string_pool -> via foreign fn ctx
// globals -> empty
// source -> via resolver

pub fn compile(ctx: *Context, err: *Error) !*code.Chunk {
    var parser = Parser.init(ctx, err);
    var block = try parser.parse();
    defer block.deinit(ctx.allocator);
    return codegen.generate(ctx, &block);
}

// for use internally by [compile]
pub const Error = struct {
    path: []const u8,
    location: Source.Location,
    data: Data,

    pub const Data = union(enum) {
        parse: ParseError,
    };
};

pub const ParseError = struct {
    unexpected: Item,
    expected: []const Item,

    pub const Item = union(enum) {
        char: u8,
        token: Token.Type,
        digit,
        alphabet,
        expression,
        end_of_input,
    };
};

test {
    std.testing.refAllDecls(scan);
    std.testing.refAllDecls(parse);
    std.testing.refAllDecls(ast);
    std.testing.refAllDecls(codegen);
}
