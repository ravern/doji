const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Wyhash = std.hash.Wyhash;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const HashMapUnmanaged = std.HashMapUnmanaged;

const GcAllocator = @import("./gc.zig").GcAllocator;
const Chunk = @import("./bytecode.zig").Chunk;
const Fiber = @import("./fiber.zig").Fiber;

const q_nan = 0x7ffc000000000000;

const tag_true = 0x1;
const tag_false = 0x2;
const tag_int = 0x3;

const tag_object = 0x8000000000000000;

const val_nil = Value{ .raw = q_nan };
const val_true = Value{ .raw = q_nan | tag_true };
const val_false = Value{ .raw = q_nan | tag_false };

pub const Value = extern union {
    pub const nil = val_nil;

    raw: u64,
    float: f64,

    pub fn initBool(b: bool) Value {
        return if (b) val_true else val_false;
    }

    pub fn initInt(int: i48) Value {
        const int64 = @as(u64, @bitCast(@as(i64, @intCast(int)) << @bitSizeOf(u2)));
        return Value{ .raw = q_nan | tag_int | int64 };
    }

    pub fn initFloat(float: f64) Value {
        const val = Value{ .float = float };
        assert(val.isFloat());
        return val;
    }

    pub fn initString(allocator: Allocator, string: []const u8) !Value {
        const object = try allocator.create(Object);
        object.* = Object{ .String = String{ .string = string } };
        return initObject(object);
    }

    pub fn initList(allocator: Allocator) !Value {
        const object = try allocator.create(Object);
        object.* = Object{ .List = List{} };
        return initObject(object);
    }

    pub fn initMap(allocator: Allocator) !Value {
        const object = try allocator.create(Object);
        object.* = Object{ .Map = Map{} };
        return initObject(object);
    }

    fn initObject(object: *const Object) !Value {
        return Value{ .raw = q_nan | tag_object | @intFromPtr(object) };
    }

    pub fn isNil(self: Value) bool {
        return self.raw == val_nil.raw;
    }

    pub fn isBool(self: Value) bool {
        return self.raw == val_true.raw or self.raw == val_false.raw;
    }

    pub fn isInt(self: Value) bool {
        return !self.isFloat() and !self.isObject() and (self.raw & tag_int) == tag_int;
    }

    pub fn isFloat(self: Value) bool {
        return (self.raw & q_nan) != q_nan;
    }

    pub fn isString(self: Value) bool {
        return self.isObject() and switch (self.asObject().*) {
            .String => true,
            else => false,
        };
    }

    pub fn isList(self: Value) bool {
        return self.isObject() and switch (self.asObject().*) {
            .List => true,
            else => false,
        };
    }

    pub fn isMap(self: Value) bool {
        return self.isObject() and switch (self.asObject().*) {
            .Map => true,
            else => false,
        };
    }

    pub fn isClosure(self: Value) bool {
        return self.isObject() and switch (self.asObject().*) {
            .Closure => true,
            else => false,
        };
    }

    pub fn isFiber(self: Value) bool {
        return self.isObject() and switch (self.asObject().*) {
            .Fiber => true,
            else => false,
        };
    }

    fn isObject(self: Value) bool {
        return !self.isFloat() and (self.raw & tag_object) == tag_object;
    }

    pub fn asBool(self: Value) bool {
        assert(self.isBool());
        return self.raw == val_true.raw;
    }

    pub fn asInt(self: Value) i64 {
        assert(self.isInt());
        return @as(i64, @bitCast((self.raw ^ q_nan) >> @bitSizeOf(u2)));
    }

    pub fn asFloat(self: Value) f64 {
        assert(self.isFloat());
        return self.float;
    }

    pub fn asString(self: Value) *String {
        assert(self.isString());
        return &self.asObject().String;
    }

    fn asObject(self: Value) *Object {
        assert(self.isObject());
        return @ptrFromInt(self.raw ^ q_nan ^ tag_object);
    }

    fn hash(self: Value) u64 {
        if (self.isString()) {
            return Wyhash.hash(0, self.asString().string);
        }
        return Wyhash.hash(0, mem.asBytes(&self.raw));
    }

    pub fn eql(self: Value, other: Value) bool {
        if (self.raw == other.raw) {
            return true;
        }
        if (self.isFloat() and other.isFloat()) {
            return self.asFloat() == other.asFloat();
        }
        // If the strings are both interned, the raw case would've returned already. So we
        // compare the actual strings to check for equality instead.
        if (self.isString() and other.isString()) {
            return mem.eql(u8, self.asString().string, other.asString().string);
        }
        return false;
    }
};

