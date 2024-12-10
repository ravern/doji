const std = @import("std");
const GC = @import("gc.zig").GC;
const Value = @import("value.zig").Value;
const Error = @import("value.zig").Error;
const Source = @import("source.zig").Source;

pub const Chunk = struct {
    arity: usize,
    code: []const Instruction,
    constants: []const Value,
    chunks: []const *const Chunk,
    trace_items: ErrorTraceItems,

    pub fn deinit(self: *Chunk, allocator: std.mem.Allocator) void {
        allocator.free(self.code);
        allocator.free(self.constants);
        allocator.free(self.chunks);
        allocator.free(self.trace_items.locations);
        self.* = undefined;
    }

    pub fn trace(self: *const Chunk, tracer: *GC.Tracer) !void {
        for (self.constants) |constant| {
            try constant.trace(tracer);
        }
        for (self.chunks) |chunk| {
            try chunk.trace(tracer);
        }
    }
};

pub const Instruction = packed struct {
    op: Op,
    arg: Arg = 0,

    pub const Op = enum(u8) {
        nop,

        true,
        false,
        int,
        constant,
        foreign_fn,

        add,
        sub,
        mul,
        div,

        is_error,

        call,
        ret,
    };

    pub const Arg = u24;
};

// FIXME: this probably consumes way more memory than it should
// each instruction in [Chunk.code] corresponds to a location in [locations]
pub const ErrorTraceItems = struct {
    path: []const u8,
    locations: []const Source.Location,
};
