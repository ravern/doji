const std = @import("std");
const gc = @import("gc.zig");
const value = @import("value.zig");
const vm = @import("vm.zig");
const source = @import("source.zig");
const compile = @import("compile.zig");

test {
    std.testing.refAllDecls(gc);
    std.testing.refAllDecls(value);
    std.testing.refAllDecls(vm);
    std.testing.refAllDecls(source);
    std.testing.refAllDecls(compile);
}