const Object = union(enum) {
    String: String,
    List: List,
    Map: Map,
    Closure: Closure,
    Fiber: Fiber,
};

pub const String = struct {
    string: []const u8,
};

pub const List = struct {
    vals: ArrayListUnmanaged(Value) = .{},
};

pub const Map = struct {
    entries: ValueHashMapUnmanaged(Value) = .{},
};

pub const Closure = struct {
    function: *Function,
    upvals: []*Upvalue,
};

pub const Function = struct {
    arity: usize,
    chunk: *Chunk,
};

pub const Upvalue = struct {
    val: union(enum) {
        Open: *Value,
        Closed: Value,
    },
    next: ?*Upvalue,
};

pub fn ValueHashMapUnmanaged(comptime V: type) type {
    return std.HashMapUnmanaged(Value, V, ValueKeyContext, 80);
}

const ValueKeyContext = struct {
    const Self = @This();

    pub fn hash(self: Self, key: Value) u64 {
        _ = self;
        return key.hash();
    }

    pub fn eql(self: Self, left_key: Value, right_key: Value) bool {
        _ = self;
        return left_key.eql(right_key);
    }
};

test "sizeOf" {
    try testing.expectEqual(@sizeOf(Value), @sizeOf(usize));
}

test "ValueHashMapUnmanaged" {
    var gc_allocator = GcAllocator.init(testing.allocator);
    defer gc_allocator.deinit();
    const allocator = gc_allocator.allocator();
    var map = ValueHashMapUnmanaged(usize){};
    const one = Value.initInt(123);
    const two = Value.initInt(456);
    const three = Value.initFloat(3.14159);
    const four = Value.initFloat(6.28318);
    const five = try Value.initString(allocator, "foo");
    const six = try Value.initString(allocator, "bar");
    const other_six_string = try allocator.alloc(u8, six.asString().string.len);
    mem.copyForwards(u8, other_six_string, "bar");
    const other_six = try Value.initString(allocator, other_six_string);
    try map.put(allocator, one, 1);
    try map.put(allocator, two, 2);
    try map.put(allocator, three, 3);
    try map.put(allocator, four, 4);
    try map.put(allocator, five, 5);
    try map.put(allocator, six, 6);
    try testing.expectEqual(map.get(one), 1);
    try testing.expectEqual(map.get(two), 2);
    try testing.expectEqual(map.get(three), 3);
    try testing.expectEqual(map.get(four), 4);
    try testing.expectEqual(map.get(five), 5);
    try testing.expectEqual(map.get(six), 6);
    try testing.expect(six.asString().string.ptr != other_six.asString().string.ptr);
    try testing.expectEqual(map.get(other_six), 6);
}

test "nil" {
    const val = Value.nil;
    try testing.expect(val.isNil());
}

test "bool" {
    const val = Value.initBool(true);
    try testing.expect(val.isBool());
    const b = val.asBool();
    try testing.expect(b);
}

test "int" {
    const val = Value.initInt(123);
    try testing.expect(val.isInt());
    const int = val.asInt();
    try testing.expectEqual(123, int);
}

test "int.large" {
    const val = Value.initInt(123456);
    try testing.expect(val.isInt());
    const int = val.asInt();
    try testing.expectEqual(123456, int);
}

test "float" {
    const val = Value.initFloat(3.14159);
    try testing.expect(val.isFloat());
    const float = val.asFloat();
    try testing.expectEqual(3.14159, float);
}

test "string" {
    var gc_allocator = GcAllocator.init(testing.allocator);
    defer gc_allocator.deinit();
    const allocator = gc_allocator.allocator();
    const val = try Value.initString(allocator, "Doji is cool!");
    try testing.expect(val.isString());
    const string = val.asString();
    try testing.expectEqual("Doji is cool!", string.string);
}
