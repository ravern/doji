const std = @import("std");
const code = @import("code.zig");
const EmptyMutator = @import("gc.zig").MockMutator;
const GC = @import("root.zig").GC;
const Source = @import("source.zig").Source;
const StringPool = @import("vm.zig").StringPool;

pub const Value = struct {
    raw: u64,

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

    const q_nan: u64 = 0x7ffc000000000000;
    const tag_mask: u64 = 0x8000000000000003;

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

    pub const nil = Value{ .raw = q_nan | @intFromEnum(Tag.nil) };

    pub fn init(data: anytype) Value {
        const T = @TypeOf(data);
        return switch (T) {
            bool => Value{ .raw = q_nan | (if (data) @intFromEnum(Tag.true) else @intFromEnum(Tag.false)) },
            comptime_float, f64 => Value{ .raw = @bitCast(@as(f64, @floatCast(data))) },
            comptime_int, i48 => Value{ .raw = q_nan | @intFromEnum(Tag.int) | rawFromInt(@intCast(data)) },
            *String, *List, *Map, *Error, *Closure, *Fiber => Value{ .raw = q_nan | @intFromEnum(Tag.gc_object) | rawFromPtr(data) },
            *const ForeignFn => Value{ .raw = q_nan | @intFromEnum(Tag.foreign_fn) | rawFromPtr(@constCast(data)) },
            else => invalidValueTypeError(T),
        };
    }

    pub fn cast(self: Value, comptime T: type) ?T {
        return switch (T) {
            bool => if (!self.isFloat() and (self.hasTag(.true) or self.hasTag(.false))) self.hasTag(.true) else null,
            f64 => if (self.isFloat()) @bitCast(self.raw) else null,
            i48 => if (!self.isFloat() and self.hasTag(.int)) intFromRaw(self.raw) else null,
            *String, *List, *Map, *Error, *Closure, *Fiber => if (!self.isFloat() and self.hasTag(.gc_object) and GC.isType(@typeInfo(T).Pointer.child, ptrFromRaw(self.raw))) @ptrCast(@alignCast(ptrFromRaw(self.raw))) else null,
            *const ForeignFn => if (!self.isFloat() and self.hasTag(.foreign_fn)) @ptrCast(@alignCast(ptrFromRaw(self.raw))) else null,
            else => invalidValueTypeError(T),
        };
    }

    pub fn trace(self: Value, tracer: *GC.Tracer) !void {
        if (self.hasTag(.gc_object)) try tracer.trace(ptrFromRaw(self.raw));
    }

    pub fn eql(left: Value, right: Value) bool {
        if (left.raw != right.raw) {
            if (left.cast(*String)) |left_string| {
                if (right.cast(*String)) |right_string| {
                    return String.eql(left_string, right_string);
                }
            }
        }
        return left.raw == right.raw;
    }

    pub fn isNil(self: Value) bool {
        return self.eql(nil);
    }

    pub fn add(left: Value, right: Value) ?Value {
        return intOrFloatBinaryOp(left, right, addInt, addFloat);
    }
    pub fn sub(left: Value, right: Value) ?Value {
        return intOrFloatBinaryOp(left, right, subInt, subFloat);
    }
    pub fn mul(left: Value, right: Value) ?Value {
        return intOrFloatBinaryOp(left, right, mulInt, mulFloat);
    }
    pub fn div(left: Value, right: Value) ?Value {
        return intOrFloatBinaryOp(left, right, divInt, divFloat);
    }

    inline fn intOrFloatBinaryOp(left: Value, right: Value, comptime int_op: fn (i48, i48) i48, comptime float_op: fn (f64, f64) f64) ?Value {
        return intOp(left, right, int_op) orelse return floatOp(left, right, float_op);
    }
    inline fn intOp(left: Value, right: Value, comptime op: fn (i48, i48) i48) ?Value {
        if (left.cast(i48)) |left_int| {
            if (right.cast(i48)) |right_int| {
                return Value.init(op(left_int, right_int));
            }
        }
        return null;
    }
    inline fn floatOp(left: Value, right: Value, comptime op: fn (f64, f64) f64) ?Value {
        if (left.cast(f64)) |left_float| {
            if (right.cast(f64)) |right_float| {
                return Value.init(op(left_float, right_float));
            }
        }
        return null;
    }

    inline fn isFloat(self: Value) bool {
        return (self.raw & q_nan) != q_nan;
    }

    inline fn hasTag(self: Value, tag: Tag) bool {
        return (self.raw & tag_mask) == @intFromEnum(tag);
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

    pub fn format(self: Value, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (self.cast(bool)) |b| {
            try writer.print("{}", .{b});
        } else if (self.cast(i48)) |int| {
            try writer.print("{d}", .{int});
        } else if (self.cast(f64)) |float| {
            try writer.print("{d}", .{float});
        } else {
            try writer.print("{}", .{self.raw});
        }
    }
};

fn invalidValueTypeError(comptime T: type) noreturn {
    @compileError(@typeName(T) ++ " is not a valid type for Value");
}

test Value {
    const allocator = std.testing.allocator;

    var gc = GC.init(allocator);
    defer gc.deinit();

    const string = try gc.create(String);
    string.* = String.init("");
    const list = try gc.create(List);
    list.* = List.init();
    const map = try gc.create(Map);
    map.* = Map.init();
    const fiber = try gc.create(Fiber);
    fiber.* = Fiber.initEmpty();
    const foreign_fn: ForeignFn = undefined;

    // positive tests

    try std.testing.expectEqual(true, Value.init(true).cast(bool).?);
    try std.testing.expectEqual(false, Value.init(false).cast(bool).?);

    try std.testing.expectEqual(100, Value.init(100).cast(i48).?);
    try std.testing.expectEqual(-100, Value.init(-100).cast(i48).?);

    try std.testing.expectEqual(3.14159, Value.init(3.14159).cast(f64).?);
    try std.testing.expectEqual(-2.71828, Value.init(-2.71828).cast(f64).?);

    try std.testing.expectEqual(string, Value.init(string).cast(*String).?);
    try std.testing.expectEqual(list, Value.init(list).cast(*List).?);
    try std.testing.expectEqual(map, Value.init(map).cast(*Map).?);
    try std.testing.expectEqual(fiber, Value.init(fiber).cast(*Fiber).?);

    try std.testing.expectEqual(&foreign_fn, Value.init(&foreign_fn).cast(*const ForeignFn).?);

    // negative tests

    try std.testing.expectEqual(null, Value.init(true).cast(i48));
    try std.testing.expectEqual(null, Value.init(32).cast(f64));
    try std.testing.expectEqual(null, Value.init(3.14159).cast(i48));
    try std.testing.expectEqual(null, Value.init(string).cast(i48));
    try std.testing.expectEqual(null, Value.init(list).cast(i48));
    try std.testing.expectEqual(null, Value.init(map).cast(i48));
    try std.testing.expectEqual(null, Value.init(fiber).cast(i48));
    try std.testing.expectEqual(null, Value.init(&foreign_fn).cast(i48));
}

pub const String = struct {
    data: []const u8,
    hash: u64,

    pub fn init(data: []const u8) String {
        return .{
            .data = data,
            .hash = std.hash.Wyhash.hash(0, data),
        };
    }

    pub fn deinit(self: *String, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
        self.* = undefined;
    }

    pub fn eql(left: *String, right: *String) bool {
        return std.mem.eql(u8, left.data, right.data);
    }
};

pub const List = struct {
    data: std.ArrayListUnmanaged(Value) = .{},

    pub fn init() List {
        return .{};
    }

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
    data: std.HashMapUnmanaged(Value, Value, Value.HashMapContext, 80) = .{},

    pub fn init() Map {
        return .{};
    }

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

pub const Error = struct {
    message: *String,
    data: ?Value,
    stack_trace: std.ArrayListUnmanaged(TraceItem),

    pub const TraceItem = struct {
        path: []const u8,
        location: Source.Location,
    };

    pub fn init(allocator: std.mem.Allocator, message: *String, data: ?Value) !Error {
        return .{
            .message = message,
            .data = data,
            .stack_trace = try std.ArrayListUnmanaged(TraceItem).initCapacity(allocator, 10),
        };
    }

    pub fn deinit(self: *Error, allocator: std.mem.Allocator) void {
        self.stack_trace.deinit(allocator);
        self.* = undefined;
    }

    pub fn addTraceItem(self: *Error, allocator: std.mem.Allocator, item: TraceItem) !void {
        try self.stack_trace.append(allocator, item);
    }

    pub fn trace(self: *const Error, tracer: *GC.Tracer) !void {
        try tracer.trace(self.message);
        if (self.data) |data| {
            try data.trace(tracer);
        }
    }
};

pub const Closure = struct {
    chunk: *const code.Chunk,
    upvalues: []*Upvalue,

    pub fn init(chunk: *const code.Chunk, upvalues: []*Upvalue) !Closure {
        return .{ .chunk = chunk, .upvalues = upvalues };
    }

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

    pub fn deinit(self: *Upvalue, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.* = undefined;
    }

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
    stack: std.ArrayListUnmanaged(Value) = .{},
    call_stack: std.ArrayListUnmanaged(CallFrame) = .{},
    parent: ?*Fiber = null,

    const default_stack_size = 1024;

    pub const CallFrame = union(enum) {
        closure: ClosureCallFrame,
        foreign_fn: ForeignFnCallFrame,
    };

    pub const ClosureCallFrame = struct {
        closure: *Closure,
        chunk: *const code.Chunk, // saves a pointer lookup each step
        ip: [*]const code.Instruction,
        bp_index: usize,
        trace_item: Error.TraceItem,

        pub fn getIPIndex(self: *const @This()) usize {
            return (@intFromPtr(self.ip) - @intFromPtr(self.chunk.code.ptr)) / @sizeOf(code.Instruction);
        }
    };

    pub const ForeignFnCallFrame = struct {
        foreign_fn: *const ForeignFn,
        step_index: usize = 0,
        trace_item: Error.TraceItem,
    };

    pub const Step = union(enum) {
        instruction: code.Instruction,
        step_fn: ForeignFn.StepFn,
    };

    pub fn initEmpty() Fiber {
        return .{};
    }

    pub fn init(allocator: std.mem.Allocator, closure: *Closure, trace_item: Error.TraceItem) !Fiber {
        var self = Fiber{
            .stack = try std.ArrayListUnmanaged(Value).initCapacity(allocator, default_stack_size),
            .call_stack = try std.ArrayListUnmanaged(CallFrame).initCapacity(allocator, 1),
        };

        try self.call_stack.append(allocator, .{
            .closure = .{
                .closure = closure,
                .chunk = closure.chunk,
                .ip = closure.chunk.code.ptr,
                .bp_index = 0,
                .trace_item = trace_item,
            },
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
            switch (frame) {
                .closure => |closure_frame| try closure_frame.chunk.trace(tracer),
                .foreign_fn => {},
            }
        }
    }

    pub fn getRoot(self: *Fiber) *Fiber {
        var curr_fiber = self;
        while (curr_fiber.parent) |parent_fiber| {
            curr_fiber = parent_fiber;
        }
        return curr_fiber;
    }

    pub fn push(self: *Fiber, allocator: std.mem.Allocator, value: Value) !void {
        try self.stack.append(allocator, value);
    }

    pub fn pop(self: *Fiber) ?Value {
        return self.stack.popOrNull();
    }

    pub fn get(self: *const Fiber, index: usize) ?Value {
        const frame = self.getCurrentClosureFrame() orelse return null;
        return self.stack.items[frame.bp_index + index];
    }

    pub fn getFromTop(self: *const Fiber, index: usize) ?Value {
        return self.stack.items[self.stack.items.len - 1 - index];
    }

    pub fn pushClosureFrame(self: *Fiber, allocator: std.mem.Allocator, closure: *Closure, trace_item: Error.TraceItem) !void {
        try self.call_stack.append(allocator, .{
            .closure = .{
                .closure = closure,
                .chunk = closure.chunk,
                .ip = closure.chunk.code.ptr,
                // FIXME: assumes arity has been checked
                .bp_index = self.stack.items.len - closure.chunk.arity,
                .trace_item = trace_item,
            },
        });
    }

    pub fn pushForeignFnFrame(self: *Fiber, allocator: std.mem.Allocator, foreign_fn: *const ForeignFn, trace_item: Error.TraceItem) !void {
        try self.call_stack.append(allocator, .{
            .foreign_fn = .{
                .foreign_fn = foreign_fn,
                .trace_item = trace_item,
            },
        });
    }

    pub fn popFrame(self: *Fiber) ?CallFrame {
        if (self.call_stack.items.len == 1) return null;
        return self.call_stack.pop();
    }

    pub fn getConstant(self: *const Fiber, index: usize) ?Value {
        const frame = self.getCurrentClosureFrame() orelse return null;
        return frame.closure.chunk.constants[index];
    }

    pub fn advance(self: *Fiber) ?Step {
        const frame = self.getCurrentFrame();
        switch (frame.*) {
            .closure => {
                if (frame.closure.chunk.code.len == 0) return null;
                const inst = frame.closure.ip[0];
                frame.closure.ip += 1;
                return Step{ .instruction = inst };
            },
            .foreign_fn => {
                if (frame.foreign_fn.foreign_fn.step_fns.len == 0) return null;
                const step_fn = frame.foreign_fn.foreign_fn.step_fns[frame.foreign_fn.step_index];
                frame.foreign_fn.step_index += 1;
                return Step{ .step_fn = step_fn };
            },
        }
    }

    pub fn getCurrentTraceItem(self: *const Fiber) ?Error.TraceItem {
        const frame = self.getCurrentFrame();
        return switch (frame.*) {
            // TODO: potential out-of-bounds?
            .closure => .{
                .path = frame.closure.chunk.trace_items.path,
                .location = frame.closure.chunk.trace_items.locations[frame.closure.getIPIndex() - 1],
            },
            .foreign_fn => frame.foreign_fn.foreign_fn.trace_items[frame.foreign_fn.step_index - 1],
        };
    }

    inline fn getCurrentClosureFrame(self: *const Fiber) ?*ClosureCallFrame {
        const frame = self.getCurrentFrame();
        switch (frame.*) {
            .closure => return &frame.closure,
            .foreign_fn => return null,
        }
    }

    inline fn getCurrentFrame(self: *const Fiber) *CallFrame {
        // call stack is always non-empty
        return &self.call_stack.items[self.call_stack.items.len - 1];
    }
};

test Fiber {
    const allocator = std.testing.allocator;

    const trace_item = Error.TraceItem{ .path = "<test>", .location = Source.Location.zero };

    const chunk_one = code.Chunk{ .arity = 0, .code = &.{}, .constants = &.{}, .chunks = &.{}, .trace_items = .{ .path = "<test>", .locations = &.{} } };
    const chunk_two = code.Chunk{ .arity = 1, .code = &.{}, .constants = &.{}, .chunks = &.{}, .trace_items = .{ .path = "<test>", .locations = &.{} } };
    const chunk_three = code.Chunk{ .arity = 2, .code = &.{.{ .op = .ret }}, .constants = &.{}, .chunks = &.{}, .trace_items = .{ .path = "<test>", .locations = &.{} } };

    var closure_one = Closure{ .chunk = &chunk_one, .upvalues = &.{} };
    var closure_two = Closure{ .chunk = &chunk_two, .upvalues = &.{} };
    var closure_three = Closure{ .chunk = &chunk_three, .upvalues = &.{} };

    var fiber = try Fiber.init(allocator, &closure_one, trace_item);
    defer fiber.deinit(allocator);

    try fiber.push(allocator, Value.init(1));
    try fiber.push(allocator, Value.init(2));

    try std.testing.expectEqual(Value.init(1), fiber.get(0).?);
    try std.testing.expectEqual(Value.init(2), fiber.get(1).?);

    try fiber.pushClosureFrame(allocator, &closure_two, trace_item);

    try fiber.push(allocator, Value.init(3));

    try std.testing.expectEqual(Value.init(2), fiber.get(0).?);
    try std.testing.expectEqual(Value.init(3), fiber.pop().?);

    _ = fiber.popFrame().?;

    try std.testing.expectEqual(Value.init(1), fiber.get(0).?);
    try std.testing.expectEqual(Value.init(2), fiber.get(1).?);

    try fiber.pushClosureFrame(allocator, &closure_three, trace_item);

    try std.testing.expectEqual(.ret, fiber.advance().?.instruction.op);

    try fiber.push(allocator, Value.init(4));

    try std.testing.expectEqual(Value.init(1), fiber.get(0).?);
    try std.testing.expectEqual(Value.init(2), fiber.get(1).?);
    try std.testing.expectEqual(Value.init(4), fiber.get(2).?);

    var fiber_parent = try Fiber.init(allocator, &closure_one, trace_item);
    defer fiber_parent.deinit(allocator);
    fiber.parent = &fiber_parent;

    var fiber_parent_parent = try Fiber.init(allocator, &closure_one, trace_item);
    defer fiber_parent_parent.deinit(allocator);
    fiber_parent.parent = &fiber_parent_parent;

    try std.testing.expectEqual(&fiber_parent_parent, fiber.getRoot());
}

pub const ForeignFn = struct {
    arity: usize,
    step_fns: []const StepFn,
    trace_items: []const Error.TraceItem,

    pub const StepFn = *const fn (ctx: Context) anyerror!Result;

    pub const Context = struct {
        allocator: std.mem.Allocator,
        fiber: *Fiber,
        gc: *GC,
        string_pool: *StringPool,
    };

    pub const Result = union(enum) {
        ret: Value,
        call: usize,
    };
};

fn addInt(left: i48, right: i48) i48 {
    return left + right;
}
fn subInt(left: i48, right: i48) i48 {
    return left - right;
}
fn mulInt(left: i48, right: i48) i48 {
    return left * right;
}
fn divInt(left: i48, right: i48) i48 {
    return @divTrunc(left, right);
}

fn addFloat(left: f64, right: f64) f64 {
    return left + right;
}
fn subFloat(left: f64, right: f64) f64 {
    return left - right;
}
fn mulFloat(left: f64, right: f64) f64 {
    return left * right;
}
fn divFloat(left: f64, right: f64) f64 {
    return left / right;
}
