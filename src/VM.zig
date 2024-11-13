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

const binary_ops = std.EnumMap(bytecode.Instruction.Op, *const fn (Value, Value) ?Value).init(.{
    .add = Value.add,
    .sub = Value.sub,
    .mul = Value.mul,
    .div = Value.div,
    .mod = Value.mod,
    .bit_and = Value.bitAnd,
    .bit_or = Value.bitOr,
    .bit_xor = Value.bitXor,
    .shift_left = Value.shiftLeft,
    .shift_right = Value.shiftRight,
});

allocator: std.mem.Allocator,
reporter: Reporter,

pub fn init(allocator: std.mem.Allocator) !Self {
    return Self{
        .allocator = allocator,
        .reporter = Reporter.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.* = undefined;
}

pub fn eval(self: *Self, source: Source) !Value {
    var parser = Parser.init(&self.reporter, source);
    var root = try parser.parse(self.allocator);
    defer root.deinit(self.allocator);

    var generator = codegen.Generator.init(self.allocator, &self.reporter, source);
    var chunk = try generator.generate(root);
    defer chunk.deinit(self.allocator);

    var fiber = Fiber.init(self.allocator);
    defer fiber.deinit();

    var ip: usize = 0;

    while (true) {
        if (ip >= chunk.code.items.len) {
            try self.reporter.report(source, Span.zero, "reached end of bytecode without returning", .{});
            return error.CorruptedBytecode;
        }

        const inst = chunk.code.items[ip];
        ip += 1;

        switch (inst.op) {
            .nil => try fiber.push(Value.nil),
            .true => try fiber.push(Value.initBool(true)),
            .false => try fiber.push(Value.initBool(false)),
            .int => try fiber.push(Value.initInt(@intCast(inst.arg))),
            .constant => try fiber.push(chunk.constants.items[inst.arg]),

            .local => try fiber.push(fiber.getLocal(inst.arg)),

            .add, .sub, .mul, .div, .mod, .bit_and, .bit_or, .bit_xor, .shift_left, .shift_right => {
                // FIXME: bunch of uncaught errors here
                const right = fiber.pop() orelse unreachable;
                const left = fiber.pop() orelse unreachable;
                try fiber.push(binary_ops.get(inst.op).?(left, right).?);
            },

            .ret => return fiber.pop() orelse unreachable, // FIXME: catch and report

            else => unreachable,
        }
    }
}