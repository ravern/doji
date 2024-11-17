const std = @import("std");
const ast = @import("ast.zig");
const compile = @import("../compile.zig");
const Scanner = @import("Scanner.zig");
const Source = @import("../Source.zig");

const Self = @This();

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

context: *compile.Context,
source: *const Source,
scanner: Scanner,
token: ?ast.Token,

pub fn init(context: *compile.Context, source: *const Source) Self {
    return Self{
        .context = context,
        .source = source,
        .scanner = Scanner.init(context, source),
        .token = null,
    };
}

pub fn parse(self: *Self) !ast.Module {
    const block = try self.parseBlock(Source.Span.zero, .eof);
    return ast.Module.init(self.context.allocator, block);
}

fn parseBlock(self: *Self, init_span: Source.Span, term_token_kind: ast.Token.Kind) !ast.Block {
    var span = init_span;
    var stmts = std.ArrayListUnmanaged(ast.Statement){};
    defer stmts.deinit(self.context.allocator);
    var ret_expr: ?ast.Expression = null;

    while (true) {
        const token = try self.peek();

        if (token.kind == term_token_kind) {
            _ = try self.expect(term_token_kind);
            span = span.merge(token.span);
            break;
        }

        switch (try self.parseStatementOrExpression()) {
            .stmt => |stmt| try stmts.append(self.context.allocator, stmt),
            .expr => |expr| ret_expr = expr,
        }

        if (ret_expr) |_| {
            const term_token = try self.peek();
            if (term_token.kind != term_token_kind) {
                self.printError(term_token);
                return error.CompileFailed;
            }
        }
    }

    return ast.Block.init(self.context.allocator, stmts.items, ret_expr, span);
}

fn parseStatementOrExpression(self: *Self) !StatementOrExpression {
    const token = try self.peek();
    switch (token.kind) {
        .let => return .{ .stmt = try self.parseLetStatement() },
        else => {
            const expr = try self.parseExpression();
            const semicolon_token = try self.peek();
            if (semicolon_token.kind == .semicolon) {
                _ = try self.expect(.semicolon);
                return .{ .stmt = .{ .expr = try ast.ExpressionStatement.init(self.context.allocator, expr, token.span) } };
            } else {
                return .{ .expr = expr };
            }
        },
    }
}

fn parseLetStatement(self: *Self) !ast.Statement {
    const let_token = try self.expect(.let);
    const pattern = try self.parsePattern();
    _ = try self.expect(.equal);
    const expr = try self.parseExpression();
    _ = try self.expect(.semicolon);
    return .{ .let = try ast.LetStatement.init(self.context.allocator, pattern, expr, let_token.span.merge(expr.getSpan())) };
}

fn parseExpression(self: *Self) compile.Error!ast.Expression {
    const token = try self.peek();
    switch (token.kind) {
        .l_brace => return self.parseBlockExpression(),
        else => return self.parsePrattExpression(0),
    }
}

fn parseBlockExpression(self: *Self) !ast.Expression {
    const l_brace_token = try self.expect(.l_brace);
    return .{ .block = try self.parseBlock(l_brace_token.span, .r_brace) };
}

fn parsePrattExpression(self: *Self, min_precedence: usize) compile.Error!ast.Expression {
    var left = try self.parsePrattPrefix();

    while (true) {
        const token = try self.peek();
        const precedence = infix_precedence.get(token.kind) orelse break;

        if (precedence[0] < min_precedence) break;

        const op_token = try self.advance();
        const op = ast.BinaryExpression.Op.fromTokenKind(op_token.kind);

        const right = try self.parsePrattExpression(self.context.allocator, precedence[1]);

        left = .{ .binary = try ast.BinaryExpression.init(self.context.allocator, op, left, right, left.getSpan().merge(right.getSpan())) };
    }

    return left;
}

fn parsePrattPrefix(self: *Self) !ast.Expression {
    const token = try self.peek();
    const precedence = prefix_precedence.get(token.kind) orelse return self.parsePrattPrimary(self.context.allocator);

    const op_token = try self.advance();
    const op = ast.UnaryExpression.Op.fromTokenKind(op_token.kind);

    const expr = try self.parsePrattExpression(self.context.allocator, precedence);
    return .{ .unary = try ast.UnaryExpression.init(self.context.allocator, op, expr, op_token.span.merge(expr.getSpan())) };
}

fn parsePrattPrimary(self: *Self) !ast.Expression {
    const token = try self.peek();
    return switch (token.kind) {
        .nil => {
            _ = try self.advance();
            return .{ .nil = token.span };
        },
        .true => {
            _ = try self.advance();
            return .{ .true = token.span };
        },
        .false => {
            _ = try self.advance();
            return .{ .false = token.span };
        },
        .int => {
            _ = try self.advance();
            return .{
                .int = .{
                    .span = token.span,
                    .int = std.fmt.parseInt(i48, self.source.contentSlice(token.span), 0) catch unreachable,
                },
            };
        },
        .float => {
            _ = try self.advance();
            return .{
                .float = .{
                    .span = token.span,
                    .float = std.fmt.parseFloat(f64, self.source.contentSlice(token.span)) catch unreachable,
                },
            };
        },
        .identifier => return .{
            .identifier = try self.parseIdentifier(),
        },
        else => {
            self.printError(token);
            return error.CompileFailed;
        },
    };
}

fn parsePattern(self: *Self) !ast.Pattern {
    const token = try self.peek();
    return switch (token.kind) {
        .identifier => .{ .identifier = try self.parseIdentifier() },
        else => {
            self.printError(token);
            return error.CompileFailed;
        },
    };
}

fn parseIdentifier(self: *Self) !ast.Identifier {
    const token = try self.expect(.identifier);
    return .{
        .identifier = try self.context.string_pool.intern(self.source.getContentSpan(token.span)),
        .span = token.span,
    };
}

fn printError(self: *Self, token: ast.Token) void {
    std.debug.print(
        "{s}:{d}:{d}: unexpected token: {s}\n",
        .{ self.source.getPath(), token.span.start.line, token.span.start.col, token.kind.toString() },
    );
}

fn expect(self: *Self, kind: ast.Token.Kind) !ast.Token {
    const token = try self.advance();
    if (token.kind != kind) {
        self.printError(token);
        return error.CompileFailed;
    }
    return token;
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
