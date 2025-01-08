const std = @import("std");
const gc = @import("gc.zig");
pub const value = @import("value.zig");

pub const GC = gc.GC;
pub const Value = value.Value;

test {
    std.testing.refAllDecls(gc);
    std.testing.refAllDecls(value);
}
