const std = @import("std");
const GC = @import("root.zig").GC;

pub const String = struct {
    str: []const u8,

    pub fn trace(self: *String, tracer: *GC.Tracer) void {
        _ = self;
        _ = tracer;
    }

    pub fn finalize(self: *String, finalize_ctx: void) void {
        _ = self;
        _ = finalize_ctx;
    }
};
