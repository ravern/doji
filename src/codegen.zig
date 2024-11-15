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
        var scope = Scope{};
        defer scope.deinit(self.allocator);
        return self.generateWithScope(&scope, root);
    }

    pub fn generateWithScope(self: *Self, scope: *Scope, root: ast.Root) !bytecode.Chunk {
        var frame = Frame.init(self.allocator);
        defer frame.deinit();
        try frame.pushScope(scope.*);
        try self.generateBlock(&frame, root.block);
        _ = try frame.chunk.appendInst(self.allocator, .ret);
        scope.* = frame.popScope();
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
                try frame.pushFreshScope();
                try self.generateBlock(frame, &block);
                var scope = frame.popScope();
                defer scope.deinit(self.allocator);
            },
        }
    }

    fn generateBlock(self: *Self, frame: *Frame, block: *const ast.Block) !void {
        for (block.stmts) |stmt| {
            try self.generateStatement(frame, stmt);
        }

        if (block.ret_expr) |ret_expr| {
            try self.generateExpression(frame, ret_expr);
        } else {
            _ = try frame.chunk.appendInst(self.allocator, .nil);
        }
    }

    fn generateStatement(self: *Self, frame: *Frame, stmt: ast.Statement) !void {
        switch (stmt) {
            .let => |let_stmt| {
                try self.generateExpression(frame, let_stmt.expr);
                // TODO: only handles identifier patterns for now
                _ = (try frame.declareLocal(self.allocator, let_stmt.pattern.identifier.identifier)) orelse {
                    try self.reporter.report(self.source, let_stmt.pattern.getSpan(), "variable already declared: {s}", .{let_stmt.pattern.identifier.identifier});
                    return error.CompileFailed;
                };
            },
            .expr => |expr_stmt| {
                try self.generateExpression(frame, expr_stmt.expr);
                _ = try frame.chunk.appendInst(self.allocator, .pop);
            },
        }
    }
};

const Frame = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    chunk: bytecode.Chunk = .{},
    scopes: std.ArrayListUnmanaged(Scope) = .{},

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    pub fn deinit(self: *Self) void {
        for (self.scopes.items) |*scope| {
            scope.deinit(self.allocator);
        }
        self.scopes.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn pushFreshScope(self: *Self) !void {
        try self.scopes.append(self.allocator, .{});
    }

    pub fn pushScope(self: *Self, scope: Scope) !void {
        try self.scopes.append(self.allocator, scope);
    }

    pub fn popScope(self: *Self) Scope {
        return self.scopes.pop();
    }

    pub fn declareLocal(self: *Self, allocator: std.mem.Allocator, identifier: []const u8) !?Scope.Local {
        var scope = &self.scopes.items[self.scopes.items.len - 1];
        return scope.addLocal(allocator, identifier);
    }

    pub fn getLocal(self: *const Self, identifier: []const u8) ?Scope.Local {
        _ = self.scopes.getLast();
        return self.scopes.getLast().getLocal(identifier);
    }
};

pub const Scope = struct {
    const Self = @This();

    const Local = struct {
        slot: usize,
        identifier: []const u8,
        is_captured: bool,
    };

    locals: std.ArrayListUnmanaged(Local) = .{},

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.locals.items) |*local| {
            allocator.free(local.identifier);
        }
        self.locals.deinit(allocator);
        self.* = undefined;
    }

    pub fn addLocal(self: *Self, allocator: std.mem.Allocator, identifier: []const u8) !?Local {
        if (self.getLocal(identifier)) |_| {
            return null;
        }
        const local = Local{
            .slot = self.locals.items.len,
            .identifier = try allocator.dupe(u8, identifier), // FIXME: because we don't intern strings and ast gets freed
            .is_captured = false,
        };
        try self.locals.append(allocator, local);
        return local;
    }

    pub fn getLocal(self: *const Self, identifier: []const u8) ?Local {
        var it = std.mem.reverseIterator(self.locals.items);
        while (it.next()) |local| {
            if (std.mem.eql(u8, local.identifier, identifier)) {
                return local;
            }
        }
        return null;
    }
};
