const std = @import("std");
const Source = @import("../source.zig").Source;
const String = @import("../value.zig").String;

pub const Block = struct {
    expressions: []const Expression,
    span: Source.Span,

    pub fn deinit(self: *Block, allocator: std.mem.Allocator) void {
        allocator.free(self.expressions);
        self.* = undefined;
    }
};

pub const Expression = union(enum) {
    identifier: Identifier,
    literal: Literal,

    pub fn deinit(self: *Expression, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const Identifier = struct {
    identifier: *String,
    span: Source.Span,
};

pub const Literal = union(enum) {
    int: IntLiteral,
    float: FloatLiteral,
    true: Source.Span,
    false: Source.Span,
};

pub const IntLiteral = struct {
    value: i48,
    span: Source.Span,
};

pub const FloatLiteral = struct {
    value: f64,
    span: Source.Span,
};
