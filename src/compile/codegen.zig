const std = @import("std");
const code = @import("../code.zig");
const compile = @import("../compile.zig");
const GC = @import("../root.zig").GC;
const Source = @import("../source.zig").Source;
const Value = @import("../value.zig").Value;
const String = @import("../value.zig").String;
const ast = @import("ast.zig");

pub fn generate(ctx: *compile.Context, block: *const ast.Block) !*code.Chunk {
    var frame = Frame.init(ctx.allocator, ctx.gc);
    defer frame.deinit();

    try generateExpression(ctx, &frame, &block.statements[0].expression);
    try frame.appendInstruction(.ret, ctx.source.getLocation(block.span.offset + block.span.len));

    return frame.toOwnedChunk(0, ctx.source.path);
}

fn generateExpression(ctx: *compile.Context, frame: *Frame, expression: *const ast.Expression) !void {
    switch (expression.*) {
        .identifier => unreachable,
        .literal => |literal| try generateLiteral(ctx, frame, &literal),
    }
}

fn generateLiteral(ctx: *compile.Context, frame: *Frame, literal: *const ast.Literal) !void {
    switch (literal.*) {
        .true => |true_literal| try frame.appendInstruction(.true, ctx.source.getLocation(true_literal.offset)),
        .false => |false_literal| try frame.appendInstruction(.false, ctx.source.getLocation(false_literal.offset)),
        .int => |int_literal| {
            if (int_literal.value > std.math.maxInt(code.Instruction.Arg)) {
                const constant_index = try frame.appendConstant(Value.init(int_literal.value));
                try frame.appendInstructionArg(.constant, constant_index, ctx.source.getLocation(int_literal.span.offset));
            } else {
                try frame.appendInstructionArg(.int, @intCast(int_literal.value), ctx.source.getLocation(int_literal.span.offset));
            }
        },
        .float => |float_literal| {
            const constant_index = try frame.appendConstant(Value.init(float_literal.value));
            try frame.appendInstructionArg(.constant, constant_index, ctx.source.getLocation(float_literal.span.offset));
        },
    }
}

const Frame = struct {
    allocator: std.mem.Allocator,
    gc: *GC,

    locals: std.ArrayListUnmanaged(Local) = .{},
    curr_scope: usize = 0,

    code: std.ArrayListUnmanaged(code.Instruction) = .{},
    constants: std.ArrayListUnmanaged(Value) = .{},
    chunks: std.ArrayListUnmanaged(*const code.Chunk) = .{},
    locations: std.ArrayListUnmanaged(Source.Location) = .{},

    const Local = struct {
        scope: usize,
        slot: code.Instruction.Arg,
        identifier: *String,
        is_captured: bool,
    };

    fn init(allocator: std.mem.Allocator, gc: *GC) Frame {
        return .{
            .allocator = allocator,
            .gc = gc,
        };
    }

    fn deinit(self: *Frame) void {
        self.locals.deinit(self.allocator);
        self.code.deinit(self.allocator);
        self.constants.deinit(self.allocator);
        self.chunks.deinit(self.allocator);
        self.locations.deinit(self.allocator);
        self.* = undefined;
    }

    fn pushScope(self: *Frame) void {
        self.curr_scope += 1;
    }

    fn popScope(self: *Frame) void {
        self.curr_scope -= 1;
    }

    fn appendConstant(self: *Frame, value: Value) !code.Instruction.Arg {
        // TODO: check overflow
        try self.constants.append(self.allocator, value);
        return @intCast(self.constants.items.len - 1);
    }

    fn appendInstruction(self: *Frame, op: code.Instruction.Op, location: Source.Location) !void {
        try self.code.append(self.allocator, .{ .op = op });
        try self.locations.append(self.allocator, location);
    }

    fn appendInstructionArg(self: *Frame, op: code.Instruction.Op, arg: code.Instruction.Arg, location: Source.Location) !void {
        try self.code.append(self.allocator, .{ .op = op, .arg = arg });
        try self.locations.append(self.allocator, location);
    }

    fn toOwnedChunk(self: *Frame, arity: usize, path: []const u8) !*code.Chunk {
        const chunk = try self.gc.create(code.Chunk);
        chunk.* = .{
            .arity = arity,
            .code = try self.code.toOwnedSlice(self.allocator),
            .constants = try self.constants.toOwnedSlice(self.allocator),
            .chunks = try self.chunks.toOwnedSlice(self.allocator),
            .trace_items = .{
                .path = path,
                .locations = try self.locations.toOwnedSlice(self.allocator),
            },
        };
        return chunk;
    }
};
