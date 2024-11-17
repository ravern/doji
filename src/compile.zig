const std = @import("std");
const ast = @import("ast.zig");
const bytecode = @import("bytecode.zig");
const Report = @import("Report.zig");
const Source = @import("Source.zig");
const Span = @import("Span.zig");
const Value = @import("Value.zig");
const GC = @import("GC.zig");

pub const GlobalScope = struct {
    locals: [][]const u8 = &.{},

    pub fn deinit(self: *GlobalScope, allocator: std.mem.Allocator) void {
        for (self.locals) |local| {
            allocator.free(local);
        }
        self.* = undefined;
    }
};

pub const Error =
    @TypeOf(std.io.getStdErr().writer()).Error ||
    std.mem.Allocator.Error ||
    error{CompileFailed};

pub const Context = struct {
    allocator: std.mem.Allocator,
    gc: *GC,
    report: *Report,
    global_scope: *GlobalScope,
};

pub fn compile(context: Context, source: Source) Error!bytecode.Chunk {
    var parser = Parser.init(context, source);
    defer parser.deinit();
    const root = try parser.parse();
    defer root.deinit(context.allocator);

    var generator = Generator.init(context, source);
    defer generator.deinit();
    const chunk = try generator.generate(root);

    return chunk;
}

const Scanner = struct {
    const punctuation = std.StaticStringMap(ast.Token.Tag).initComptime(.{
        .{ "+", .plus },
        .{ "-", .minus },
        .{ "*", .asterisk },
        .{ "/", .slash },
        .{ "%", .percent },
        .{ "=", .equal },
        .{ "!", .bang },
        .{ "<", .less },
        .{ ">", .greater },
        .{ "&", .ampersand },
        .{ "|", .pipe },
        .{ "^", .caret },
        .{ "~", .tilde },
        .{ ".", .period },
        .{ ",", .comma },
        .{ ":", .colon },
        .{ ";", .semicolon },
        .{ "{", .l_brace },
        .{ "}", .r_brace },
        .{ "(", .l_paren },
        .{ ")", .r_paren },
        .{ "[", .l_bracket },
        .{ "]", .r_bracket },
    });

    const punctuation2 = std.StaticStringMap(ast.Token.Tag).initComptime(.{
        .{ "+=", .plus_equal },
        .{ "-=", .minus_equal },
        .{ "*=", .asterisk_equal },
        .{ "/=", .slash_equal },
        .{ "%=", .percent_equal },
        .{ "==", .equal_equal },
        .{ "!=", .bang_equal },
        .{ "<=", .less_equal },
        .{ ">=", .greater_equal },
        .{ "&&", .ampersand_ampersand },
        .{ "||", .pipe_pipe },
        .{ "<<", .less_less },
        .{ ">>", .greater_greater },
    });

    const keywords = std.StaticStringMap(ast.Token.Tag).initComptime(.{
        .{ "nil", .nil },
        .{ "true", .true },
        .{ "false", .false },
        .{ "let", .let },
    });

    context: Context,
    source: Source,
    accumulated_span: Span,

    fn init(context: Context, source: Source) Scanner {
        return Scanner{
            .context = context,
            .source = source,
            .accumulated_span = Span.zero,
        };
    }

    fn next(self: *Scanner) !ast.Token {
        self.skipWhitespace();
        const c = self.peek() orelse return ast.Token{
            .tag = .eof,
            .span = self.accumulated_span,
        };
        if (punctuation.get(&.{c})) |tag| {
            self.advance();
            const c2 = self.peek() orelse return self.buildToken(tag);
            if (punctuation2.get(&.{ c, c2 })) |tag2| {
                self.advance();
                return self.buildToken(tag2);
            }
            return self.buildToken(tag);
        } else if (std.ascii.isDigit(c)) {
            return self.nextNumber();
        } else if (std.ascii.isAlphabetic(c)) {
            return self.nextIdentifier();
        } else {
            try self.context.report.appendItem(.@"error", self.context.source, self.accumulated_span.start, "unexpected character: '{c}'", .{c});
            return error.CompileFailed;
        }
    }

    fn nextNumber(self: *Scanner) !ast.Token {
        self.advance();
        var is_float = false;
        while (true) {
            const c = self.peek() orelse break;
            if (c == '.' and !is_float) {
                is_float = true;
                self.advance();
                continue;
            }
            if (!std.ascii.isDigit(c)) break;
            self.advance();
        }
        return self.buildToken(if (is_float) .float else .int);
    }

    fn nextIdentifier(self: *Scanner) !ast.Token {
        self.advance();
        while (true) {
            const c = self.peek() orelse break;
            if (!std.ascii.isAlphabetic(c) and !std.ascii.isDigit(c) and c != '_') break;
            self.advance();
        }
        const identifier = self.source.getContentSpan(self.accumulated_span);
        if (keywords.get(identifier)) |tag| return self.buildToken(tag);
        return self.buildToken(.identifier);
    }

    fn skipWhitespace(self: *Scanner) void {
        while (true) {
            const c = self.peek() orelse break;
            if (!std.ascii.isWhitespace(c)) break;
            self.advance();
        }
        self.resetSpan();
    }

    fn buildToken(self: *Scanner, tag: ast.Token.Tag) ast.Token {
        const token = ast.Token{
            .tag = tag,
            .span = self.accumulated_span,
        };
        self.resetSpan();
        return token;
    }

    fn resetSpan(self: *Scanner) void {
        self.accumulated_span.start = self.accumulated_span.end;
    }

    fn advance(self: *Scanner) void {
        const c = self.peek() orelse return;
        if (c == '\n') {
            self.accumulated_span.end.line += 1;
            self.accumulated_span.end.col = 1;
        } else {
            self.accumulated_span.end.col += 1;
        }
        self.accumulated_span.end.offset += 1;
    }

    fn peek(self: *Scanner) ?u8 {
        if (self.accumulated_span.end.offset >= self.source.content.len) {
            return null;
        }
        return self.source.content[self.accumulated_span.end.offset];
    }
};

