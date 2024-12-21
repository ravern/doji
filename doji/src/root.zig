const std = @import("std");
const gc = @import("gc.zig");
const value = @import("value.zig");
const vm = @import("vm.zig");

pub const String = value.String;

pub const GC = gc.GC(
    .{
        value.String,
        value.List,
        value.Fiber,
    },
    std.mem.Allocator,
);
