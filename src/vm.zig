const std = @import("std");
const code = @import("code.zig");
const compile = @import("compile.zig");
const GC = @import("gc.zig").GC;
const MockMutator = @import("gc.zig").MockMutator;
const Value = @import("value.zig").Value;
const String = @import("value.zig").String;
const List = @import("value.zig").List;
const Map = @import("value.zig").Map;
const ErrorValue = @import("value.zig").Error;
const Closure = @import("value.zig").Closure;
const Upvalue = @import("value.zig").Upvalue;
const Fiber = @import("value.zig").Fiber;
const ForeignFn = @import("value.zig").ForeignFn;
const prelude = @import("prelude.zig");
const Resolver = @import("resolver.zig").Resolver;
const MockResolver = @import("resolver.zig").MockResolver;
const Source = @import("source.zig").Source;

pub const VM = struct {
    allocator: std.mem.Allocator,
    gc: GC,
    fiber: *Fiber,
    string_pool: StringPool,
    globals: std.ArrayList(*String),
    foreign_fn_registry: ForeignFnRegistry,
    resolver: Resolver,

    pub const Error = error{
        OutOfMemory,
        CorruptedBytecode,
        TODO,
    };

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

    pub fn init(allocator: std.mem.Allocator, resolver: Resolver) !*VM {
        var self = try allocator.create(VM);
        self.* = .{
            .allocator = allocator,
            .gc = GC.init(allocator, self.mutator()),
            .fiber = undefined,
            .string_pool = undefined,
            .globals = std.ArrayList(*String).init(self.allocator),
            .foreign_fn_registry = ForeignFnRegistry.init(self.allocator),
            .resolver = resolver,
        };

        self.string_pool = StringPool.init(self.allocator, &self.gc);

        return self;
    }

    pub fn deinit(self: *VM) void {
        self.gc.deinit();
        self.string_pool.deinit();
        self.foreign_fn_registry.deinit();
        self.allocator.destroy(self);
    }

    pub fn registerForeignFn(self: *VM, identifier: []const u8, foreign_fn: *const ForeignFn) !void {
        try self.foreign_fn_registry.register(identifier, foreign_fn);
    }

    pub fn evaluate(self: *VM, source: *const Source) !Value {
        var compile_ctx = compile.Context{
            .allocator = self.allocator,
            .gc = &self.gc,
            .string_pool = &self.string_pool,
            .globals = &self.globals,
            .source = source,
        };
        var compile_err: compile.Error = undefined;
        const chunk = compile.compile(&compile_ctx, &compile_err) catch |err| {
            switch (err) {
                error.CompileFailed => {
                    std.debug.print("compile error: unexpected: {any}, expected: {any}\n", .{ compile_err.data.parse.unexpected, compile_err.data.parse.expected });
                    // TODO: transform compile error into error value
                    unreachable;
                },
                else => return err,
            }
        };

        const root_closure = try self.gc.create(Closure);
        root_closure.* = .{ .chunk = chunk, .upvalues = &.{} };

        self.fiber = try self.gc.create(Fiber);
        self.fiber.* = try Fiber.init(self.allocator, root_closure, .{ .path = "vm.zig", .location = Source.Location.zero });

        while (true) {
            const step = self.fiber.advance() orelse return Error.CorruptedBytecode;
            switch (step) {
                .instruction => |inst| switch (inst.op) {
                    .nop => {},

                    .true => try self.fiber.push(self.allocator, Value.init(true)),
                    .false => try self.fiber.push(self.allocator, Value.init(false)),
                    .int => try self.fiber.push(self.allocator, Value.init(@as(i48, @intCast(inst.arg)))),
                    .constant => {
                        const value = self.fiber.getConstant(@intCast(inst.arg)) orelse return Error.CorruptedBytecode;
                        try self.fiber.push(self.allocator, value);
                    },
                    .foreign_fn => {
                        const foreign_fn = self.foreign_fn_registry.get(@intCast(inst.arg)) orelse return Error.CorruptedBytecode;
                        try self.fiber.push(self.allocator, Value.init(foreign_fn));
                    },

                    .add => try self.fiber.push(self.allocator, try self.binaryOp(Value.add)),
                    .sub => try self.fiber.push(self.allocator, try self.binaryOp(Value.sub)),
                    .mul => try self.fiber.push(self.allocator, try self.binaryOp(Value.mul)),
                    .div => try self.fiber.push(self.allocator, try self.binaryOp(Value.div)),

                    .is_error => {
                        const value = self.fiber.pop() orelse return Error.CorruptedBytecode;
                        try self.fiber.push(self.allocator, Value.init(value.cast(*ErrorValue) != null));
                    },

                    .call => try self.call(@intCast(inst.arg)),
                    .ret => return self.fiber.pop() orelse return Error.CorruptedBytecode,
                },
                .step_fn => |step_fn| {
                    const result = try step_fn(.{
                        .allocator = self.allocator,
                        .fiber = self.fiber,
                        .gc = &self.gc,
                        .string_pool = &self.string_pool,
                    });
                    switch (result) {
                        .ret => {
                            _ = self.fiber.popFrame();
                            try self.fiber.push(self.allocator, result.ret);
                        },
                        .call => {
                            const closure_value = self.fiber.getFromTop(result.call) orelse return Error.TODO;
                            const closure = closure_value.cast(*Closure) orelse return Error.TODO;
                            const trace_item = self.fiber.getCurrentTraceItem() orelse return Error.CorruptedBytecode;
                            try self.fiber.pushClosureFrame(self.allocator, closure, trace_item);
                        },
                    }
                },
            }
        }

        return Value.nil;
    }

    fn binaryOp(self: *VM, op: fn (Value, Value) ?Value) !Value {
        const right = self.fiber.pop() orelse return Error.CorruptedBytecode;
        const left = self.fiber.pop() orelse return Error.CorruptedBytecode;
        return op(left, right) orelse Error.TODO;
    }

    fn call(self: *VM, arity: usize) !void {
        const callable = self.fiber.getFromTop(arity) orelse return Error.CorruptedBytecode;
        const trace_item = self.fiber.getCurrentTraceItem() orelse return Error.CorruptedBytecode;
        if (callable.cast(*const ForeignFn)) |foreign_fn| {
            if (foreign_fn.arity != arity) return Error.TODO;
            try self.fiber.pushForeignFnFrame(self.allocator, foreign_fn, trace_item);
        } else {
            return Error.CorruptedBytecode;
        }
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
            .err => @as(*ErrorValue, @ptrCast(@alignCast(data))).trace(tracer),
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
            .err => @as(*ErrorValue, @ptrCast(@alignCast(data))).deinit(self.allocator),
            .closure => @as(*Closure, @ptrCast(@alignCast(data))).deinit(self.allocator),
            .fiber => @as(*Fiber, @ptrCast(@alignCast(data))).deinit(self.allocator),
            .chunk => @as(*code.Chunk, @ptrCast(@alignCast(data))).deinit(self.allocator),
            .upvalue => {},
        }
    }
};

