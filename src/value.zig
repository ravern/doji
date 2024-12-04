const std = @import("std");
const code = @import("code.zig");
const GC = @import("gc.zig").GC;

pub const Value = struct {
    raw: u64,

    const q_nan: u64 = 0x7ffc000000000000;

    const Tag = enum(u64) {
        nil = 0x0000000000000000,
        true = 0x0000000000000001,
        false = 0x0000000000000002,
        int = 0x0000000000000003,
        gc_object = 0x8000000000000000,
        foreign_fn = 0x8000000000000001,

        const num_bits_prefix = 1;
        const num_bits_suffix = 2;
    };

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

    pub const nil = Value{ .raw = q_nan | @intFromEnum(Tag.nil) };

    pub fn init(data: anytype) Value {
        const T = @TypeOf(data);
        return switch (T) {
            bool => Value{ .raw = q_nan | (if (data) @intFromEnum(Tag.true) else @intFromEnum(Tag.false)) },
            comptime_float, f64 => Value{ .raw = @bitCast(@as(f64, @floatCast(data))) },
            comptime_int, i48 => Value{ .raw = q_nan | @intFromEnum(Tag.int) | rawFromInt(@intCast(data)) },
            *String, *List, *Map, *Closure, *Fiber => Value{ .raw = q_nan | @intFromEnum(Tag.gc_object) | rawFromPtr(data) },
            *ForeignFn => Value{ .raw = q_nan | @intFromEnum(Tag.foreign_fn) | rawFromPtr(data) },
            else => invalidValueTypeError(T),
        };
    }

    pub fn cast(self: Value, comptime T: type) ?T {
        return switch (T) {
            bool => if (!self.isFloat() and (self.hasTag(.true) or self.hasTag(.false))) self.hasTag(.true) else null,
            f64 => if (self.isFloat()) @bitCast(self.raw) else null,
            i48 => if (!self.isFloat() and self.hasTag(.int)) intFromRaw(self.raw) else null,
            *String, *List, *Map, *Closure, *Fiber => if (!self.isFloat() and self.hasTag(.gc_object)) @ptrCast(@alignCast(ptrFromRaw(self.raw))) else null,
            *ForeignFn => if (!self.isFloat() and self.hasTag(.foreign_fn)) @ptrCast(@alignCast(ptrFromRaw(self.raw))) else null,
            else => invalidValueTypeError(T),
        };
    }

    pub fn trace(self: Value, tracer: *GC.Tracer) !void {
        if (self.hasTag(.gc_object)) try tracer.trace(ptrFromRaw(self.raw));
    }

    inline fn isFloat(self: Value) bool {
        return (self.raw & q_nan) != q_nan;
    }

    inline fn hasTag(self: Value, tag: Tag) bool {
        return (self.raw & @intFromEnum(tag)) == @intFromEnum(tag);
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
        return @as(u64, @intCast(data)) << Tag.num_bits_suffix;
    }

    inline fn dataFromRaw(raw: u64) u48 {
        return @truncate(raw >> Tag.num_bits_suffix);
    }
};

fn invalidValueTypeError(comptime T: type) noreturn {
    @compileError(@typeName(T) ++ " is not a valid type for Value");
}

test Value {
    var string: String = undefined;
    var list: List = undefined;
    var map: Map = undefined;
    var fiber: Fiber = undefined;
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

    try std.testing.expectEqual(&fiber, Value.init(&fiber).cast(*Fiber).?);

    try std.testing.expectEqual(&foreign_fn, Value.init(&foreign_fn).cast(*ForeignFn).?);

    // negative tests

    try std.testing.expectEqual(null, Value.init(true).cast(i48));
    try std.testing.expectEqual(null, Value.init(32).cast(f64));
    try std.testing.expectEqual(null, Value.init(3.14159).cast(i48));
    try std.testing.expectEqual(null, Value.init(&string).cast(i48));
    try std.testing.expectEqual(null, Value.init(&list).cast(i48));
    try std.testing.expectEqual(null, Value.init(&map).cast(i48));
    try std.testing.expectEqual(null, Value.init(&fiber).cast(i48));
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
    data: std.ArrayListUnmanaged(Value),

    pub fn deinit(self: *List, allocator: std.mem.Allocator) void {
        self.data.deinit(allocator);
        self.* = undefined;
    }

    pub fn trace(self: *const List, tracer: *GC.Tracer) !void {
        for (self.data.items) |item| {
            try item.trace(tracer);
        }
    }
};

pub const Map = struct {
    data: std.HashMapUnmanaged(Value, Value, Value.HashMapContext, 80),

    pub fn deinit(self: *Map, allocator: std.mem.Allocator) void {
        self.data.deinit(allocator);
        self.* = undefined;
    }

    pub fn trace(self: *const Map, tracer: *GC.Tracer) !void {
        var it = self.data.iterator();
        while (it.next()) |entry| {
            try entry.key_ptr.*.trace(tracer);
            try entry.value_ptr.*.trace(tracer);
        }
    }
};

pub const Closure = struct {
    chunk: *const code.Chunk,
    upvalues: []*Upvalue,

    pub fn deinit(self: *Closure, allocator: std.mem.Allocator) void {
        allocator.free(self.upvalues);
        self.* = undefined;
    }

    pub fn trace(self: *const Closure, tracer: *GC.Tracer) !void {
        try self.chunk.trace(tracer);
        for (self.upvalues) |upvalue| {
            try upvalue.trace(tracer);
        }
    }
};

pub const Upvalue = struct {
    value: *Value,
    closed_value: Value = Value.nil,
    next: ?*Upvalue = null,

    pub fn trace(self: *const Upvalue, tracer: *GC.Tracer) !void {
        try self.value.trace(tracer);
    }

    pub fn close(self: *Upvalue) void {
        self.closed_value = self.value.*;
        self.value = &self.closed_value;
    }
};

