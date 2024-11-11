const std = @import("std");
const Span = @import("Span.zig");

pub const Token = struct {
    const Self = @This();

    pub const Kind = enum {
        int,
        eof,
    };

    kind: Kind,
    span: Span,
};

pub const Root = struct {
    const Self = @This();

    root: *Expression,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.root.deinit(allocator);
        allocator.destroy(self.root);
        self.* = undefined;
    }
};

pub const Expression = union(enum) {
    const Self = @This();

    int: IntExpression,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        _ = allocator;
        switch (self) {
            else => {},
        }
        self.* = undefined;
    }
};

pub const IntExpression = struct {
    int: i64,
    span: Span,
};
