const std = @import("std");
const ast = @import("ast.zig");
const bytecode = @import("bytecode.zig");
const Value = @import("Value.zig");
const Reporter = @import("Reporter.zig");
const Source = @import("Source.zig");

pub const Generator = struct {
    const Self = @This();

    const Error = error{CompileFailed} ||
        @TypeOf(std.io.getStdErr().writer()).Error ||
        std.mem.Allocator.Error;

    allocator: std.mem.Allocator,
    reporter: *Reporter,
    source: Source,

    pub fn init(allocator: std.mem.Allocator, reporter: *Reporter, source: Source) Self {
        return Self{
            .allocator = allocator,
            .reporter = reporter,
            .source = source,
        };
    }

    pub fn generate(self: *Self, root: ast.Root) !bytecode.Chunk {
        var frame = Frame{};
        try self.generateExpression(&frame, root.expr);
        _ = try frame.chunk.appendInst(self.allocator, .ret);
        return frame.chunk;
    }

    fn generateExpression(self: *Self, frame: *Frame, expr: *const ast.Expression) Error!void {
        switch (expr.*) {
            .nil => {
                _ = try frame.chunk.appendInst(self.allocator, .nil);
            },
            .true => {
                _ = try frame.chunk.appendInst(self.allocator, .true);
            },
            .false => {
                _ = try frame.chunk.appendInst(self.allocator, .false);
            },
            .int => |int| {
                // FIXME: check for int size
                _ = try frame.chunk.appendInstArg(self.allocator, .int, @intCast(int.int));
            },
            .float => |float| {
                const index = try frame.chunk.appendConstant(self.allocator, Value.initFloat(float.float));
                _ = try frame.chunk.appendInstArg(self.allocator, .constant, @intCast(index));
            },
            .identifier => |identifier| {
                if (frame.getLocal(identifier.identifier)) |local| {
                    _ = try frame.chunk.appendInstArg(self.allocator, .local, @intCast(local.slot));
                } else {
                    try self.reporter.report(self.source, identifier.span, "undefined variable: {s}", .{identifier.identifier});
                    return error.CompileFailed;
                }
            },
            .unary => |unary| {
                try self.generateExpression(frame, unary.expr);
                _ = try frame.chunk.appendInst(self.allocator, bytecode.Instruction.Op.fromUnaryOp(unary.op));
            },
            .binary => |binary| {
                try self.generateExpression(frame, binary.left);
                try self.generateExpression(frame, binary.right);
                _ = try frame.chunk.appendInst(self.allocator, bytecode.Instruction.Op.fromBinaryOp(binary.op));
            },
            .block => |block| {
                try self.generateBlock(frame, &block);
            },
        }
    }

    fn generateBlock(self: *Self, frame: *Frame, block: *const ast.Block) !void {
        frame.pushScope();

        for (block.stmts) |stmt| {
            try self.generateStatement(frame, stmt);
        }

        if (block.ret_expr) |ret_expr| {
            try self.generateExpression(frame, ret_expr);
        } else {
            _ = try frame.chunk.appendInst(self.allocator, .nil);
        }

        frame.popScope();
    }

    fn generateStatement(self: *Self, frame: *Frame, stmt: ast.Statement) !void {
        switch (stmt) {
            .expr => |expr_stmt| {
                try self.generateExpression(frame, expr_stmt.expr);
                _ = try frame.chunk.appendInst(self.allocator, .pop);
            },
        }
    }
};

const Frame = struct {
    const Self = @This();

    const Local = struct {
        scope: usize,
        slot: usize,
        identifier: []const u8,
        is_captured: bool,
    };

    chunk: bytecode.Chunk = .{},
    cur_scope: usize = 0,
    locals: std.ArrayListUnmanaged(Local) = .{},

    pub fn pushScope(self: *Self) void {
        self.cur_scope += 1;
    }

    pub fn popScope(self: *Self) void {
        while (true) {
            const local = self.locals.popOrNull() orelse break;
            if (local.scope != self.cur_scope) break;
            _ = self.locals.pop();
        }
        self.cur_scope -= 1;
    }

    pub fn getLocal(self: *Self, identifier: []const u8) ?Local {
        var it = std.mem.reverseIterator(self.locals.items);
        while (it.next()) |local| {
            if (std.mem.eql(u8, local.identifier, identifier)) {
                return local;
            }
        }
        return null;
    }
};
