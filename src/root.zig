const std = @import("std");
const chunk = @import("chunk.zig");

pub const gc = @import("gc.zig");
pub const GC = gc.GC;
pub const input = @import("input.zig");
pub const Input = input.Input;
pub const vm = @import("vm.zig");
pub const VM = vm.VM;
pub const value = @import("value.zig");
pub const Value = value.Value;

test {
    std.testing.refAllDecls(chunk);
    std.testing.refAllDecls(gc);
}
