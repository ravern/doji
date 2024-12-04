const std = @import("std");
const GC = @import("gc.zig").GC;

pub const Value = struct {
    raw: u64,

    const q_nan: u64 = 0x7ffc000000000000;

    const num_tag_bits = 2;
    const tag_nil: u64 = 0x0000000000000000;
    const tag_true: u64 = 0x0000000000000001;
    const tag_false: u64 = 0x0000000000000002;
    const tag_int: u64 = 0x0000000000000003;
    const tag_gc_object: u64 = 0x8000000000000000;
    const tag_foreign_fn: u64 = 0x8000000000000001;

    const HashMapContext = struct {
        pub fn hash(self: HashMapContext, value: Value) u64 {
            _ = self;

            if (value.cast(*String)) |string| {
                return string.hash;
            }
            return std.hash.Wyhash.hash(0, std.mem.asBytes(&value.raw));
        }

        pub fn eql(self: HashMapContext, left: Value, right: Value) bool {
            _ = self;

            if (left.raw != right.raw) {
                if (left.cast(*String)) |left_string| {
                    if (right.cast(*String)) |right_string| {
                        return std.mem.eql(u8, left_string.data, right_string.data);
                    }
                }
            }
            return left.raw == right.raw;
        }
    };

    pub fn init(data: anytype) Value {
        const T = @TypeOf(data);
        return switch (T) {
            bool => Value{ .raw = q_nan | (if (data) tag_true else tag_false) },
            comptime_float, f64 => Value{ .raw = @bitCast(@as(f64, @floatCast(data))) },
            comptime_int, i48 => Value{ .raw = q_nan | tag_int | rawFromData(@bitCast(@as(i48, @intCast(data)))) },
            *String, *List, *Map => Value{ .raw = q_nan | tag_gc_object | rawFromPtr(data) },
            *ForeignFn => Value{ .raw = q_nan | tag_foreign_fn | rawFromPtr(data) },
            else => invalidValueTypeError(T),
        };
    }

    pub fn cast(self: Value, comptime T: type) ?T {
        return switch (T) {
            bool => if (!self.isFloat() and (self.hasTag(tag_true) or self.hasTag(tag_false))) self.hasTag(tag_true) else null,
            f64 => if (self.isFloat()) @bitCast(self.raw) else null,
            i48 => if (!self.isFloat() and self.hasTag(tag_int)) @as(i48, @bitCast(dataFromRaw(self.raw))) else null,
            *String, *List, *Map => if (!self.isFloat() and self.hasTag(tag_gc_object)) @ptrCast(@alignCast(ptrFromRaw(self.raw))) else null,
            *ForeignFn => if (!self.isFloat() and self.hasTag(tag_foreign_fn)) @ptrCast(@alignCast(ptrFromRaw(self.raw))) else null,
            else => invalidValueTypeError(T),
        };
    }

    inline fn isFloat(self: Value) bool {
        return (self.raw & q_nan) != q_nan;
    }

    inline fn hasTag(self: Value, tag: u64) bool {
        return (self.raw & tag) == tag;
    }

    inline fn rawFromPtr(ptr: *anyopaque) u64 {
        return rawFromData(@intCast(@intFromPtr(ptr)));
    }

    inline fn ptrFromRaw(raw: u64) *anyopaque {
        return @ptrFromInt(dataFromRaw(raw));
    }

    inline fn rawFromData(data: u48) u64 {
        return @as(u64, @intCast(data)) << num_tag_bits;
    }

    inline fn dataFromRaw(raw: u64) u48 {
        return @truncate(raw >> num_tag_bits);
    }
};

fn invalidValueTypeError(comptime T: type) noreturn {
    @compileError(@typeName(T) ++ " is not a valid type for Value");
}

test Value {
    var string: String = undefined;
    var list: List = undefined;
    var map: Map = undefined;
    var foreign_fn: ForeignFn = undefined;

    // positive tests

    try std.testing.expectEqual(true, Value.init(true).cast(bool).?);
    try std.testing.expectEqual(false, Value.init(false).cast(bool).?);

    try std.testing.expectEqual(100, Value.init(100).cast(i48).?);
    try std.testing.expectEqual(-100, Value.init(-100).cast(i48).?);

    try std.testing.expectEqual(3.14159, Value.init(3.14159).cast(f64).?);
    try std.testing.expectEqual(-2.71828, Value.init(-2.71828).cast(f64).?);

    try std.testing.expectEqual(&string, Value.init(&string).cast(*String).?);

    try std.testing.expectEqual(&list, Value.init(&list).cast(*List).?);

    try std.testing.expectEqual(&map, Value.init(&map).cast(*Map).?);

    try std.testing.expectEqual(&foreign_fn, Value.init(&foreign_fn).cast(*ForeignFn).?);

    // negative tests

    try std.testing.expectEqual(null, Value.init(true).cast(i48));
    try std.testing.expectEqual(null, Value.init(32).cast(f64));
    try std.testing.expectEqual(null, Value.init(3.14159).cast(i48));
    try std.testing.expectEqual(null, Value.init(&string).cast(i48));
    try std.testing.expectEqual(null, Value.init(&list).cast(i48));
    try std.testing.expectEqual(null, Value.init(&map).cast(i48));
    try std.testing.expectEqual(null, Value.init(&foreign_fn).cast(i48));
}

pub const String = struct {
    data: []const u8,
    hash: u64,

    pub fn deinit(self: *String, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        self.* = undefined;
    }
};

pub const List = struct {
    items: std.ArrayListUnmanaged(Value),

    pub fn deinit(self: *List, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
        self.* = undefined;
    }
};

pub const Map = struct {
    items: std.HashMapUnmanaged(Value, Value, Value.HashMapContext, 80),

    pub fn deinit(self: *Map, allocator: std.mem.Allocator) void {
        self.items.deinit(allocator);
        self.* = undefined;
    }
};

pub const ForeignFn = struct {
    entry_fn: *const fn (ctx: Context) Result,
    body_fns: []*const fn (ctx: Context) Result,

    pub const Context = struct {
        allocator: std.mem.Allocator,
        gc: *GC,
    };

    pub const Result = union(enum) {
        ret: Value,
        err: Value,
        yield: Value,
    };
};
