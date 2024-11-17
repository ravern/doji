const std = @import("std");
const ast = @import("ast.zig");
const bytecode = @import("../bytecode.zig");
const compile = @import("../compile.zig");
const heap = @import("../heap.zig");
const Source = @import("../Source.zig");
const Value = @import("../Value.zig");

const Frame = struct {
    const Self = @This();

    const Local = struct {
        scope: usize,
        slot: u24,
        identifier: *heap.String,
        is_captured: bool,
    };

    allocator: std.mem.Allocator,
    current_scope: usize = 0,
    locals: std.ArrayList(Local),
    code: std.ArrayList(bytecode.Instruction),
    constants: std.ArrayList(Value),

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .locals = std.ArrayList(Local).init(allocator),
            .code = std.ArrayList(bytecode.Instruction).init(allocator),
            .constants = std.ArrayList(Value).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.locals.deinit();
        self.code.deinit();
        self.constants.deinit();
        self.* = undefined;
    }

    pub fn pushScope(self: *Self) void {
        self.current_scope += 1;
    }

    pub fn popScope(self: *Self) !?[]Local {
        if (self.locals.items.len == 0) return null;
        return try self.allocator.dupe(Local, self.locals.items[self.locals.items.len - 1 ..]);
    }

    pub fn addLocal(self: *Self, identifier: *heap.String) !?Local {
        const local = Local{
            .scope = self.current_scope,
            .slot = @intCast(self.locals.items.len),
            .identifier = identifier,
            .is_captured = false,
        };
        try self.locals.append(local);
        return local;
    }

    pub fn getLocal(self: *const Self, identifier: *heap.String) ?Local {
        const it = std.mem.reverseIterator(self.locals.items);
        while (it.next()) |local| {
            // all identifiers are interned, so we can just compare pointers
            if (local.identifier == identifier) return local;
        }
        return null;
    }

    pub fn appendInstruction(self: *Self, op: bytecode.Instruction.Op) !void {
        try self.code.append(.{ .op = op, .arg = 0 });
    }

    pub fn appendInstructionWithArg(self: *Self, op: bytecode.Instruction.Op, arg: bytecode.Instruction.Arg) !void {
        try self.code.append(.{ .op = op, .arg = arg });
    }

    pub fn addConstant(self: *Self, value: Value) !u24 {
        try self.constants.append(value);
        return @intCast(self.constants.items.len - 1);
    }
};

pub fn generate(context: *compile.Context, module: *const ast.Module) !bytecode.Chunk {
    var frame = Frame.init(context.allocator);
    defer frame.deinit();
    try generateBlock(context, &frame, module.block);
    _ = try frame.appendInstruction(.ret);
    return bytecode.Chunk{
        .code = try frame.code.toOwnedSlice(),
        .constants = try frame.constants.toOwnedSlice(),
    };
}

fn generateExpression(context: *compile.Context, frame: *Frame, expr: *const ast.Expression) compile.Error!void {
    switch (expr.*) {
        .nil => {
            _ = try frame.appendInstruction(.nil);
        },
        .true => {
            _ = try frame.appendInstruction(.true);
        },
        .false => {
            _ = try frame.appendInstruction(.false);
        },
        .int => |int| {
            // FIXME: check for int size
            _ = try frame.appendInstructionWithArg(.int, @intCast(int.int));
        },
        .float => |float| {
            const index = try frame.addConstant(Value.initFloat(float.float));
            _ = try frame.appendInstructionWithArg(.constant, index);
        },
        .identifier => |identifier| {
            if (frame.getLocal(identifier.identifier)) |local| {
                _ = try frame.appendInstructionWithArg(.local, local.slot);
            } else {
                std.debug.print(
                    "<generator>:{d}:{d}: undefined variable: {s}\n",
                    .{ identifier.span.start.line, identifier.span.start.col, identifier.identifier },
                );
                return error.CompileFailed;
            }
        },
        .unary => |unary| {
            try generateExpression(context, frame, unary.expr);
            _ = try frame.appendInstruction(opFromUnary(unary.op));
        },
        .binary => |binary| {
            try generateExpression(context, frame, binary.left);
            try generateExpression(context, frame, binary.right);
            _ = try frame.appendInstruction(opFromBinary(binary.op));
        },
        .block => |block| {
            frame.pushScope();
            try generateBlock(context, frame, &block);
            _ = try frame.popScope();
        },
    }
}

fn generateBlock(context: *compile.Context, frame: *Frame, block: *const ast.Block) !void {
    for (block.stmts) |stmt| {
        try generateStatement(context, frame, stmt);
    }

    if (block.ret_expr) |ret_expr| {
        try generateExpression(context, frame, ret_expr);
    } else {
        _ = try frame.appendInstruction(.nil);
    }
}

fn generateStatement(context: *compile.Context, frame: *Frame, stmt: ast.Statement) !void {
    switch (stmt) {
        .let => |let_stmt| {
            try generateExpression(context, frame, let_stmt.expr);
            // TODO: only handles identifier patterns for now
            _ = (try frame.addLocal(let_stmt.pattern.identifier.identifier)) orelse {
                std.debug.print(
                    "<generator>:{d}:{d}: variable already declared: {s}\n",
                    .{ let_stmt.pattern.getSpan().start.line, let_stmt.pattern.getSpan().start.col, let_stmt.pattern.identifier.identifier },
                );
                return error.CompileFailed;
            };
        },
        .expr => |expr_stmt| {
            try generateExpression(context, frame, expr_stmt.expr);
            _ = try frame.appendInstruction(.pop);
        },
    }
}

fn opFromUnary(op: ast.UnaryExpression.Op) bytecode.Instruction.Op {
    return switch (op) {
        .pos => .pos,
        .neg => .neg,
        .log_not => .log_not,
    };
}

fn opFromBinary(op: ast.BinaryExpression.Op) bytecode.Instruction.Op {
    return switch (op) {
        .add => .add,
        .sub => .sub,
        .mul => .mul,
        .div => .div,
        .mod => .mod,
        .eq => .eq,
        .neq => .neq,
        .lt => .lt,
        .le => .le,
        .gt => .gt,
        .ge => .ge,
        .log_and => .log_and,
        .log_or => .log_or,
        .bit_and => .bit_and,
        .bit_or => .bit_or,
        .bit_xor => .bit_xor,
        .shl => .shl,
        .shr => .shr,
    };
}
