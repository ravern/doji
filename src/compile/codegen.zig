const std = @import("std");
const maxInt = std.math.maxInt;
const assert = std.debug.assert;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const StringHashMapUnmanaged = std.StringHashMapUnmanaged;

const bytecode = @import("../vm/bytecode.zig");
const Chunk = bytecode.Chunk;
const Instruction = bytecode.Instruction;
const OpCode = bytecode.OpCode;
const Upvalue = bytecode.Upvalue;
const Environment = @import("../global.zig").Environment;
const DojiError = @import("../errors.zig").DojiError;
const Span = @import("../Span.zig");
const ast = @import("./ast.zig");

pub fn generate(allocator: Allocator, env: *Environment, file: *const ast.File) !Chunk {
    var frame = Frame{};
    try generateFile(allocator, env, &frame, file);
    return frame.toOwnedChunk(allocator);
}

fn generateFile(
    allocator: Allocator,
    env: *Environment,
    frame: *Frame,
    file: *const ast.File,
) !void {
    try generateBlock(allocator, env, frame, &file.block);
    _ = try frame.appendInstruction(allocator, .ret);
}

fn generateStatement(
    allocator: Allocator,
    env: *Environment,
    frame: *Frame,
    statement: *const ast.Statement,
) !void {
    switch (statement.*) {
        .Expression => try generateExpression(allocator, env, frame, &statement.Expression),
    }
}

fn generateExpression(
    allocator: Allocator,
    env: *Environment,
    frame: *Frame,
    expression: *const ast.Expression,
) error{ CompileFailed, OutOfMemory }!void {
    switch (expression.*) {
        .Block => try generateBlock(allocator, env, frame, &expression.Block),
        .Literal => try generateLiteral(allocator, env, frame, &expression.Literal),
    }
}

fn generateBlock(
    allocator: Allocator,
    env: *Environment,
    frame: *Frame,
    block: *const ast.Block,
) !void {
    for (block.statements) |statement| {
        try generateStatement(allocator, env, frame, &statement);
    }
    if (block.return_expression) |return_expression| {
        try generateExpression(allocator, env, frame, return_expression);
    } else {
        _ = try frame.appendInstruction(allocator, .nil);
    }
}

fn generateLiteral(
    allocator: Allocator,
    env: *Environment,
    frame: *Frame,
    literal: *const ast.Literal,
) !void {
    switch (literal.*) {
        .Nil => _ = try frame.appendInstruction(allocator, .nil),
        .Bool => _ = try frame.appendInstructionArg(allocator, .bool, if (literal.Bool.bool) 1 else 0),
        .Int => _ = try frame.appendInstructionArg(allocator, .int, literal.Int.int),
        .Float => {
            const index = try env.constants.add(.{ .float = literal.Float.float });
            _ = try frame.appendInstructionArg(allocator, .constant, index);
        },
    }
}

const Frame = struct {
    parent: ?*Frame = null,
    scope: Scope = Scope{},
    let_scope: ?Scope = null,
    upval_indices: StringHashMapUnmanaged(usize) = .{},
    upvals: ArrayListUnmanaged(Upvalue) = .{},
    code: ArrayListUnmanaged(Instruction) = .{},

    fn initParent(parent: ?*Frame) Frame {
        return Frame{
            .parent = parent,
        };
    }

    fn appendInstruction(self: *Frame, allocator: Allocator, op: OpCode) !usize {
        const offset = self.code.items.len;
        try self.code.append(allocator, Instruction{ .op = op });
        return offset;
    }

    fn appendInstructionArg(
        self: *Frame,
        allocator: Allocator,
        op: OpCode,
        arg: usize,
    ) !usize {
        const offset = self.code.items.len;
        var arg_offset = @as(u6, @bitSizeOf(usize) - @bitSizeOf(u8));
        var has_started = false;
        while (arg_offset > 0) : (arg_offset -= @bitSizeOf(u8)) {
            const arg_component = (arg >> arg_offset) & maxInt(u8);
            if (arg_component != 0 or has_started) {
                try self.code.append(allocator, Instruction{ .op = OpCode.ext, .arg = @intCast(arg_component) });
                has_started = true;
            }
        }
        try self.code.append(allocator, Instruction{ .op = op, .arg = @intCast(arg & maxInt(u8)) });
        return offset;
    }

    fn toOwnedChunk(
        self: *Frame,
        allocator: Allocator,
    ) !Chunk {
        return Chunk{
            .code = try self.code.toOwnedSlice(allocator),
            .upvals = try self.upvals.toOwnedSlice(allocator),
        };
    }
};

