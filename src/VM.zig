const std = @import("std");
const bytecode = @import("bytecode.zig");
const codegen = @import("codegen.zig");
const parse = @import("parse.zig");
const Parser = parse.Parser;
const Source = @import("Source.zig");
const Span = @import("Span.zig");
const Value = @import("Value.zig");
const Reporter = @import("Reporter.zig");
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
reporter: Reporter,
fiber: *Fiber,
global_scope: codegen.Scope,

pub fn init(allocator: std.mem.Allocator) !Self {
    var self = Self{
        .allocator = allocator,
        .reporter = Reporter.init(allocator),
        .fiber = undefined,
        .global_scope = codegen.Scope{},
    };

    self.fiber = try allocator.create(Fiber);
    errdefer allocator.destroy(self.fiber);
    self.fiber.* = Fiber.init(allocator);

    return self;
}

pub fn deinit(self: *Self) void {
    self.fiber.deinit();
    self.allocator.destroy(self.fiber);
    self.global_scope.deinit(self.allocator);
    self.* = undefined;
}

pub fn eval(self: *Self, source: Source) !Value {
    // we need to offset by the number of locals in the global scope
    // conveniently, we can use the arity argument to do so
    // TODO: is this the cleanest way to do this?
    const arity = self.global_scope.locals.items.len;

    var parser = Parser.init(&self.reporter, source);
    var root = try parser.parse(self.allocator);
    defer root.deinit(self.allocator);

    var generator = codegen.Generator.init(self.allocator, &self.reporter, source);
    var chunk = try generator.generateWithScope(&self.global_scope, root);
    defer chunk.deinit(self.allocator);

    try self.fiber.pushFrame(&chunk, arity);

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
