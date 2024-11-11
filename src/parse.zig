const std = @import("std");
const ast = @import("ast.zig");
const scan = @import("scan.zig");
const Scanner = scan.Scanner;
const Source = @import("Source.zig");
const Reporter = @import("Reporter.zig");

pub const Parser = struct {
    const Self = @This();

    reporter: *Reporter,
    source: Source,
    scanner: Scanner,

    pub fn init(reporter: *Reporter, source: Source) Self {
        return Self{
            .reporter = reporter,
            .source = source,
            .scanner = Scanner.init(reporter, source),
        };
    }

    pub fn parse(self: *Self, allocator: std.mem.Allocator) !ast.Root {
        const root = try allocator.create(ast.Expression);
        errdefer allocator.destroy(root);
        root.* = try self.parseExpression(allocator);
        return ast.Root{ .root = root };
    }

    fn parseExpression(self: *Self, allocator: std.mem.Allocator) !ast.Expression {
        _ = allocator;
        const token = try self.scanner.next();
        return switch (token.kind) {
            .int => .{
                .int = .{
                    .span = token.span,
                    .int = std.fmt.parseInt(i64, self.source.contentSlice(token.span), 0) catch unreachable,
                },
            },
            .eof => unreachable,
        };
    }
};
