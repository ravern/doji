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

    curr_fiber: ?*Fiber = null,

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
        root_closure.* = .{ .chunk = chunk, .upvalues = &.{} };

        var fiber = try self.gc.create(Fiber);
        fiber.* = try Fiber.init(self.allocator, root_closure, .{ .path = "vm.zig", .location = Source.Location.zero });

        self.curr_fiber = fiber;

        while (true) {
            const step = fiber.advance() orelse return Error.CorruptedBytecode;
            switch (step) {
                .instruction => |inst| switch (inst.op) {
                    .nop => {},

                    .true => try fiber.push(self.allocator, Value.init(true)),
                    .false => try fiber.push(self.allocator, Value.init(false)),
                    .int => try fiber.push(self.allocator, Value.init(@as(i48, @intCast(inst.arg)))),
                    .constant => {
                        const value = fiber.getConstant(@intCast(inst.arg)) orelse return Error.CorruptedBytecode;
                        try fiber.push(self.allocator, value);
                    },
                    .foreign_fn => {
                        const foreign_fn = self.foreign_fn_registry.get(@intCast(inst.arg)) orelse return Error.CorruptedBytecode;
                        try fiber.push(self.allocator, Value.init(foreign_fn));
                    },

                    .add => try fiber.push(self.allocator, try self.binaryOp(Value.add)),
                    .sub => try fiber.push(self.allocator, try self.binaryOp(Value.sub)),
                    .mul => try fiber.push(self.allocator, try self.binaryOp(Value.mul)),
                    .div => try fiber.push(self.allocator, try self.binaryOp(Value.div)),

                    .is_error => {
                        const value = fiber.pop() orelse return Error.CorruptedBytecode;
                        try fiber.push(self.allocator, Value.init(value.cast(*ErrorValue) != null));
                    },

                    .call => try self.call(@intCast(inst.arg)),
                    .ret => return fiber.pop() orelse return Error.CorruptedBytecode,

                    else => unreachable,
                },
                .step_fn => |step_fn| {
                    const result = try step_fn(.{
                        .allocator = self.allocator,
                        .fiber = fiber,
                        .gc = self.gc,
                        .string_pool = &self.string_pool,
                    });
                    switch (result) {
                        .ret => {
                            _ = fiber.popFrame();
                            try fiber.push(self.allocator, result.ret);
                        },
                        .call => {
                            const closure_value = fiber.getFromTop(result.call) orelse return Error.TODO;
                            const closure = closure_value.cast(*Closure) orelse return Error.TODO;
                            const trace_item = fiber.getCurrentTraceItem() orelse return Error.CorruptedBytecode;
                            try fiber.pushClosureFrame(self.allocator, closure, trace_item);
                        },
                    }
                },
            }
        }

        unreachable;
    }

    fn call(self: *VM, arity: usize) !void {
        var fiber = self.curr_fiber.?;
        const callable = fiber.getFromTop(arity) orelse return Error.CorruptedBytecode;
        const trace_item = fiber.getCurrentTraceItem() orelse return Error.CorruptedBytecode;
        if (callable.cast(*const ForeignFn)) |foreign_fn| {
            if (foreign_fn.arity != arity) return Error.TODO;
            try fiber.pushForeignFnFrame(self.allocator, foreign_fn, trace_item);
        } else {
            return Error.CorruptedBytecode;
        }
    }

    fn binaryOp(self: *VM, op: fn (Value, Value) ?Value) !Value {
        var fiber = self.curr_fiber.?;
        const right = fiber.pop() orelse return Error.CorruptedBytecode;
        const left = fiber.pop() orelse return Error.CorruptedBytecode;
        return op(left, right) orelse Error.TODO;
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
