const std = @import("std");
const bytecode = @import("bytecode.zig");
const codegen = @import("codegen.zig");
const parse = @import("parse.zig");
const Parser = parse.Parser;
const Source = @import("Source.zig");
const Value = @import("Value.zig");
const Reporter = @import("Reporter.zig");

const Self = @This();

reporter: Reporter,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) !Self {
    return Self{
        .allocator = allocator,
        .reporter = Reporter.init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn eval(self: *Self, source: Source) !Value {
    var parser = Parser.init(&self.reporter, source);
    var root = try parser.parse(self.allocator);
    defer root.deinit(self.allocator);

    var chunk = try codegen.generate(self.allocator, root);
    defer chunk.deinit(self.allocator);

    const inst = chunk.code.items[0];
    return switch (inst.op) {
        .int => Value.initInt(@intCast(inst.arg)),
    };
}
