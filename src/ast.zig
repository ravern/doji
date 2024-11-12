const std = @import("std");
const Span = @import("Span.zig");

pub const Token = struct {
    const Self = @This();

    pub const Kind = enum {
        // literals
        int,
        float,

        // keywords
        nil,
        true,
        false,

        // others
        identifier,
        eof,
    };

    kind: Kind,
    span: Span,
};

pub const Root = struct {
    const Self = @This();

    expr: *Expression,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.expr.deinit(allocator);
        allocator.destroy(self.expr);
        self.* = undefined;
    }
};

pub const Expression = union(enum) {
    const Self = @This();

    nil: Span,
    true: Span,
    false: Span,
    int: IntExpression,
    float: FloatExpression,
    identifier: IdentifierExpression,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .identifier => |*identifier| identifier.deinit(allocator),
            else => {},
        }
        self.* = undefined;
    }
};

pub const IntExpression = struct {
    int: i48,
    span: Span,
};

pub const FloatExpression = struct {
    float: f64,
    span: Span,
};

pub const IdentifierExpression = struct {
    const Self = @This();

    identifier: []const u8,
    span: Span,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.identifier);
        self.* = undefined;
    }
};
