const std = @import("std");
const gc = @import("gc.zig");
const value = @import("value.zig");
const vm = @import("vm.zig");

test {
    std.testing.refAllDecls(gc);
    std.testing.refAllDecls(value);
    std.testing.refAllDecls(vm);
}
