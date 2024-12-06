const std = @import("std");
const code = @import("code.zig");
const compile = @import("compile.zig");
const GC = @import("gc.zig").GC;
const MockMutator = @import("gc.zig").MockMutator;
const Value = @import("value.zig").Value;
const String = @import("value.zig").String;
const List = @import("value.zig").List;
const Map = @import("value.zig").Map;
const Closure = @import("value.zig").Closure;
const Upvalue = @import("value.zig").Upvalue;
const Fiber = @import("value.zig").Fiber;
const Source = @import("source.zig").Source;

pub const VM = struct {
    allocator: std.mem.Allocator,
    gc: GC,
    fiber: *Fiber,
    string_pool: StringPool,

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
            .string_pool = undefined,
        };

        self.string_pool = StringPool.init(self.allocator, &self.gc);

        return self;
    }

    pub fn deinit(self: *VM) void {
        self.gc.deinit();
        self.allocator.destroy(self);
    }

    pub fn evaluate(self: *VM, source: *const Source) !Value {
        const compile_ctx = compile.Context{ .allocator = self.allocator, .gc = &self.gc, .string_pool = &self.string_pool, .globals = &.{} };
        const compile_result = try compile.compile(compile_ctx, source);

        const closure = try self.gc.create(Closure);
        closure.* = .{ .chunk = compile_result.chunk, .upvalues = &.{} };
        self.fiber = try self.gc.create(Fiber);
        self.fiber.* = try Fiber.init(self.allocator, closure);

        while (true) {
            const inst = self.fiber.advance() orelse return error.CorruptedBytecode;
            switch (inst.op) {
                .int => {
                    const value = Value.init(@as(i48, @intCast(inst.arg)));
                    try self.fiber.push(self.allocator, value);
                },
                .constant => {
                    const value = self.fiber.getConstant(@intCast(inst.arg)) orelse return error.CorruptedBytecode;
                    try self.fiber.push(self.allocator, value);
                },
                .add => try self.fiber.push(self.allocator, try self.binaryOp(Value.add)),
                .sub => try self.fiber.push(self.allocator, try self.binaryOp(Value.sub)),
                .mul => try self.fiber.push(self.allocator, try self.binaryOp(Value.mul)),
                .div => try self.fiber.push(self.allocator, try self.binaryOp(Value.div)),
                .ret => return self.fiber.pop() orelse return error.CorruptedBytecode,
            }
        }

        return Value.nil;
    }

    fn binaryOp(self: *VM, op: fn (Value, Value) ?Value) !Value {
        const right = self.fiber.pop() orelse return error.CorruptedBytecode;
        const left = self.fiber.pop() orelse return error.CorruptedBytecode;
        return op(left, right) orelse return error.CorruptedBytecode;
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

    const result = try vm.evaluate(&.{ .path = .stdin, .content = "" });
    try std.testing.expectEqual(-57, result.cast(i48).?);
}

pub const StringPool = struct {
    gc: *GC,
    data: std.StringHashMap(Value),

    pub fn init(allocator: std.mem.Allocator, gc: *GC) StringPool {
        return .{
            .gc = gc,
            .data = std.StringHashMap(Value).init(allocator),
        };
    }

    pub fn deinit(self: *StringPool) void {
        self.data.deinit();
    }

    pub fn intern(self: *StringPool, str: []const u8) !Value {
        const result = try self.data.getOrPut(str);
        if (!result.found_existing) {
            const string = try self.gc.create(String);
            string.* = String.init(str);
            result.value_ptr.* = Value.init(string);
        }
        return result.value_ptr.*;
    }
};

test StringPool {
    const allocator = std.testing.allocator;

    var mutator = try MockMutator.init(allocator);
    defer mutator.deinit(allocator);

    var gc = GC.init(allocator, mutator.mutator());
    defer gc.deinit();

    var pool = StringPool.init(allocator, &gc);
    defer pool.deinit();

    const value_one = try pool.intern("one");
    const value_two = try pool.intern("one");
    const value_three = try pool.intern("three");

    try std.testing.expect(Value.eql(value_one, value_two));
    try std.testing.expect(!Value.eql(value_one, value_three));
}
