const Allocator = @import("std").mem.Allocator;

const Span = @import("../Span.zig");

pub const File = struct {
    block: Block,

    pub fn deinit(self: File, allocator: Allocator) void {
        self.block.deinit(allocator);
    }
};

pub const Statement = union(enum) {
    Expression: Expression,

    pub fn deinit(self: Statement, allocator: Allocator) void {
        switch (self) {
            .Expression => self.Expression.deinit(allocator),
        }
    }
};

pub const Expression = union(enum) {
    Block: Block,
    Literal: Literal,

    pub fn deinit(self: Expression, allocator: Allocator) void {
        switch (self) {
            .Block => self.Block.deinit(allocator),
            .Literal => {},
        }
    }
};

pub const Block = struct {
    span: Span,
    statements: []const Statement,
    return_expression: ?*const Expression,

    pub fn deinit(self: Block, allocator: Allocator) void {
        for (self.statements) |statement| {
            statement.deinit(allocator);
        }
        allocator.free(self.statements);
        if (self.return_expression) |return_expression| {
            return_expression.deinit(allocator);
            allocator.destroy(return_expression);
        }
    }
};

pub const Identifier = struct {
    span: Span,
    identifier: []const u8,
};

pub const Literal = union(enum) {
    Nil: Span,
    Bool: BoolLiteral,
    Int: IntLiteral,
    Float: FloatLiteral,
};

pub const BoolLiteral = struct {
    span: Span,
    bool: bool,
};

pub const IntLiteral = struct {
    span: Span,
    int: u64,
};

pub const FloatLiteral = struct {
    span: Span,
    float: f64,
};
