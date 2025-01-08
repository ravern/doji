const std = @import("std");
const FinalizeContext = @import("gc.zig").FinalizeContext;
const Object = @import("gc.zig").Object;
const Tracer = @import("gc.zig").Tracer;

pub const Value = struct {
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
            return Value.eql(left, right);
        }
    };

    raw: u64,

    const q_nan: u64 = 0x7ffc000000000000;
    const payload_mask: u64 = 0x0003fffffffffffc;
    const tag_mask: u64 = 0x8000000000000003;

    const tag_nil: u64 = 0x0000000000000000;
    const tag_true: u64 = 0x0000000000000001;
    const tag_false: u64 = 0x0000000000000002;
    const tag_int: u64 = 0x0000000000000003;
    const tag_gc: u64 = 0x8000000000000000;
    const tag_foreign: u64 = 0x80000000000000001;

    const num_tag_suffix_bits = 2;

    pub const nil = Value{ .raw = q_nan | @intFromEnum(tag_nil) };

    pub fn init(data: anytype) Value {
        const T = @TypeOf(data);
        return switch (T) {
            bool => Value{ .raw = q_nan | (if (data) tag_true else tag_false) },
            comptime_float, f64 => Value{ .raw = @bitCast(@as(f64, @floatCast(data))) },
            comptime_int, i48 => Value{ .raw = q_nan | tag_int | rawFromInt(@intCast(data)) },
            *String, *List => Value{ .raw = q_nan | tag_gc | rawFromPtr(data) },
            else => @compileError(@typeName(T) ++ " is not a valid value type"),
        };
    }

    pub fn cast(self: Value, comptime T: type) ?T {
        return switch (T) {
            bool => if (!self.isFloat() and (self.hasTag(tag_true) or self.hasTag(tag_false))) self.hasTag(tag_true) else null,
            f64 => if (self.isFloat()) @bitCast(self.raw) else null,
            i48 => if (!self.isFloat() and self.hasTag(tag_int)) intFromRaw(self.raw) else null,
            *String, *List => if (!self.isFloat() and self.hasTag(tag_gc)) Object.cast(ptrFromRaw(self.raw), @typeInfo(T).Pointer.child) else null,
            else => @compileError(@typeName(T) ++ " is not a valid value type"),
        };
    }

    pub fn trace(self: *Value, tracer: *Tracer) !void {
        if (self.hasTag(tag_gc)) {
            try tracer.trace(ptrFromRaw(self.raw));
        }
    }

    inline fn isFloat(self: Value) bool {
        return (self.raw & q_nan) != q_nan;
    }

    inline fn hasTag(self: Value, tag: u64) bool {
        return (self.raw & tag_mask) == tag;
    }

    inline fn rawFromInt(int: i48) u64 {
        return rawFromData(@bitCast(int));
    }

    inline fn intFromRaw(raw: u64) i48 {
        return @bitCast(dataFromRaw(raw));
    }

    inline fn rawFromPtr(ptr: *anyopaque) u64 {
        return rawFromData(@intCast(@intFromPtr(ptr)));
    }

    inline fn ptrFromRaw(raw: u64) *anyopaque {
        return @ptrFromInt(dataFromRaw(raw));
    }

    inline fn rawFromData(data: u48) u64 {
        return @as(u64, @intCast(data)) << num_tag_suffix_bits;
    }

    inline fn dataFromRaw(raw: u64) u48 {
        return @truncate(raw >> num_tag_suffix_bits);
    }
};

pub const List = struct {
    list: std.ArrayListUnmanaged(Value),

    pub fn deinit(self: *List, allocator: std.mem.Allocator) void {
        self.list.deinit(allocator);
    }

    pub fn trace(self: *List, tracer: *Tracer) !void {
        for (self.list.items) |*value| {
            try value.trace(tracer);
        }
    }

    pub fn finalize(self: *List, ctx: *FinalizeContext) void {
        self.deinit(ctx.allocator);
    }
};

pub const String = union(enum) {
    manual: []const u8,
    gc: []const u8, // when finalized, will free the underlying str

    pub fn deinit(self: *String, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .manual => {},
            .gc => |str| allocator.free(str),
        }
    }

    pub fn trace(self: *String, tracer: *Tracer) !void {
        _ = self;
        _ = tracer;
    }

    pub fn finalize(self: *String, ctx: *FinalizeContext) void {
        self.deinit(ctx.allocator);
    }

    pub fn toStr(self: *const String) []const u8 {
        switch (self.*) {
            .manual => |str| return str,
            .gc => |str| return str,
        }
    }
};
