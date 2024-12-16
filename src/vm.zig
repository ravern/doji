const std = @import("std");
const doji = @import("root.zig");

pub const Config = struct {};

pub fn VM(
    comptime GC: type,
    comptime Value: type,
    comptime config: Config,
) type {
    _ = GC;
    _ = Value;
    _ = config;

    return struct {
        const Self = @This();
    };
}