test VM {
    const allocator = std.testing.allocator;

    var resolver = MockResolver{};

    var vm = try VM.init(allocator, resolver.resolver());
    defer vm.deinit();

    try vm.registerForeignFn("add", prelude.add_foreign_fn);

    const result = try vm.evaluate(&.{ .path = "<stdin>", .content = "123" });
    try std.testing.expectEqual(123, result.cast(i48).?);
}

pub const StringPool = struct {
    gc: *GC,
    data: std.StringHashMap(*String),

    pub fn init(allocator: std.mem.Allocator, gc: *GC) StringPool {
        return .{
            .gc = gc,
            .data = std.StringHashMap(*String).init(allocator),
        };
    }

    pub fn deinit(self: *StringPool) void {
        self.data.deinit();
    }

    pub fn intern(self: *StringPool, str: []const u8) !*String {
        const result = try self.data.getOrPut(str);
        if (!result.found_existing) {
            result.value_ptr.* = try self.gc.create(String);
            result.value_ptr.*.* = String.init(str);
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

    const string_one = try pool.intern("one");
    const string_two = try pool.intern("one");
    const string_three = try pool.intern("three");

    try std.testing.expect(String.eql(string_one, string_two));
    try std.testing.expect(!String.eql(string_one, string_three));
}

pub const ForeignFnRegistry = struct {
    indices: std.StringHashMap(usize),
    data: std.ArrayList(*const ForeignFn),

    pub fn init(allocator: std.mem.Allocator) ForeignFnRegistry {
        return .{
            .indices = std.StringHashMap(usize).init(allocator),
            .data = std.ArrayList(*const ForeignFn).init(allocator),
        };
    }

    pub fn deinit(self: *ForeignFnRegistry) void {
        self.indices.deinit();
        self.data.deinit();
    }

    pub fn register(self: *ForeignFnRegistry, identifier: []const u8, foreign_fn: *const ForeignFn) !void {
        try self.data.append(foreign_fn);
        try self.indices.put(identifier, self.data.items.len - 1);
    }

    pub fn getIndex(self: *ForeignFnRegistry, name: []const u8) ?usize {
        return self.indices.get(name);
    }

    pub fn get(self: *ForeignFnRegistry, index: usize) ?*const ForeignFn {
        return self.data.items[index];
    }
};