test Upvalue {
    var value = Value.init(1);
    var upvalue = Upvalue{ .value = &value };
    try std.testing.expectEqual(&value, upvalue.value);
    upvalue.close();
    try std.testing.expectEqual(&upvalue.closed_value, upvalue.value);
}

pub const Fiber = struct {
    stack: std.ArrayListUnmanaged(Value),
    call_stack: std.ArrayListUnmanaged(CallFrame),
    parent: ?*Fiber = null,

    const default_stack_size = 1024;

    pub const CallFrame = struct {
        closure: *Closure,
        chunk: *const code.Chunk, // saves a pointer lookup each step
        ip: [*]const code.Instruction,
        bp_index: usize,
    };

    pub fn init(allocator: std.mem.Allocator, closure: *Closure) !Fiber {
        var self = Fiber{
            .stack = try std.ArrayListUnmanaged(Value).initCapacity(allocator, default_stack_size),
            .call_stack = try std.ArrayListUnmanaged(CallFrame).initCapacity(allocator, 1),
        };

        try self.call_stack.append(allocator, .{
            .closure = closure,
            .chunk = closure.chunk,
            .ip = closure.chunk.code.ptr,
            .bp_index = 0,
        });

        return self;
    }

    pub fn deinit(self: *Fiber, allocator: std.mem.Allocator) void {
        self.stack.deinit(allocator);
        self.call_stack.deinit(allocator);
        self.* = undefined;
    }

    pub fn trace(self: *const Fiber, tracer: *GC.Tracer) !void {
        for (self.stack.items) |value| {
            try value.trace(tracer);
        }
        for (self.call_stack.items) |frame| {
            try frame.chunk.trace(tracer);
        }
    }

    pub fn push(self: *Fiber, allocator: std.mem.Allocator, value: Value) !void {
        try self.stack.append(allocator, value);
    }

    pub fn pop(self: *Fiber) ?Value {
        return self.stack.popOrNull();
    }

    pub fn pushFrame(self: *Fiber, allocator: std.mem.Allocator, closure: *Closure) !void {
        try self.call_stack.append(allocator, .{
            .closure = closure,
            .chunk = closure.chunk,
            .ip = closure.chunk.code.ptr,
            // FIXME: assumes arity has been checked
            .bp_index = self.stack.items.len - closure.chunk.arity,
        });
    }

    pub fn popFrame(self: *Fiber) ?CallFrame {
        if (self.call_stack.items.len == 1) return null;
        return self.call_stack.pop();
    }

    pub fn get(self: *const Fiber, index: usize) ?Value {
        return self.stack.items[self.getCurrentFrame().bp_index + index];
    }

    pub fn getRoot(self: *Fiber) *Fiber {
        var curr_fiber = self;
        while (curr_fiber.parent) |parent_fiber| {
            curr_fiber = parent_fiber;
        }
        return curr_fiber;
    }

    pub fn advance(self: *Fiber) ?code.Instruction {
        const frame = self.getCurrentFrame();
        const inst = frame.ip[0];
        frame.ip += 1;
        return inst;
    }

    fn getCurrentFrame(self: *const Fiber) *CallFrame {
        // call stack is always non-empty
        return &self.call_stack.items[self.call_stack.items.len - 1];
    }
};

test Fiber {
    const allocator = std.testing.allocator;

    const chunk_one = code.Chunk{ .arity = 0, .code = &.{}, .constants = &.{}, .chunks = &.{} };
    const chunk_two = code.Chunk{ .arity = 1, .code = &.{}, .constants = &.{}, .chunks = &.{} };
    const chunk_three = code.Chunk{ .arity = 2, .code = &.{.{ .op = .ret }}, .constants = &.{}, .chunks = &.{} };

    var closure_one = Closure{ .chunk = &chunk_one, .upvalues = &.{} };
    var closure_two = Closure{ .chunk = &chunk_two, .upvalues = &.{} };
    var closure_three = Closure{ .chunk = &chunk_three, .upvalues = &.{} };

    var fiber = try Fiber.init(allocator, &closure_one);
    defer fiber.deinit(allocator);

    try fiber.push(allocator, Value.init(1));
    try fiber.push(allocator, Value.init(2));

    try std.testing.expectEqual(Value.init(1), fiber.get(0).?);
    try std.testing.expectEqual(Value.init(2), fiber.get(1).?);

    try fiber.pushFrame(allocator, &closure_two);

    try fiber.push(allocator, Value.init(3));

    try std.testing.expectEqual(Value.init(2), fiber.get(0).?);
    try std.testing.expectEqual(Value.init(3), fiber.pop().?);

    _ = fiber.popFrame().?;

    try std.testing.expectEqual(Value.init(1), fiber.get(0).?);
    try std.testing.expectEqual(Value.init(2), fiber.get(1).?);

    try fiber.pushFrame(allocator, &closure_three);

    try std.testing.expectEqual(.ret, fiber.advance().?.op);

    try fiber.push(allocator, Value.init(4));

    try std.testing.expectEqual(Value.init(1), fiber.get(0).?);
    try std.testing.expectEqual(Value.init(2), fiber.get(1).?);
    try std.testing.expectEqual(Value.init(4), fiber.get(2).?);

    var fiber_parent = try Fiber.init(allocator, &closure_one);
    defer fiber_parent.deinit(allocator);
    fiber.parent = &fiber_parent;

    var fiber_parent_parent = try Fiber.init(allocator, &closure_one);
    defer fiber_parent_parent.deinit(allocator);
    fiber_parent.parent = &fiber_parent_parent;

    try std.testing.expectEqual(&fiber_parent_parent, fiber.getRoot());
}

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
