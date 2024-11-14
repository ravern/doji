const std = @import("std");
const ast = @import("ast.zig");
const scan = @import("scan.zig");
const Scanner = scan.Scanner;
const Source = @import("Source.zig");
const Reporter = @import("Reporter.zig");

pub const Parser = struct {
    const Self = @This();

    const Error = error{CompileFailed} ||
        @TypeOf(std.io.getStdErr().writer()).Error ||
        std.mem.Allocator.Error;

    const StatementOrExpression = union(enum) {
        stmt: ast.Statement,
        expr: ast.Expression,
    };

    pub const prefix_precedence = std.EnumMap(ast.Token.Kind, usize).init(.{
        .plus = 21,
        .minus = 21,
    });

    pub const infix_precedence = std.EnumMap(ast.Token.Kind, [2]usize).init(.{
        .pipe_pipe = .{ 1, 2 },
        .ampersand_ampersand = .{ 3, 4 },
        .pipe = .{ 5, 6 },
        .caret = .{ 7, 8 },
        .ampersand = .{ 9, 10 },
        .equal = .{ 11, 12 },
        .bang_equal = .{ 11, 12 },
        .less = .{ 13, 14 },
        .less_equal = .{ 13, 14 },
        .greater = .{ 13, 14 },
        .greater_equal = .{ 13, 14 },
        .greater_greater = .{ 15, 16 },
        .less_less = .{ 15, 16 },
        .plus = .{ 17, 18 },
        .minus = .{ 17, 18 },
        .asterisk = .{ 19, 20 },
        .slash = .{ 19, 20 },
        .percent = .{ 19, 20 },
    });

    reporter: *Reporter,
    source: Source,
    scanner: Scanner,
    token: ?ast.Token,

    pub fn init(reporter: *Reporter, source: Source) Self {
        return Self{
            .reporter = reporter,
            .source = source,
            .scanner = Scanner.init(reporter, source),
            .token = null,
        };
    }

    pub fn parse(self: *Self, allocator: std.mem.Allocator) !ast.Root {
        const expr = try allocator.create(ast.Expression);
        errdefer allocator.destroy(expr);
        expr.* = try self.parseExpression(allocator);
        return ast.Root{ .expr = expr };
    }

    fn parseExpression(self: *Self, allocator: std.mem.Allocator) Error!ast.Expression {
        const token = try self.peek();
        switch (token.kind) {
            .l_brace => return self.parseBlock(allocator),
            else => return self.parsePrattExpression(allocator, 0),
        }
    }

    fn parseBlock(self: *Self, allocator: std.mem.Allocator) !ast.Expression {
        const l_brace_token = try self.advance();

        var span = l_brace_token.span;
        var stmts = std.ArrayListUnmanaged(ast.Statement){};
        defer stmts.deinit(allocator);
        var ret_expr: ?ast.Expression = null;

        while (true) {
            const token = try self.peek();

            if (token.kind == .r_brace) {
                span = span.merge(token.span);
                break;
            }

            switch (try self.parseStatementOrExpression(allocator)) {
                .stmt => |stmt| try stmts.append(allocator, stmt),
                .expr => |expr| ret_expr = expr,
            }

            if (ret_expr) |_| {
                const r_brace_token = try self.peek();
                if (r_brace_token.kind != .r_brace) {
                    try self.reporter.report(self.source, r_brace_token.span, "unexpected token: {s}", .{r_brace_token.toString()});
                    return error.CompileFailed;
                }
            }
        }

        return .{ .block = try ast.Block.init(allocator, stmts.items, ret_expr, span) };
    }

    fn parseStatementOrExpression(self: *Self, allocator: std.mem.Allocator) !StatementOrExpression {
        const expr = try self.parseExpression(allocator);

        const token = try self.peek();
        if (token.kind == .semicolon) {
            _ = try self.advance();
            return .{ .stmt = .{ .expr = try ast.ExpressionStatement.init(allocator, expr, token.span) } };
        } else {
            return .{ .expr = expr };
        }
    }

    fn parsePrattExpression(self: *Self, allocator: std.mem.Allocator, min_precedence: usize) Error!ast.Expression {
        var left = try self.parsePrattPrefix(allocator);

        while (true) {
            const token = try self.peek();
            const precedence = infix_precedence.get(token.kind) orelse break;

            if (precedence[0] < min_precedence) break;

            const op_token = try self.advance();
            const op = ast.BinaryExpression.Op.fromTokenKind(op_token.kind);

            const right = try self.parsePrattExpression(allocator, precedence[1]);

            left = .{ .binary = try ast.BinaryExpression.init(allocator, op, left, right) };
        }

        return left;
    }

    fn parsePrattPrefix(self: *Self, allocator: std.mem.Allocator) !ast.Expression {
        const token = try self.peek();
        const precedence = prefix_precedence.get(token.kind) orelse return self.parsePrattPrimary(allocator);

        const op_token = try self.advance();
        const op = ast.UnaryExpression.Op.fromTokenKind(op_token.kind);

        const expr = try self.parsePrattExpression(allocator, precedence);
        return .{ .unary = try ast.UnaryExpression.init(allocator, op, expr) };
    }

    fn parsePrattPrimary(self: *Self, allocator: std.mem.Allocator) !ast.Expression {
        const token = try self.advance();
        return switch (token.kind) {
            .nil => .{ .nil = token.span },
            .true => .{ .true = token.span },
            .false => .{ .false = token.span },
            .int => .{
                .int = .{
                    .span = token.span,
                    .int = std.fmt.parseInt(i48, self.source.contentSlice(token.span), 0) catch unreachable,
                },
            },
            .float => .{
                .float = .{
                    .span = token.span,
                    .float = std.fmt.parseFloat(f64, self.source.contentSlice(token.span)) catch unreachable,
                },
            },
            .identifier => .{
                .identifier = .{
                    .identifier = try allocator.dupe(u8, self.source.contentSlice(token.span)),
                    .span = token.span,
                },
            },
            else => {
                try self.reporter.report(self.source, token.span, "unexpected token: {s}", .{token.toString()});
                return error.CompileFailed;
            },
        };
    }

    fn advance(self: *Self) !ast.Token {
        const token = try self.peek();
        self.token = null;
        return token;
    }

    fn peek(self: *Self) !ast.Token {
        if (self.token) |token| return token;
        self.token = try self.scanner.next();
        return self.token.?;
    }
};