const Parser = struct {
    const StatementOrExpression = union(enum) {
        stmt: ast.Statement,
        expr: ast.Expression,
    };

    const prefix_precedence = std.EnumMap(ast.Token.Tag, usize).init(.{
        .plus = 21,
        .minus = 21,
    });

    const infix_precedence = std.EnumMap(ast.Token.Tag, [2]usize).init(.{
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

    context: Context,
    source: Source,
    scanner: Scanner,
    token: ?ast.Token,

    fn init(context: Context, source: Source) Parser {
        return Parser{
            .context = context,
            .source = source,
            .scanner = Scanner.init(context, source),
            .token = null,
        };
    }

    fn parse(self: *Parser) !ast.Root {
        const block = try self.parseBlock(Span.zero, .eof);
        return ast.Root.init(self.context.allocator, block);
    }

    fn parseBlock(self: *Parser, init_span: Span, term_token_tag: ast.Token.Tag) !ast.Block {
        var span = init_span;
        var stmts = std.ArrayListUnmanaged(ast.Statement){};
        defer stmts.deinit(self.context.allocator);
        var ret_expr: ?ast.Expression = null;

        while (true) {
            const token = try self.peek();

            if (token.tag == term_token_tag) {
                _ = try self.expect(term_token_tag);
                span = span.merge(token.span);
                break;
            }

            switch (try self.parseStatementOrExpression(self.context.allocator)) {
                .stmt => |stmt| try stmts.append(self.context.allocator, stmt),
                .expr => |expr| ret_expr = expr,
            }

            if (ret_expr) |_| {
                const term_token = try self.peek();
                if (term_token.tag != term_token_tag) {
                    try self.reporter.report(self.source, term_token.span, "unexpected token: {s}", .{term_token.tag.toString()});
                    return error.CompileFailed;
                }
            }
        }

        return ast.Block.init(self.context.allocator, stmts.items, ret_expr, span);
    }

    fn parseStatementOrExpression(self: *Parser) !StatementOrExpression {
        const token = try self.peek();
        switch (token.tag) {
            .let => return .{ .stmt = try self.parseLetStatement() },
            else => {
                const expr = try self.parseExpression();
                const semicolon_token = try self.peek();
                if (semicolon_token.tag == .semicolon) {
                    _ = try self.expect(.semicolon);
                    return .{ .stmt = .{ .expr = try ast.ExpressionStatement.init(self.context.allocator, expr, token.span) } };
                } else {
                    return .{ .expr = expr };
                }
            },
        }
    }

    fn parseLetStatement(self: *Parser) !ast.Statement {
        const let_token = try self.expect(.let);
        const pattern = try self.parsePattern();
        _ = try self.expect(.equal);
        const expr = try self.parseExpression();
        _ = try self.expect(.semicolon);
        return .{ .let = try ast.LetStatement.init(self.context.allocator, pattern, expr, let_token.span.merge(expr.getSpan())) };
    }

    fn parseExpression(self: *Parser) Error!ast.Expression {
        const token = try self.peek();
        switch (token.tag) {
            .l_brace => return self.parseBlockExpression(),
            else => return self.parsePrattExpression(0),
        }
    }

    fn parseBlockExpression(self: *Parser) !ast.Expression {
        const l_brace_token = try self.expect(.l_brace);
        return .{ .block = try self.parseBlock(l_brace_token.span, .r_brace) };
    }

    fn parsePrattExpression(self: *Parser, min_precedence: usize) Error!ast.Expression {
        var left = try self.parsePrattPrefix();

        while (true) {
            const token = try self.peek();
            const precedence = infix_precedence.get(token.tag) orelse break;

            if (precedence[0] < min_precedence) break;

            const op_token = try self.advance();
            const op = ast.BinaryExpression.Op.fromTokenTag(op_token.tag);

            const right = try self.parsePrattExpression(precedence[1]);

            left = .{ .binary = try ast.BinaryExpression.init(self.context.allocator, op, left, right, left.getSpan().merge(right.getSpan())) };
        }

        return left;
    }

    fn parsePrattPrefix(self: *Parser) !ast.Expression {
        const token = try self.peek();
        const precedence = prefix_precedence.get(token.tag) orelse return self.parsePrattPrimary();

        const op_token = try self.advance();
        const op = ast.UnaryExpression.Op.fromTokenTag(op_token.tag);

        const expr = try self.parsePrattExpression(precedence);
        return .{ .unary = try ast.UnaryExpression.init(self.context.allocator, op, expr, op_token.span.merge(expr.getSpan())) };
    }

    fn parsePrattPrimary(self: *Parser) !ast.Expression {
        const token = try self.peek();
        return switch (token.tag) {
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
                        .int = std.fmt.parseInt(i48, self.source.getContentSpan(token.span), 0) catch unreachable,
                    },
                };
            },
            .float => {
                _ = try self.advance();
                return .{
                    .float = .{
                        .span = token.span,
                        .float = std.fmt.parseFloat(f64, self.source.getContentSpan(token.span)) catch unreachable,
                    },
                };
            },
            .identifier => return .{
                .identifier = try self.parseIdentifier(),
            },
            else => {
                try self.reporter.report(self.source, token.span, "unexpected token: {s}", .{token.tag.toString()});
                return error.CompileFailed;
            },
        };
    }

    fn parsePattern(self: *Parser) !ast.Pattern {
        const token = try self.peek();
        return switch (token.tag) {
            .identifier => .{ .identifier = try self.parseIdentifier() },
            else => {
                try self.reporter.report(self.source, token.span, "unexpected token: {s}", .{token.tag.toString()});
                return error.CompileFailed;
            },
        };
    }

    fn parseIdentifier(self: *Parser) !ast.Identifier {
        const token = try self.expect(.identifier);
        return .{
            .identifier = try self.context.gc.internString(self.source.getContentSpan(token.span)),
            .span = token.span,
        };
    }

    fn expect(self: *Parser, tag: ast.Token.Tag) !ast.Token {
        const token = try self.advance();
        if (token.tag != tag) {
            try self.reporter.report(self.source, token.span, "unexpected token: {s}", .{token.tag.toString()});
            return error.CompileFailed;
        }
        return token;
    }

    fn advance(self: *Parser) !ast.Token {
        const token = try self.peek();
        self.token = null;
        return token;
    }

    fn peek(self: *Parser) !ast.Token {
        if (self.token) |token| return token;
        self.token = try self.scanner.next();
        return self.token.?;
    }
};

