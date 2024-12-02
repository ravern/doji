const std = @import("std");
const gc = @import("gc.zig");
const value = @import("value.zig");

test {
    std.testing.refAllDecls(gc);
    std.testing.refAllDecls(value);
}
