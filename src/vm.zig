const std = @import("std");
const code = @import("code.zig");
const GC = @import("gc.zig").GC;
const String = @import("value.zig").String;
const List = @import("value.zig").List;
const Map = @import("value.zig").Map;
const Closure = @import("value.zig").Closure;
const Upvalue = @import("value.zig").Upvalue;
const Fiber = @import("value.zig").Fiber;

pub const VM = struct {
    allocator: std.mem.Allocator,
    gc: GC,
    fiber: *Fiber,

    fn mutator(self: *VM) GC.Mutator {
        return .{
            .ptr = self,
            .vtable = &.{
                .mark_roots = markRoots,
                .trace = trace,
                .finalize = finalize,
            },
        };
    }

    pub fn init(allocator: std.mem.Allocator) !*VM {
        var self = try allocator.create(VM);
        self.* = .{
            .allocator = allocator,
            .gc = GC.init(allocator, self.mutator()),
            .fiber = undefined,
        };

        const closure = try self.gc.create(Closure);
        closure.* = .{ .chunk = &code.Chunk.empty, .upvalues = &.{} };

        self.fiber = try self.gc.create(Fiber);
        self.fiber.* = try Fiber.init(self.allocator, closure);

        return self;
    }

    pub fn deinit(self: *VM) void {
        self.gc.deinit();
        self.allocator.destroy(self);
    }

    fn markRoots(ctx: *anyopaque, gc: *GC) !void {
        const self: *VM = @ptrCast(@alignCast(ctx));

        try gc.mark(self.fiber);
    }

    fn trace(ctx: *anyopaque, tracer: *GC.Tracer, tag: GC.ObjectTag, data: *anyopaque) !void {
        _ = ctx;

        try switch (tag) {
            .string => {},
            .list => @as(*List, @ptrCast(@alignCast(data))).trace(tracer),
            .map => @as(*Map, @ptrCast(@alignCast(data))).trace(tracer),
            .closure => @as(*Closure, @ptrCast(@alignCast(data))).trace(tracer),
            .fiber => @as(*Fiber, @ptrCast(@alignCast(data))).trace(tracer),
            .chunk => @as(*code.Chunk, @ptrCast(@alignCast(data))).trace(tracer),
            .upvalue => @as(*Upvalue, @ptrCast(@alignCast(data))).trace(tracer),
        };
    }

    fn finalize(ctx: *anyopaque, tag: GC.ObjectTag, data: *anyopaque) void {
        const self: *VM = @ptrCast(@alignCast(ctx));

        switch (tag) {
            .string => @as(*String, @ptrCast(@alignCast(data))).deinit(self.allocator),
            .list => @as(*List, @ptrCast(@alignCast(data))).deinit(self.allocator),
            .map => @as(*Map, @ptrCast(@alignCast(data))).deinit(self.allocator),
            .closure => @as(*Closure, @ptrCast(@alignCast(data))).deinit(self.allocator),
            .fiber => @as(*Fiber, @ptrCast(@alignCast(data))).deinit(self.allocator),
            .chunk => @as(*code.Chunk, @ptrCast(@alignCast(data))).deinit(self.allocator),
            .upvalue => {},
        }
    }
};

test VM {
    const allocator = std.testing.allocator;

    var vm = try VM.init(allocator);
    defer vm.deinit();
}
