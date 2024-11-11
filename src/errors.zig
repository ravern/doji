const std = @import("std");
const Allocator = std.mem.Allocator;

const Span = @import("./Span.zig");
const Token = @import("./compile/lex.zig").Token;

pub const DojiError = error{
    CompileFailed,
    OutOfMemory,
};

pub const Error = union(enum) {
    Compile: CompileError,

    pub fn deinit(self: Error, allocator: Allocator) void {
        switch (self) {
            .Compile => self.Compile.deinit(allocator),
        }
    }
};

pub const CompileError = union(enum) {
    UnexpectedChar: UnexpectedCharError,
    IntLiteralOverflow: Span,

    pub fn deinit(self: CompileError, allocator: Allocator) void {
        switch (self) {
            .UnexpectedChar => self.UnexpectedChar.deinit(allocator),
            .IntLiteralOverflow => {},
        }
    }
};

pub const UnexpectedCharError = struct {
    span: Span,
    unexpected: u8,
    expected: []const ExpectedChar,

    pub fn deinit(self: UnexpectedCharError, allocator: Allocator) void {
        allocator.free(self.expected);
    }
};

pub const ExpectedChar = union(enum) {
    Digit,
    Char: u8,
};

pub const UnexpectedTokenError = struct {
    span: Span,
    unexpected: Token,
    expected: []const ExpectedToken,
};

pub const ExpectedToken = union(enum) {
    Token: Token,
};
