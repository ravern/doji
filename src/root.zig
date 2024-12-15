const std = @import("std");
const code = @import("code.zig");
const compile = @import("compile.zig");
const gc = @import("gc.zig");
const vm = @import("vm.zig");
const resolver = @import("resolver.zig");
const source = @import("source.zig");
const string_pool = @import("string_pool.zig");

pub const VM = vm.VM;
pub const Resolver = resolver.Resolver;
pub const FileResolver = resolver.FileResolver;
pub const value = @import("value.zig");
pub const Value = value.Value;
pub const Source = source.Source;

pub const GC = gc.GC(union {
    // values
    string: value.String,
    list: value.List,
    map: value.Map,
    err: value.Error,
    closure: value.Closure,
    fiber: value.Fiber,
    // non-values
    chunk: code.Chunk,
    upvalue: value.Upvalue,
});

test {
    std.testing.refAllDecls(code);
    std.testing.refAllDecls(compile);
    std.testing.refAllDecls(gc);
    std.testing.refAllDecls(value);
    std.testing.refAllDecls(vm);
    std.testing.refAllDecls(resolver);
    std.testing.refAllDecls(source);
    std.testing.refAllDecls(string_pool);
}
