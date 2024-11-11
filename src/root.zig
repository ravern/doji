const std = @import("std");
const testing = std.testing;

const compile = @import("./compile.zig");
const global = @import("./global.zig");
const vm = @import("./vm.zig");

pub const Vm = vm.Vm;

test {
    testing.refAllDecls(@This());
}
