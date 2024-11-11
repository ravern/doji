const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const ascii = std.ascii;
const testing = std.testing;

const errors = @import("../errors.zig");
const Error = errors.Error;
const DojiError = errors.DojiError;
const CompileError = errors.CompileError;
const UnexpectedCharError = errors.UnexpectedCharError;
const ExpectedChar = errors.ExpectedChar;
const Environment = @import("../global.zig").Environment;
const Span = @import("../Span.zig");

pub const Token = enum {
    end_of_input,
    nil,
    bool,
    int,
    float,
    identifier,
};

pub const Lexeme = struct {
    token: Token,
    span: Span,
};

pub const Lexer = struct {
    env: *Environment,
    source: []const u8,
    span: Span = Span.initZero(),

    pub fn init(env: *Environment, source: []const u8) Lexer {
        return Lexer{
            .env = env,
            .source = source,
        };
    }

    pub fn next(self: *Lexer, allocator: Allocator) !Lexeme {
        self.skipWhitespace();
        const c = self.peek() orelse return self.buildLexeme(Token.end_of_input);
        if (ascii.isDigit(c)) {
            return self.nextNumber(allocator);
        } else if (ascii.isAlphabetic(c) or c == '_') {
            return self.nextIdentifier();
        } else {
            try self.reportUnexpectedCharError(allocator, c, &.{.Digit});
            return error.CompileFailed;
        }
    }

    fn nextNumber(self: *Lexer, allocator: Allocator) !Lexeme {
        assert(ascii.isDigit(self.peek().?));
        var is_float = false;
        while (true) : (_ = self.advance()) {
            const c = self.peek() orelse break;
            if (c == '.') {
                if (is_float) {
                    try self.reportUnexpectedCharError(allocator, c, &.{.{ .Char = '.' }});
                    return error.CompileFailed;
                }
                is_float = true;
            } else if (!ascii.isDigit(c)) {
                break;
            }
        }
        const token = if (is_float) Token.float else Token.int;
        return self.buildLexeme(token);
    }

    fn nextIdentifier(self: *Lexer) !Lexeme {
        assert(ascii.isAlphabetic(self.peek().?));
        while (true) : (_ = self.advance()) {
            const c = self.peek() orelse break;
            if (!ascii.isAlphabetic(c) and !ascii.isDigit(c) and c != '_') {
                break;
            }
        }
        if (mem.eql(u8, self.span.toString(self.source), "nil")) {
            return self.buildLexeme(Token.nil);
        } else if (mem.eql(u8, self.span.toString(self.source), "true") or
            mem.eql(u8, self.span.toString(self.source), "false"))
        {
            return self.buildLexeme(Token.bool);
        }
        return self.buildLexeme(Token.identifier);
    }

    fn skipWhitespace(self: *Lexer) void {
        while (true) : (_ = self.advance()) {
            const c = self.peek() orelse break;
            if (!ascii.isWhitespace(c)) {
                break;
            }
        }
    }

    fn buildLexeme(self: *Lexer, token: Token) Lexeme {
        const span = self.span;
        self.span = Span.init(self.span.getEnd());
        return Lexeme{
            .token = token,
            .span = span,
        };
    }

    fn reportUnexpectedCharError(
        self: *Lexer,
        allocator: Allocator,
        unexpected: u8,
        expected: []const ExpectedChar,
    ) !void {
        self.env.reportError(Error{
            .Compile = CompileError{
                .UnexpectedChar = UnexpectedCharError{
                    .span = Span{
                        .start = self.span.getEnd(),
                        .len = 1,
                    },
                    .unexpected = unexpected,
                    .expected = try allocator.dupe(ExpectedChar, expected),
                },
            },
        });
    }

    fn peek(self: *const Lexer) ?u8 {
        if (self.span.getEnd() >= self.source.len) {
            return null;
        }
        return self.source[self.span.getEnd()];
    }

    fn advance(self: *Lexer) ?u8 {
        const c = self.peek();
        if (self.span.getEnd() < self.source.len) {
            self.span.len += 1;
        }
        return c;
    }
};

fn testLex(allocator: Allocator, source: []const u8) !Lexeme {
    var env = Environment.init(allocator);
    var lexer = Lexer.init(&env, source);
    return lexer.next(allocator);
}

test "nil" {
    const allocator = testing.allocator;
    const lexeme = try testLex(allocator, "nil");
    try testing.expectEqual(lexeme.token, Token.nil);
}

test "bool" {
    const allocator = testing.allocator;
    const lexeme = try testLex(allocator, "true");
    try testing.expectEqual(lexeme.token, Token.bool);
}

test "int" {
    const allocator = testing.allocator;
    const lexeme = try testLex(allocator, "123");
    try testing.expectEqual(lexeme.token, Token.int);
}

test "float" {
    const allocator = testing.allocator;
    const lexeme = try testLex(allocator, "3.14159");
    try testing.expectEqual(lexeme.token, Token.float);
}

test "identifier" {
    const allocator = testing.allocator;
    const lexeme = try testLex(allocator, "foo");
    try testing.expectEqual(lexeme.token, Token.identifier);
}
