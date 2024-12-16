const std = @import("std");
const gc = @import("gc.zig");
const value = @import("value.zig");
const vm = @import("vm.zig");

pub const Config = struct {};

pub fn Doji(comptime config: Config) type {
    return struct {
        pub const GC = gc.GC(
            .{
                value.String,
            },
            .{
                .FinalizationContext = std.mem.Allocator,
            },
        );

        pub const Value = value.Value(GC);
        pub const String = value.String;

        pub const VM = vm.VM(GC, Value, config);
    };
}
