const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const fmt = std.fmt;
const testing = std.testing;
const assert = std.debug.assert;

const ast = @import("./ast.zig");
const errors = @import("../errors.zig");
const ExpectedToken = errors.ExpectedToken;
const UnexpectedTokenError = errors.UnexpectedTokenError;
const DojiError = errors.DojiError;
const Error = errors.Error;
const CompileError = errors.CompileError;
const Environment = @import("../global.zig").Environment;
const Span = @import("../Span.zig");
const lex = @import("./lex.zig");
const Lexer = lex.Lexer;
const Lexeme = lex.Lexeme;
const Token = lex.Token;

pub const Parser = struct {
    env: *Environment,
    lexer: Lexer,
    lexeme: ?Lexeme,

    pub fn init(env: *Environment, source: []const u8) Parser {
        return Parser{
            .env = env,
            .lexer = Lexer.init(env, source),
            .lexeme = null,
        };
    }

    pub fn parse(self: *Parser, allocator: Allocator) !ast.File {
        const block = try self.parseBlock(allocator);
        return ast.File{ .block = block };
    }

    fn parseBlock(self: *Parser, allocator: Allocator) !ast.Block {
        const statements = try allocator.alloc(ast.Statement, 0);
        const return_expression = try allocator.create(ast.Expression);
        return_expression.* = try self.parseExpression(allocator);
        return ast.Block{
            .span = Span.initZero(), // TODO
            .statements = statements,
            .return_expression = return_expression,
        };
    }

    fn parseExpression(self: *Parser, allocator: Allocator) !ast.Expression {
        const lexeme = try self.peek(allocator);
        return switch (lexeme.token) {
            .nil => {
                _ = try self.advance(allocator);
                return ast.Expression{ .Literal = ast.Literal{ .Nil = lexeme.span } };
            },
            .bool => {
                const bool_literal = try self.parseBoolLiteral(allocator);
                return ast.Expression{ .Literal = ast.Literal{ .Bool = bool_literal } };
            },
            .int => {
                const int_literal = try self.parseIntLiteral(allocator);
                return ast.Expression{ .Literal = ast.Literal{ .Int = int_literal } };
            },
            .float => {
                const float_literal = try self.parseFloatLiteral(allocator);
                return ast.Expression{ .Literal = ast.Literal{ .Float = float_literal } };
            },
            else => unreachable,
        };
    }

    fn parseBoolLiteral(self: *Parser, allocator: Allocator) !ast.BoolLiteral {
        const lexeme = try self.advance(allocator);
        assert(lexeme.token == Token.bool);
        const bool_string = lexeme.span.toString(self.lexer.source);
        return ast.BoolLiteral{
            .span = lexeme.span,
            .bool = parseBool(bool_string) catch unreachable,
        };
    }

    fn parseIntLiteral(self: *Parser, allocator: Allocator) !ast.IntLiteral {
        const lexeme = try self.advance(allocator);
        assert(lexeme.token == Token.int);
        const int_string = lexeme.span.toString(self.lexer.source);
        const int = fmt.parseInt(u64, int_string, 10) catch |err| switch (err) {
            error.Overflow => {
                self.reportIntLiteralOverflowError(lexeme.span);
                return error.CompileFailed;
            },
            else => unreachable,
        };
        return ast.IntLiteral{
            .span = lexeme.span,
            .int = int,
        };
    }

    fn parseFloatLiteral(self: *Parser, allocator: Allocator) !ast.FloatLiteral {
        const lexeme = try self.advance(allocator);
        assert(lexeme.token == Token.float);
        const float_string = lexeme.span.toString(self.lexer.source);
        const float = fmt.parseFloat(f64, float_string) catch unreachable;
        return ast.FloatLiteral{
            .span = lexeme.span,
            .float = float,
        };
    }

    fn reportIntLiteralOverflowError(self: *Parser, span: Span) void {
        self.env.reportError(Error{
            .Compile = CompileError{ .IntLiteralOverflow = span },
        });
    }

    fn reportUnexpectedTokenError(
        self: *Parser,
        allocator: Allocator,
        span: Span,
        unexpected: Token,
        expected: []const ExpectedToken,
    ) void {
        self.env.reportError(Error{
            .Compile = CompileError{
                .UnexpectedToken = UnexpectedTokenError{
                    .span = span,
                    .unexpected = unexpected,
                    .expected = try allocator.dupe(ExpectedToken, expected),
                },
            },
        });
    }

    fn peek(self: *Parser, allocator: Allocator) !Lexeme {
        if (self.lexeme) |lexeme| {
            return lexeme;
        } else {
            const lexeme = try self.lexer.next(allocator);
            self.lexeme = lexeme;
            return lexeme;
        }
    }

    fn advance(self: *Parser, allocator: Allocator) !Lexeme {
        const lexeme = try self.peek(allocator);
        self.lexeme = null;
        return lexeme;
    }
};

fn parseBool(s: []const u8) !bool {
    if (mem.eql(u8, "true", s)) {
        return true;
    } else if (mem.eql(u8, "false", s)) {
        return false;
    } else {
        return error.InvalidCharacter;
    }
}

fn testParse(allocator: Allocator, source: []const u8) !ast.File {
    var env = Environment.init(allocator);
    var parser = Parser.init(&env, source);
    return parser.parse(allocator);
}

test "int" {
    const allocator = testing.allocator;
    const file = try testParse(allocator, "123");
    defer file.deinit(allocator);
    try testing.expectEqual(file.block.return_expression.?.Literal.Int.int, 123);
}

test "float" {
    const allocator = testing.allocator;
    const file = try testParse(allocator, "3.14159");
    defer file.deinit(allocator);
    try testing.expectEqual(file.block.return_expression.?.Literal.Float.float, 3.14159);
}
