const std = @import("std");
const bytecode = @import("bytecode.zig");
const compile = @import("compile.zig");
const heap = @import("heap.zig");
const Source = @import("Source.zig");
const Value = @import("Value.zig");
const Fiber = @import("Fiber.zig");

const Self = @This();

const unary_ops = std.EnumMap(bytecode.Instruction.Op, *const fn (Value) ?Value).init(.{
    .pos = Value.pos,
    .neg = Value.neg,
    .log_not = Value.logNot,
    .bit_not = Value.bitNot,
});

const binary_ops = std.EnumMap(bytecode.Instruction.Op, *const fn (Value, Value) ?Value).init(.{
    .add = Value.add,
    .sub = Value.sub,
    .mul = Value.mul,
    .div = Value.div,
    .mod = Value.mod,
    .eq = Value.eq,
    .neq = Value.neq,
    .lt = Value.lt,
    .le = Value.le,
    .gt = Value.gt,
    .ge = Value.ge,
    .log_and = Value.logAnd,
    .log_or = Value.logOr,
    .bit_and = Value.bitAnd,
    .bit_or = Value.bitOr,
    .bit_xor = Value.bitXor,
    .shl = Value.shl,
    .shr = Value.shr,
});

allocator: std.mem.Allocator,
gc: *heap.GC,
string_pool: heap.StringPool,
root_fiber: *Fiber,
current_fiber: *Fiber,
globals_map: []*heap.String = &.{},

pub fn init(allocator: std.mem.Allocator) !Self {
    var self = Self{
        .allocator = allocator,
        .gc = heap.GC.init(allocator),
        .string_pool = undefined,
        .root_fiber = undefined,
        .current_fiber = undefined,
    };

    self.string_pool = heap.StringPool.init(allocator, &self.gc);

    self.root_fiber = try self.gc.create(Fiber);
    self.root_fiber.* = Fiber.init(allocator);

    self.current_fiber = self.root_fiber;

    return self;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.globals_map);
    self.* = undefined;
}

pub fn evaluate(self: *Self, source: Source) !Value {
    // we need to offset by the number of locals in the global scope
    // conveniently, we can use the arity argument to do so
    // TODO: is this the cleanest way to do this?
    const globals_count = self.globals_map.len;

    var compile_context = compile.Context{
        .allocator = self.allocator,
        .gc = &self.gc,
        .string_pool = &self.string_pool,
        .globals_map = &self.globals_map,
    };
    var chunk = try compile.compile(&compile_context, &source);
    defer chunk.deinit(self.allocator);

    try self.fiber.pushFrame(&chunk, globals_count);

    while (true) {
        const inst = try self.fiber.step();

        switch (inst.op) {
            .nil => try self.fiber.push(Value.nil),
            .true => try self.fiber.push(Value.initBool(true)),
            .false => try self.fiber.push(Value.initBool(false)),
            .int => try self.fiber.push(Value.initInt(@intCast(inst.arg))),
            .constant => try self.fiber.push(chunk.constants.items[inst.arg]),

            .local => try self.fiber.push(try self.fiber.getLocal(inst.arg)),

            .pop => _ = try self.fiber.pop(),

            .pos,
            .neg,
            .log_not,
            .bit_not,
            => {
                const value = try self.fiber.pop();
                try self.fiber.push(unary_ops.get(inst.op).?(value).?);
            },

            .add,
            .sub,
            .mul,
            .div,
            .mod,
            .eq,
            .neq,
            .lt,
            .le,
            .gt,
            .ge,
            .log_and,
            .log_or,
            .bit_and,
            .bit_or,
            .bit_xor,
            .shl,
            .shr,
            => {
                // FIXME: bunch of uncaught errors here
                const right = try self.fiber.pop();
                const left = try self.fiber.pop();
                try self.fiber.push(binary_ops.get(inst.op).?(left, right).?);
            },

            .ret => {
                try self.fiber.popFrame();
                return try self.fiber.pop();
            },

            else => unreachable,
        }
    }
}
