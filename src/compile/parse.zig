const std = @import("std");
const Context = @import("../compile.zig").Context;
const Error = @import("../compile.zig").Error;
const ParseError = @import("../compile.zig").ParseError;
const String = @import("../value.zig").String;
const Source = @import("../source.zig").Source;
const ast = @import("ast.zig");
const Token = @import("scan.zig").Token;
const Scanner = @import("scan.zig").Scanner;

pub const Parser = struct {
    ctx: *Context,
    err: *Error,
    scanner: Scanner,
    curr_token: ?Token = null,

    pub fn init(ctx: *Context, err: *Error) Parser {
        return .{
            .ctx = ctx,
            .err = err,
            .scanner = Scanner.init(ctx.source, err),
        };
    }

    pub fn parse(self: *Parser) !ast.Block {
        return .{
            .statements = try self.parseBlockStatements(.end_of_input),
            .span = .{ .offset = 0, .len = self.ctx.source.content.len },
        };
    }

    fn parseBlockStatements(self: *Parser, term_ty: Token.Type) ![]ast.Statement {
        var statements = std.ArrayList(ast.Statement).init(self.ctx.allocator);
        while (true) {
            const token = try self.peek();
            if (token.ty == term_ty) break;
            const statement = switch (token.ty) {
                else => {
                    const expression = try self.parseExpression();
                    const token2 = try self.peek();
                    if (token2.ty != .semicolon and token2.ty != term_ty) {
                        return self.parseError([]ast.Statement, token, &.{.{ .token = .semicolon }});
                    }
                    try statements.append(.{ .expression = expression });
                    continue;
                },
            };
            try statements.append(statement);
        }
        return statements.toOwnedSlice();
    }

    fn parseExpression(self: *Parser) !ast.Expression {
        const token = try self.peek();
        return switch (token.ty) {
            .identifier => .{ .identifier = try self.parseIdentifier() },
            .int, .float, .true, .false => .{ .literal = try self.parseLiteral() },
            else => self.parseError(ast.Expression, token, &.{.expression}),
        };
    }

    fn parseIdentifier(self: *Parser) !ast.Identifier {
        const token = try self.expect(.identifier);
        const identifier = try self.ctx.string_pool.intern(self.ctx.source.getSlice(token.span));
        return .{ .identifier = identifier, .span = token.span };
    }

    fn parseLiteral(self: *Parser) !ast.Literal {
        const token = try self.peek();
        self.advance();
        const str = self.ctx.source.getSlice(token.span);
        return switch (token.ty) {
            .int => .{ .int = .{ .value = try std.fmt.parseInt(i48, str, 10), .span = token.span } },
            .float => .{ .float = .{ .value = try std.fmt.parseFloat(f64, str), .span = token.span } },
            .true => .{ .true = token.span },
            .false => .{ .false = token.span },
            else => unreachable,
        };
    }

    fn expect(self: *Parser, token_ty: Token.Type) !Token {
        const token = try self.peek();
        if (token.ty != token_ty) {
            return self.parseError(Token, token, &.{.{ .token = token_ty }});
        }
        self.advance();
        return token;
    }

    fn parseError(self: *Parser, comptime T: type, unexpected: Token, expected: []const ParseError.Item) !T {
        self.err.* = .{
            .path = self.ctx.source.path,
            .location = self.ctx.source.getLocation(unexpected.span.offset),
            .data = .{ .parse = .{ .unexpected = .{ .token = unexpected.ty }, .expected = expected } },
        };
        return error.CompileFailed;
    }

    fn peek(self: *Parser) !Token {
        if (self.curr_token) |token| return token;
        self.curr_token = try self.scanner.next();
        return self.curr_token.?;
    }

    fn advance(self: *Parser) void {
        self.curr_token = null;
    }
};
