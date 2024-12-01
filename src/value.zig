const std = @import("std");
const GC = @import("gc.zig").GC;
const Fiber = @import("vm.zig").Fiber;

pub const Value = struct {
    raw: u64,

    const q_nan: u64 = 0x7ffc000000000000;

    const tag_nil: u64 = 0x0000000000000000;
    const tag_true: u64 = 0x0000000000000001;
    const tag_false: u64 = 0x0000000000000002;
    const tag_int: u64 = 0x0000000000000003;
    const tag_object: u64 = 0x8000000000000000;

    pub const nil = Value{ .raw = q_nan | tag_nil };

    pub fn init(data: anytype) Value {
        return switch (@TypeOf(data)) {
            bool => if (data) .{ .raw = q_nan | tag_true } else .{ .raw = q_nan | tag_false },
            comptime_int => .{ .raw = q_nan | tag_int | makePayload(@bitCast(@as(i48, @intCast(data)))) },
            i48 => .{ .raw = q_nan | tag_int | makePayload(@bitCast(data)) },
            comptime_float, f64 => .{ .raw = @bitCast(@as(f64, data)) },
            *Fiber, *List, *Map => .{ .raw = q_nan | tag_object | makePayload(@truncate(@intFromPtr(data))) },
            else => throwInvalidTypeError(@TypeOf(data)),
        };
    }

    pub fn cast(self: Value, comptime T: type) ?T {
        return switch (T) {
            f64 => if (self.isFloat()) @bitCast(self.raw) else null,
            i48 => if (self.isInt()) self.toInt() else null,
            *Fiber, *List, *Map => if (self.isObject()) GC.cast(T, self.toObject()) else null,
            else => throwInvalidTypeError(T),
        };
    }

    inline fn isFloat(self: Value) bool {
        return (self.raw & q_nan) != q_nan;
    }

    inline fn isInt(self: Value) bool {
        return !self.isFloat() and self.raw & tag_int == tag_int;
    }

    inline fn isObject(self: Value) bool {
        return !self.isFloat() and self.raw & tag_object == tag_object;
    }

    inline fn toInt(self: Value) i48 {
        return @as(i48, @bitCast(self.getPayload()));
    }

    inline fn toObject(self: Value) *anyopaque {
        return @ptrFromInt(self.getPayload());
    }

    inline fn makePayload(data: u48) u64 {
        return @as(u64, @intCast(data)) << 2;
    }

    inline fn getPayload(self: Value) u48 {
        return @truncate(self.raw >> 2);
    }

    fn markIfObject(self: Value, gc: *GC) !void {
        if (self.isObject()) {
            try gc.mark(self.toObject());
        }
    }
};

pub const List = struct {
    items: std.ArrayListUnmanaged(Value),

    pub fn deinit(self: *List, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
        self.* = undefined;
    }

    pub fn mark(self: *List, gc: *GC) !void {
        for (self.items.items) |value| {
            try value.markIfObject(gc);
        }
    }
};

pub const Map = struct {
    items: std.HashMapUnmanaged(Value, Value, ValueContext, 80),

    pub fn deinit(self: *Map, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
        self.* = undefined;
    }

    pub fn mark(self: *Map, gc: *GC) !void {
        var it = self.items.iterator();
        while (it.next()) |entry| {
            try entry.key_ptr.markIfObject(gc);
            try entry.value_ptr.markIfObject(gc);
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

fn throwInvalidTypeError(comptime T: type) noreturn {
    @compileError(@typeName(T) ++ " is not a valid type for a Doji value");
}
