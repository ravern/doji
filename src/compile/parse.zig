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
        var expressions = try self.ctx.allocator.alloc(ast.Expression, 1);
        expressions[0] = try self.parseExpression();
        return .{ .expressions = expressions, .span = .{ .offset = 0, .len = self.ctx.source.content.len } };
    }

    fn parseExpression(self: *Parser) !ast.Expression {
        const token = try self.peek();
        switch (token.ty) {
            .identifier => return .{ .identifier = try self.parseIdentifier(token) },
            .int, .float, .true, .false => return .{ .literal = try self.parseLiteral(token) },
            else => return self.parseError(ast.Expression, token, &.{.expression}),
        }
    }

    fn parseIdentifier(self: *Parser, token: Token) !ast.Identifier {
        const identifier = try self.ctx.string_pool.intern(self.ctx.source.getSlice(token.span));
        return .{ .identifier = identifier, .span = token.span };
    }

    fn parseLiteral(self: *Parser, token: Token) !ast.Literal {
        const str = self.ctx.source.getSlice(token.span);
        switch (token.ty) {
            .int => return .{ .int = .{ .value = try std.fmt.parseInt(i48, str, 10), .span = token.span } },
            .float => return .{ .float = .{ .value = try std.fmt.parseFloat(f64, str), .span = token.span } },
            .true => return .{ .true = token.span },
            .false => return .{ .false = token.span },
            else => unreachable,
        }
    }

    fn expect(self: *Parser, token_ty: Token.Type) !void {
        const token = try self.peek();
        if (token.ty != token_ty) {
            return self.errorUnexpectedToken(token);
        }
        self.advance();
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
