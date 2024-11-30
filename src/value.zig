const std = @import("std");
const GC = @import("gc.zig").GC;
const Tracer = @import("gc.zig").Tracer;
const Fiber = @import("vm.zig").Fiber;

// needs to be extern to avoid Zig's safety check of which field is active.
pub const Value = extern union {
    float: f64,
    raw: u64,

    pub fn initList(gc: *GC) !Value {
        const list = try gc.create(List);
        return initPtr(list);
    }

    fn initPtr(ptr: *anyopaque) Value {
        return .{ .raw = @intFromPtr(ptr) };
    }

    pub fn asFiber(self: Value) ?*Fiber {
        const ptr = self.asPtr() orelse return null;
        return GC.cast(Fiber, ptr);
    }

    pub fn asList(self: Value) ?*List {
        const ptr = self.asPtr() orelse return null;
        return GC.cast(List, ptr);
    }

    fn asPtr(self: Value) ?*anyopaque {
        return @ptrFromInt(self.raw);
    }

    fn traceIfPtr(self: Value, gc: *GC, tracer: Tracer) !void {
        if (self.asPtr()) |ptr| {
            try tracer.trace(gc, ptr);
        }
    }
};

pub const List = struct {
    items: std.ArrayListUnmanaged(Value),

    pub fn deinit(self: *List, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
        self.* = undefined;
    }

    pub fn trace(self: *List, gc: *GC, tracer: Tracer) !void {
        for (self.items.items) |value| {
            try value.traceIfPtr(gc, tracer);
        }
    }
};

pub const Map = struct {
    items: std.HashMapUnmanaged(Value, Value, ValueContext, 80),

    pub fn deinit(self: *Map, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
        self.* = undefined;
    }

    pub fn trace(self: *Map, gc: *GC, tracer: Tracer) !void {
        var it = self.items.iterator();
        while (it.next()) |entry| {
            try entry.key_ptr.traceIfPtr(gc, tracer);
            try entry.value_ptr.traceIfPtr(gc, tracer);
        }
    }
};

// TODO: make these proper lol
pub const ValueContext = struct {
    pub fn hash(self: ValueContext, key: Value) u64 {
        _ = self;

        return key.raw;
    }

    pub fn eql(self: ValueContext, left: Value, right: Value) bool {
        _ = self;

        return left.raw == right.raw;
    }
};
