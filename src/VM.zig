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
            .ret => return fiber.pop() orelse unreachable, // FIXME: catch and report
        }
    }
}
