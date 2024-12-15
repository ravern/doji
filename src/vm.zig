const std = @import("std");
const code = @import("code.zig");
const compile = @import("compile.zig");
const prelude = @import("prelude.zig");
const Resolver = @import("resolver.zig").Resolver;
const MockResolver = @import("resolver.zig").MockResolver;
const GC = @import("root.zig").GC;
const Source = @import("source.zig").Source;
const StringPool = @import("string_pool.zig").StringPool;
const Value = @import("value.zig").Value;
const String = @import("value.zig").String;
const List = @import("value.zig").List;
const Map = @import("value.zig").Map;
const ErrorValue = @import("value.zig").Error;
const Closure = @import("value.zig").Closure;
const Upvalue = @import("value.zig").Upvalue;
const Fiber = @import("value.zig").Fiber;
const ForeignFn = @import("value.zig").ForeignFn;

pub const VM = struct {
    allocator: std.mem.Allocator,
    gc: *GC,
    string_pool: StringPool,
    foreign_fn_registry: ForeignFnRegistry,
    globals: std.ArrayList(*String),
    resolver: Resolver,

    pub const Error = error{
        OutOfMemory,
        CorruptedBytecode,
        TODO,
    };

    pub fn init(allocator: std.mem.Allocator, gc: *GC, resolver: Resolver) !VM {
        return .{
            .allocator = allocator,
            .gc = gc,
            .string_pool = StringPool.init(allocator, gc),
            .foreign_fn_registry = ForeignFnRegistry.init(allocator),
            .globals = std.ArrayList(*String).init(allocator),
            .resolver = resolver,
        };
    }

    pub fn deinit(self: *VM) void {
        self.string_pool.deinit();
        self.foreign_fn_registry.deinit();
        self.globals.deinit();
    }

    pub fn registerForeignFn(self: *VM, identifier: []const u8, foreign_fn: *const ForeignFn) !void {
        try self.foreign_fn_registry.register(identifier, foreign_fn);
    }

    pub fn evaluate(self: *VM, source: *const Source) !Value {
        var compile_ctx = compile.Context{
            .allocator = self.allocator,
            .gc = self.gc,
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

        return self.evaluateChunk(chunk);
    }

    fn evaluateChunk(self: *VM, chunk: *const code.Chunk) !Value {
        const root_closure = try self.gc.create(Closure);
        root_closure.* = .{
            .chunk = chunk,
            .upvalues = try self.allocator.alloc(*Upvalue, 0),
        };
        try self.gc.root(root_closure);
        defer GC.unroot(root_closure);

        const root_fiber = try self.gc.create(Fiber);
        root_fiber.* = Fiber.init();
        try self.gc.root(root_fiber);
        defer GC.unroot(root_fiber);

        var fiber = root_fiber;
        var frame = Fiber.Frame{
            .closure = Fiber.ClosureFrame{
                .closure = root_closure,
                .ip = 0,
                .bp = 0,
                .trace_item = .{ .path = "vm.zig", .location = Source.Location.zero },
            },
        };
        while (true) {
            switch (frame) {
                .closure => |*closure_frame| {
                    if (closure_frame.ip >= closure_frame.closure.chunk.code.len) return Error.CorruptedBytecode;
                    const inst = closure_frame.closure.chunk.code[closure_frame.ip];
                    closure_frame.ip += 1;

                    switch (inst.op) {
                        .nop => {},

                        .true => try fiber.push(self.allocator, Value.init(true)),
                        .false => try fiber.push(self.allocator, Value.init(false)),
                        .int => try fiber.push(self.allocator, Value.init(@as(i48, @intCast(inst.arg)))),
                        .constant => {
                            const constant_index: usize = @intCast(inst.arg);
                            if (constant_index >= closure_frame.closure.chunk.constants.len) return Error.CorruptedBytecode;
                            const value = closure_frame.closure.chunk.constants[constant_index];
                            try fiber.push(self.allocator, value);
                        },
                        .foreign_fn => {
                            const foreign_fn_index: usize = @intCast(inst.arg);
                            if (foreign_fn_index >= self.foreign_fn_registry.data.items.len) return Error.CorruptedBytecode;
                            const foreign_fn = self.foreign_fn_registry.data.items[foreign_fn_index];
                            try fiber.push(self.allocator, Value.init(foreign_fn));
                        },

                        .add => try fiber.push(self.allocator, try self.binaryOp(fiber, Value.add)),
                        .sub => try fiber.push(self.allocator, try self.binaryOp(fiber, Value.sub)),
                        .mul => try fiber.push(self.allocator, try self.binaryOp(fiber, Value.mul)),
                        .div => try fiber.push(self.allocator, try self.binaryOp(fiber, Value.div)),

                        .is_error => {
                            const value = fiber.pop() orelse return Error.CorruptedBytecode;
                            try fiber.push(self.allocator, Value.init(value.cast(*ErrorValue) != null));
                        },

                        .call => {
                            const arity: usize = @intCast(inst.arg);
                            if (closure_frame.ip <= 0 or closure_frame.ip >= closure_frame.closure.chunk.trace_items.locations.len) return Error.CorruptedBytecode;
                            const trace_item = .{
                                .path = frame.closure.closure.chunk.trace_items.path,
                                .location = frame.closure.closure.chunk.trace_items.locations[frame.closure.ip - 1],
                            };
                            try self.call(fiber, &frame, arity, trace_item);
                        },
                        .ret => {
                            frame = fiber.popFrame() orelse {
                                const ret_value = fiber.pop() orelse return Error.CorruptedBytecode;
                                try ret_value.root(self.gc);
                                return ret_value;
                            };
                        },

                        else => unreachable,
                    }
                },
                .foreign_fn => |*foreign_fn_frame| {
                    if (foreign_fn_frame.step >= foreign_fn_frame.foreign_fn.step_fns.len) return Error.CorruptedBytecode;
                    const step_fn = foreign_fn_frame.foreign_fn.step_fns[foreign_fn_frame.step];
                    foreign_fn_frame.step += 1;

                    const result = try step_fn(.{
                        .allocator = self.allocator,
                        .gc = self.gc,
                        .string_pool = &self.string_pool,
                        .fiber = fiber,
                        .frame = &frame,
                    });
                    switch (result) {
                        .ret => {
                            frame = fiber.popFrame() orelse return Error.CorruptedBytecode;
                            try fiber.push(self.allocator, result.ret);
                        },
                        .call => {
                            if (foreign_fn_frame.step <= 0 or foreign_fn_frame.step >= foreign_fn_frame.foreign_fn.trace_items.len) return Error.CorruptedBytecode;
                            const trace_item = foreign_fn_frame.foreign_fn.trace_items[foreign_fn_frame.step - 1];
                            try self.call(fiber, &frame, result.call, trace_item);
                        },
                    }
                },
            }
        }

        unreachable;
    }

    fn binaryOp(self: *VM, fiber: *Fiber, op: fn (Value, Value) ?Value) !Value {
        _ = self;
        const right = fiber.pop() orelse return Error.CorruptedBytecode;
        const left = fiber.pop() orelse return Error.CorruptedBytecode;
        return op(left, right) orelse Error.TODO;
    }

    fn call(self: *VM, fiber: *Fiber, frame: *Fiber.Frame, arity: usize, trace_item: ErrorValue.TraceItem) !void {
        const callable = fiber.getFromTop(arity) orelse return Error.CorruptedBytecode;
        if (callable.cast(*Closure)) |closure| {
            if (closure.chunk.arity != arity) return Error.TODO;
            try fiber.pushFrame(self.allocator, frame.*);
            frame.* = .{
                .closure = .{
                    .closure = closure,
                    .ip = 0,
                    .bp = fiber.values.items.len - 1 - arity,
                    .trace_item = trace_item,
                },
            };
        } else if (callable.cast(*const ForeignFn)) |foreign_fn| {
            if (foreign_fn.arity != arity) return Error.TODO;
            try fiber.pushFrame(self.allocator, frame.*);
            frame.* = .{
                .foreign_fn = .{
                    .foreign_fn = foreign_fn,
                    .step = 0,
                    .bp = fiber.values.items.len - 1 - arity,
                    .trace_item = trace_item,
                },
            };
        } else {
            return Error.TODO;
        }
    }
};

test VM {
    const allocator = std.testing.allocator;

    var gc = GC.init(allocator, allocator);
    defer gc.deinit();

    var resolver = MockResolver{};

    var vm = try VM.init(allocator, &gc, resolver.resolver());
    defer vm.deinit();

    const result = try vm.evaluate(&.{ .path = "<stdin>", .content = "123" });
    try std.testing.expectEqual(123, result.cast(i48).?);
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
