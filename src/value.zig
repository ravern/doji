const std = @import("std");
const FinalizeContext = @import("gc.zig").FinalizeContext;
const Tracer = @import("gc.zig").Tracer;

pub const String = union(enum) {
    manual: []const u8,
    gc: []const u8, // when finalized, will free the underlying str

    pub fn trace(self: *String, tracer: *Tracer) !void {
        _ = self;
        _ = tracer;
    }

    pub fn finalize(self: *String, ctx: *FinalizeContext) void {
        switch (self.*) {
            .manual => {},
            .gc => |str| ctx.allocator.free(str),
        }
    }

    pub fn toStr(self: *const String) []const u8 {
        switch (self.*) {
            .manual => |str| return str,
            .gc => |str| return str,
        }
    }
};
