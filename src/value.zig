const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const GC = @import("gc.zig").GC;
const VM = @import("vm.zig").VM;
const Fiber = @import("vm.zig").Fiber;

pub const Value = struct {
    raw: u64,

    const q_nan: u64 = 0x7ffc000000000000;

    const tag_nil: u64 = 0x0000000000000000;
    const tag_true: u64 = 0x0000000000000001;
    const tag_false: u64 = 0x0000000000000002;
    const tag_int: u64 = 0x0000000000000003;
    const tag_object: u64 = 0x8000000000000000;
    const tag_foreign_fn: u64 = 0x8000000000000001;
    const tag_foreign_data: u64 = 0x8000000000000002;

    pub const nil = Value{ .raw = q_nan | tag_nil };

    pub fn init(data: anytype) Value {
        return switch (@TypeOf(data)) {
            bool => return if (data) .{ .raw = q_nan | tag_true } else .{ .raw = q_nan | tag_false },
            comptime_int, i48 => .{ .raw = q_nan | tag_int | makePayload(@bitCast(@as(i48, @intCast(data)))) },
            comptime_float, f64 => .{ .raw = @bitCast(@as(f64, data)) },
            // TODO: add check to ensure that pointers only take up 48 bits
            *String, *List, *Map, *Closure, *Fiber => .{ .raw = q_nan | tag_object | makePayload(@intCast(@intFromPtr(data))) },
            *ForeignFn => .{ .raw = q_nan | tag_foreign_fn | makePayload(@intCast(@intFromPtr(data))) },
            else => switch (@typeInfo(@TypeOf(data))) {
                .Pointer => .{ .raw = q_nan | tag_foreign_data | makePayload(@intCast(@intFromPtr(data))) },
                else => throwInvalidTypeError(@TypeOf(data)),
            },
        };
    }

    pub fn cast(self: Value, comptime T: type) ?T {
        return switch (T) {
            bool => if (self.isBool()) self.toBool() else null,
            i48 => if (self.isInt()) self.toInt() else null,
            f64 => if (self.isFloat()) self.toFloat() else null,
            *String, *List, *Map, *Closure, *Fiber => if (self.isObject()) GC.cast(std.meta.Child(T), self.toPtr()) else null,
            *ForeignFn => if (self.isForeignFn()) @ptrCast(@alignCast(self.toPtr())) else null,
            else => if (self.isForeignData()) @ptrCast(@alignCast(self.toPtr())) else null,
        };
    }

    fn isBool(self: Value) bool {
        return self.raw & tag_true == tag_true or self.raw & tag_false == tag_false;
    }
    fn isFloat(self: Value) bool {
        return (self.raw & q_nan) != q_nan;
    }
    fn isInt(self: Value) bool {
        return !self.isFloat() and self.raw & tag_int == tag_int;
    }
    fn isString(self: Value) bool {
        return self.cast(*String) != null;
    }
    fn isObject(self: Value) bool {
        return !self.isFloat() and self.raw & tag_object == tag_object;
    }
    fn isForeignFn(self: Value) bool {
        return !self.isFloat() and self.raw & tag_foreign_fn == tag_foreign_fn;
    }
    fn isForeignData(self: Value) bool {
        return !self.isFloat() and self.raw & tag_foreign_data == tag_foreign_data;
    }

    fn toFloat(self: Value) f64 {
        return @bitCast(self.raw);
    }
    fn toInt(self: Value) i48 {
        return @as(i48, @bitCast(self.getPayload()));
    }
    fn toPtr(self: Value) *anyopaque {
        return @ptrFromInt(self.getPayload());
    }

    fn makePayload(data: u48) u64 {
        return @as(u64, @intCast(data)) << 2;
    }
    fn getPayload(self: Value) u48 {
        return @truncate(self.raw >> 2);
    }

    pub fn add(self: Value, other: Value) ?Value {
        return self.intOrFloatBinaryOp(other, intAdd, floatAdd);
    }
    pub fn sub(self: Value, other: Value) ?Value {
        return self.intOrFloatBinaryOp(other, intSub, floatSub);
    }
    pub fn mul(self: Value, other: Value) ?Value {
        return self.intOrFloatBinaryOp(other, intMul, floatMul);
    }
    pub fn div(self: Value, other: Value) ?Value {
        return self.intOrFloatBinaryOp(other, intDiv, floatDiv);
    }
    pub fn mod(self: Value, other: Value) ?Value {
        return self.intBinaryOp(other, intMod);
    }
    pub fn eq(self: Value, other: Value) ?Value {
        return init(self.isEqual(other));
    }
    pub fn neq(self: Value, other: Value) ?Value {
        return init(!self.isEqual(other));
    }
    pub fn lt(self: Value, other: Value) ?Value {
        return self.intBinaryOp(other, intLt);
    }
    pub fn le(self: Value, other: Value) ?Value {
        return self.intBinaryOp(other, intLe);
    }
    pub fn gt(self: Value, other: Value) ?Value {
        return self.intBinaryOp(other, intGt);
    }
    pub fn ge(self: Value, other: Value) ?Value {
        return self.intBinaryOp(other, intGe);
    }
    pub fn logAnd(self: Value, other: Value) ?Value {
        return boolBinaryOp(self, other, boolAnd);
    }
    pub fn logOr(self: Value, other: Value) ?Value {
        return boolBinaryOp(self, other, boolOr);
    }
    pub fn bitAnd(self: Value, other: Value) ?Value {
        return self.intBinaryOp(other, intBitAnd);
    }
    pub fn bitOr(self: Value, other: Value) ?Value {
        return self.intBinaryOp(other, intBitOr);
    }
    pub fn bitXor(self: Value, other: Value) ?Value {
        return self.intBinaryOp(other, intBitXor);
    }
    pub fn shl(self: Value, other: Value) ?Value {
        return self.intBinaryOp(other, intShiftLeft);
    }
    pub fn shr(self: Value, other: Value) ?Value {
        return self.intBinaryOp(other, intShiftRight);
    }
    pub fn pos(self: Value) ?Value {
        return self.intOrFloatUnaryOp(init, init);
    }
    pub fn neg(self: Value) ?Value {
        return self.intOrFloatUnaryOp(intNeg, floatNeg);
    }
    pub fn bitNot(self: Value) ?Value {
        return self.intUnaryOp(intBitNot);
    }
    pub fn logNot(self: Value) ?Value {
        return self.boolUnaryOp(boolNot);
    }

    fn intOrFloatBinaryOp(self: Value, other: Value, intOp: fn (i48, i48) Value, floatOp: fn (f64, f64) Value) ?Value {
        if (self.isInt() and other.isInt()) {
            return intOp(self.toInt(), other.toInt());
        } else if (self.isFloat() and other.isFloat()) {
            return floatOp(self.toFloat(), other.toFloat());
        } else {
            return null;
        }
    }
    fn intBinaryOp(self: Value, other: Value, op: fn (i48, i48) Value) ?Value {
        if (self.isInt() and other.isInt()) {
            return op(self.toInt(), other.toInt());
        } else {
            return null;
        }
    }
    fn boolBinaryOp(self: Value, other: Value, op: fn (bool, bool) Value) ?Value {
        if (self.isBool() and other.isBool()) {
            return op(self.toBool(), other.toBool());
        } else {
            return null;
        }
    }
    fn intOrFloatUnaryOp(self: Value, intOp: fn (i48) Value, floatOp: fn (f64) Value) ?Value {
        if (self.isInt()) {
            return intOp(self.toInt().?);
        } else if (self.isFloat()) {
            return floatOp(self.toFloat().?);
        } else {
            return null;
        }
    }
    fn intUnaryOp(self: Value, op: fn (i48) Value) ?Value {
        if (self.isInt()) {
            return op(self.toInt().?);
        } else {
            return null;
        }
    }
    fn boolUnaryOp(self: Value, op: fn (bool) Value) ?Value {
        if (self.isBool()) {
            return op(self.toBool().?);
        } else {
            return null;
        }
    }

    fn intAdd(left: i48, right: i48) Value {
        return init(left + right); // FIXME: check for overflow
    }
    fn intSub(left: i48, right: i48) Value {
        return init(left - right);
    }
    fn intMul(left: i48, right: i48) Value {
        return init(left * right); // FIXME: check for overflow
    }
    fn intDiv(left: i48, right: i48) Value {
        return init(@divTrunc(left, right));
    }
    fn intMod(left: i48, right: i48) Value {
        return init(@rem(left, right)); // FIXME: check for right < 0
    }
    fn intBitAnd(left: i48, right: i48) Value {
        return init(left & right);
    }
    fn intBitOr(left: i48, right: i48) Value {
        return init(left | right);
    }
    fn intBitXor(left: i48, right: i48) Value {
        return init(left ^ right);
    }
    fn intShiftLeft(left: i48, right: i48) Value {
        return init(left << @intCast(right)); // FIXME: check for right > max u6
    }
    fn intShiftRight(left: i48, right: i48) Value {
        return init(left >> @intCast(right)); // FIXME: check for right > max u6
    }
    fn intLt(left: i48, right: i48) Value {
        return init(left < right);
    }
    fn intLe(left: i48, right: i48) Value {
        return init(left <= right);
    }
    fn intGt(left: i48, right: i48) Value {
        return init(left > right);
    }
    fn intGe(left: i48, right: i48) Value {
        return init(left >= right);
    }
    fn intNeg(int: i48) Value {
        return init(-int);
    }
    fn intBitNot(int: i48) Value {
        return init(~int);
    }

    fn floatAdd(left: f64, right: f64) Value {
        return init(left + right);
    }
    fn floatSub(left: f64, right: f64) Value {
        return init(left - right);
    }
    fn floatMul(left: f64, right: f64) Value {
        return init(left * right);
    }
    fn floatDiv(left: f64, right: f64) Value {
        return init(left / right);
    }
    fn floatNeg(float: f64) Value {
        return init(-float);
    }

    fn boolAnd(left: bool, right: bool) Value {
        return init(left and right);
    }
    fn boolOr(left: bool, right: bool) Value {
        return init(left or right);
    }
    fn boolNot(b: bool) Value {
        return init(!b);
    }

    fn hash(self: Value) u64 {
        if (self.cast(*String)) |string| {
            return string.hash();
        }
        return self.raw;
    }

    fn isEqual(self: Value, other: Value) bool {
        if (self.cast(*String)) |string| {
            if (other.cast(*String)) |other_string| {
                if (self.raw != other.raw) {
                    return string.isEqual(other_string);
                }
            }
        }
        return self.raw == other.raw;
    }

    fn markIfObject(self: Value, gc: *GC) !void {
        if (self.isObject()) {
            try gc.mark(self.toPtr());
        }
    }
};

