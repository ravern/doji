const std = @import("std");
const gc = @import("gc.zig");
const value = @import("value.zig");
const vm = @import("vm.zig");

pub const Config = struct {};

pub fn Doji(comptime config: Config) type {
    _ = config;

    return struct {
        pub const GC = gc.GC(
            .{
                value.String,
                value.List,
                value.Fiber,
            },
            .{
                .FinalizeContext = std.mem.Allocator,
            },
        );

        pub const Value = value.Value;
        pub const String = value.String;
        pub const Fiber = value.Fiber;
        pub const ForeignFn = value.ForeignFn();

        pub const VM = vm.VM(GC, Value, .{});
    };
}
