const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const compile = @import("./compile.zig").compile;
const errors = @import("./errors.zig");
const DojiError = errors.DojiError;
const Error = errors.Error;
const global = @import("./global.zig");
const Environment = global.Environment;
const Fiber = @import("./vm/fiber.zig").Fiber;
const GcAllocator = @import("./vm/gc.zig").GcAllocator;
const value = @import("./vm/value.zig");
const Value = value.Value;

pub const Vm = struct {
    allocator: Allocator,
    gc_allocator: GcAllocator,
    env: Environment,
    fiber_stack: FiberStack = .{},

    pub fn init(allocator: Allocator) Vm {
        return Vm{
            .allocator = allocator,
            .gc_allocator = GcAllocator.init(allocator),
            .env = Environment.init(allocator),
        };
    }

    pub fn deinit(self: *Vm) void {
        self.gc_allocator.deinit();
        self.env.deinit(self.allocator);
        self.fiber_stack.deinit(self.allocator);
    }

    pub fn execute(self: *Vm, source: []const u8) !Value {
        const gc_allocator = self.gc_allocator.allocator();

        const chunk = try compile(self.allocator, &self.env, source);
        defer chunk.deinit(self.allocator);

        // no need to defer free, it's managed by gc
        const fiber = try gc_allocator.create(Fiber);
        fiber.* = try Fiber.init(gc_allocator, &chunk);

        try self.fiber_stack.push(self.allocator, fiber);
        while (true) {
            const top_fiber = self.fiber_stack.getTop() orelse unreachable; // TODO
            const step = try top_fiber.step(gc_allocator, &self.env);
            switch (step) {
                .Continue => {},
                .Yield => unreachable, // TODO
                .Resume => unreachable, // TODO
                .Done => return step.Done,
            }
        }
    }

    pub fn getError(self: *Vm) ?Error {
        return self.env.err;
    }
};

const FiberStack = struct {
    fibers: ArrayListUnmanaged(*Fiber) = .{},

    pub fn deinit(self: *FiberStack, allocator: Allocator) void {
        self.fibers.deinit(allocator);
    }

    pub fn getTop(self: *const FiberStack) ?*Fiber {
        return self.fibers.getLastOrNull();
    }

    pub fn push(self: *FiberStack, allocator: Allocator, fiber: *Fiber) !void {
        try self.fibers.append(allocator, fiber);
    }
};

fn testVm(allocator: Allocator, source: []const u8) !Value {
    var vm = Vm.init(allocator);
    defer vm.deinit();

    return vm.execute(source);
}

test {
    testing.refAllDecls(@This());
}

test "nil" {
    const allocator = std.testing.allocator;
    const result = try testVm(allocator, "nil");
    try testing.expect(result.isNil());
}

test "bool" {
    const allocator = std.testing.allocator;
    const result = try testVm(allocator, "true");
    try testing.expectEqual(true, result.asBool());
}

test "int" {
    const allocator = std.testing.allocator;
    const result = try testVm(allocator, "123");
    try testing.expectEqual(123, result.asInt());
}

test "large int" {
    const allocator = std.testing.allocator;
    const result = try testVm(allocator, "123456");
    try testing.expectEqual(123456, result.asInt());
}

test "float" {
    const allocator = std.testing.allocator;
    const result = try testVm(allocator, "3.14159");
    try testing.expectEqual(3.14159, result.asFloat());
}