const Scope = struct {
    parent: ?*Scope = null,
    locals: StringHashMapUnmanaged(Local) = .{},

    fn initParent(parent: ?*Scope) Scope {
        return Scope{
            .parent = parent,
        };
    }

    fn getLocal(self: *Scope, name: []const u8) ?Local {
        if (self.locals.get(name)) |local| {
            return local;
        }
        if (self.parent) |parent| {
            return parent.getLocal(name);
        }
        return null;
    }
};

const Local = struct {
    slot: usize,
    is_local: bool,
};

fn testGenerate(allocator: Allocator, file: *const ast.File) !Chunk {
    var env = Environment.init(allocator);
    defer env.deinit(allocator);
    return try generate(allocator, &env, file);
}

test "nil" {
    const allocator = testing.allocator;
    const file = ast.File{
        .block = ast.Block{
            .span = Span.initZero(),
            .statements = &[_]ast.Statement{},
            .return_expression = &ast.Expression{
                .Literal = ast.Literal{
                    .Nil = Span.initZero(),
                },
            },
        },
    };
    const chunk = try testGenerate(allocator, &file);
    defer chunk.deinit(allocator);
    try testing.expectEqual(
        Instruction{
            .op = OpCode.nil,
        },
        chunk.code[0],
    );
}

test "bool" {
    const allocator = testing.allocator;
    const file = ast.File{
        .block = ast.Block{
            .span = Span.initZero(),
            .statements = &[_]ast.Statement{},
            .return_expression = &ast.Expression{
                .Literal = ast.Literal{
                    .Bool = ast.BoolLiteral{
                        .span = Span.initZero(),
                        .bool = true,
                    },
                },
            },
        },
    };
    const chunk = try testGenerate(allocator, &file);
    defer chunk.deinit(allocator);
    try testing.expectEqual(
        Instruction{
            .op = OpCode.bool,
            .arg = 1,
        },
        chunk.code[0],
    );
}

test "int" {
    const allocator = testing.allocator;
    const file = ast.File{
        .block = ast.Block{
            .span = Span.initZero(),
            .statements = &[_]ast.Statement{},
            .return_expression = &ast.Expression{
                .Literal = ast.Literal{
                    .Int = ast.IntLiteral{
                        .span = Span.initZero(),
                        .int = 123,
                    },
                },
            },
        },
    };
    const chunk = try testGenerate(allocator, &file);
    defer chunk.deinit(allocator);
    try testing.expectEqual(
        Instruction{
            .op = OpCode.int,
            .arg = 123,
        },
        chunk.code[0],
    );
}

test "float" {
    const allocator = testing.allocator;
    const file = ast.File{
        .block = ast.Block{
            .span = Span.initZero(),
            .statements = &[_]ast.Statement{},
            .return_expression = &ast.Expression{
                .Literal = ast.Literal{
                    .Float = ast.FloatLiteral{
                        .span = Span.initZero(),
                        .float = 3.14159,
                    },
                },
            },
        },
    };
    const chunk = try testGenerate(allocator, &file);
    defer chunk.deinit(allocator);
    try testing.expectEqual(
        Instruction{
            .op = OpCode.constant,
            .arg = 0,
        },
        chunk.code[0],
    );
}