const Generator = struct {
    const Frame = struct {
        allocator: std.mem.Allocator,
        chunk: bytecode.Chunk = .{},
        scopes: std.ArrayListUnmanaged(Scope) = .{},

        fn init(allocator: std.mem.Allocator) Frame {
            return Frame{ .allocator = allocator };
        }

        fn deinit(self: *Frame) void {
            for (self.scopes.items) |*scope| {
                scope.deinit(self.allocator);
            }
            self.scopes.deinit(self.allocator);
            self.* = undefined;
        }

        fn pushFreshScope(self: *Frame) !void {
            try self.scopes.append(self.allocator, .{});
        }

        fn pushScope(self: *Frame, scope: Scope) !void {
            try self.scopes.append(self.allocator, scope);
        }

        fn popScope(self: *Frame) Scope {
            return self.scopes.pop();
        }

        fn declareLocal(self: *Frame, allocator: std.mem.Allocator, identifier: []const u8) !?Scope.Local {
            var scope = &self.scopes.items[self.scopes.items.len - 1];
            return scope.addLocal(allocator, identifier);
        }

        fn getLocal(self: *const Frame, identifier: []const u8) ?Scope.Local {
            _ = self.scopes.getLast();
            return self.scopes.getLast().getLocal(identifier);
        }
    };

    const Scope = struct {
        const Local = struct {
            slot: usize,
            identifier: []const u8,
            is_captured: bool,
        };

        locals: std.ArrayListUnmanaged(Local) = .{},

        fn deinit(self: *Scope, allocator: std.mem.Allocator) void {
            for (self.locals.items) |*local| {
                allocator.free(local.identifier);
            }
            self.locals.deinit(allocator);
            self.* = undefined;
        }

        fn addLocal(self: *Scope, allocator: std.mem.Allocator, identifier: []const u8) !?Local {
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

        fn getLocal(self: *const Scope, identifier: []const u8) ?Local {
            var it = std.mem.reverseIterator(self.locals.items);
            while (it.next()) |local| {
                if (std.mem.eql(u8, local.identifier, identifier)) {
                    return local;
                }
            }
            return null;
        }
    };

    context: Context,
    source: Source,

    fn init(context: Context, source: Source) Generator {
        return Generator{
            .context = context,
            .source = source,
        };
    }

    fn generate(self: *Generator, root: ast.Root) !bytecode.Chunk {
        var scope = Scope{};
        defer scope.deinit(self.context.allocator);
        return self.generateWithScope(&scope, root);
    }

    // TODO: generate global scope
    fn generateWithScope(self: *Generator, scope: *Scope, root: ast.Root) !bytecode.Chunk {
        var frame = Frame.init(self.allocator);
        defer frame.deinit();
        try frame.pushScope(scope.*);
        try self.generateBlock(&frame, root.block);
        _ = try frame.chunk.appendInstruction(self.allocator, .ret);
        scope.* = frame.popScope();
        return frame.chunk;
    }

    fn generateExpression(self: *Generator, frame: *Frame, expr: *const ast.Expression) Error!void {
        switch (expr.*) {
            .nil => {
                _ = try frame.chunk.appendInstruction(self.allocator, .nil);
            },
            .true => {
                _ = try frame.chunk.appendInstruction(self.allocator, .true);
            },
            .false => {
                _ = try frame.chunk.appendInstruction(self.allocator, .false);
            },
            .int => |int| {
                // FIXME: check for int size
                _ = try frame.chunk.appendInstructionArg(self.allocator, .int, @intCast(int.int));
            },
            .float => |float| {
                const index = try frame.chunk.appendConstant(self.allocator, Value.initFloat(float.float));
                _ = try frame.chunk.appendInstructionArg(self.allocator, .constant, @intCast(index));
            },
            .identifier => |identifier| {
                if (frame.getLocal(identifier.identifier)) |local| {
                    _ = try frame.chunk.appendInstructionArg(self.allocator, .local, @intCast(local.slot));
                } else {
                    try self.reporter.report(self.source, identifier.span, "undefined variable: {s}", .{identifier.identifier});
                    return error.CompileFailed;
                }
            },
            .unary => |unary| {
                try self.generateExpression(frame, unary.expr);
                _ = try frame.chunk.appendInstruction(self.allocator, bytecode.Instruction.Op.fromUnaryOp(unary.op));
            },
            .binary => |binary| {
                try self.generateExpression(frame, binary.left);
                try self.generateExpression(frame, binary.right);
                _ = try frame.chunk.appendInstruction(self.allocator, bytecode.Instruction.Op.fromBinaryOp(binary.op));
            },
            .block => |block| {
                try frame.pushFreshScope();
                try self.generateBlock(frame, &block);
                var scope = frame.popScope();
                defer scope.deinit(self.allocator);
            },
        }
    }

    fn generateBlock(self: *Generator, frame: *Frame, block: *const ast.Block) !void {
        for (block.stmts) |stmt| {
            try self.generateStatement(frame, stmt);
        }

        if (block.ret_expr) |ret_expr| {
            try self.generateExpression(frame, ret_expr);
        } else {
            _ = try frame.chunk.appendInstruction(self.allocator, .nil);
        }
    }

    fn generateStatement(self: *Generator, frame: *Frame, stmt: ast.Statement) !void {
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
                _ = try frame.chunk.appendInstruction(self.allocator, .pop);
            },
        }
    }
};
