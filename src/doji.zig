const std = @import("std");
const gc = @import("gc.zig");
pub const value = @import("value.zig");

pub const GC = gc.GC;

test {
    std.testing.refAllDecls(gc);
    std.testing.refAllDecls(value);
}
