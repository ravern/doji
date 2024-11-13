const std = @import("std");
const ast = @import("ast.zig");
const scan = @import("scan.zig");
const Scanner = scan.Scanner;
const Source = @import("Source.zig");
const Reporter = @import("Reporter.zig");

pub const Parser = struct {
    const Self = @This();

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

    fn parseExpression(self: *Self, allocator: std.mem.Allocator) !ast.Expression {
        return self.parsePrattExpression(allocator, 0);
    }

    fn parsePrattExpression(self: *Self, allocator: std.mem.Allocator, min_precedence: usize) !ast.Expression {
        var left = try self.parsePrattPrimary(allocator);

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