pub const String = struct {
    str: []const u8,

    pub fn init(allocator: std.mem.Allocator, str: []const u8) !String {
        return .{ .str = try allocator.dupe(u8, str) };
    }

    pub fn deinit(self: *String, allocator: std.mem.Allocator) void {
        allocator.free(self.str);
        self.* = undefined;
    }

    pub fn concat(allocator: std.mem.Allocator, gc: *GC, left: *const String, right: *const String) *String {
        const str = try std.mem.concat(allocator, u8, &.{ left.str, right.str });
        const string = try gc.create(String);
        string.* = String.init(str);
        return string;
    }

    fn hash(self: String) u64 {
        return std.hash.Wyhash.hash(0, self.str);
    }

    fn isEqual(self: String, other: String) bool {
        return std.mem.eql(u8, self.str, other.str);
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

pub const ValueContext = struct {
    pub fn hash(self: ValueContext, key: Value) u64 {
        _ = self;

        return key.hash();
    }

    pub fn eql(self: ValueContext, left: Value, right: Value) bool {
        _ = self;

        return left.isEqual(right);
    }
};

pub const Closure = struct {
    chunk: *Chunk,
    upvalues: []*Upvalue,

    pub fn init(chunk: *Chunk, upvalues: []*Upvalue) Closure {
        return .{ .chunk = chunk, .upvalues = upvalues };
    }

    pub fn deinit(self: *Closure, allocator: std.mem.Allocator) void {
        allocator.free(self.upvalues);
        self.* = undefined;
    }

    pub fn mark(self: *Closure, gc: *GC) !void {
        try gc.mark(self.chunk);
        for (self.upvalues) |upvalue| {
            try upvalue.mark(gc);
        }
    }
};

pub const Upvalue = struct {
    value: *Value,
    closed_value: ?Value = null,

    pub fn mark(self: *Upvalue, gc: *GC) !void {
        try self.value.markIfObject(gc);
    }
};

pub const ForeignFn = struct {
    entry_fn: *const fn (ctx: *Context) Result,
    fns: []*const fn (ctx: *Context) Result,

    pub const Context = struct {
        allocator: std.mem.Allocator,
        gc: *GC,
        curr_fiber: *Fiber,
        state: ?*anyopaque = null,
    };

    pub const Result = union(enum) {
        ret: Value,
        yield: Value,
        err: Value,
    };
};

fn throwInvalidTypeError(comptime T: type) noreturn {
    @compileError(@typeName(T) ++ " is not a valid type for a Doji value");
}
