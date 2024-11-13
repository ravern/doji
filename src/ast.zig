const std = @import("std");
const Span = @import("Span.zig");

pub const Token = struct {
    const Self = @This();

    pub const Kind = enum {
        // literals
        int,
        float,

        // punctuation
        plus,
        plus_equal,
        minus,
        minus_equal,
        asterisk,
        asterisk_equal,
        slash,
        slash_equal,
        percent,
        percent_equal,
        equal,
        equal_equal,
        bang,
        bang_equal,
        less,
        less_equal,
        less_less,
        greater,
        greater_equal,
        greater_greater,
        ampersand,
        ampersand_ampersand,
        pipe,
        pipe_pipe,
        caret,
        tilde,
        period,
        comma,
        colon,
        semicolon,
        l_brace,
        r_brace,
        l_paren,
        r_paren,
        l_bracket,
        r_bracket,

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

    pub fn toString(self: Self) []const u8 {
        return switch (self.kind) {
            .plus => "'+'",
            .plus_equal => "'+='",
            .minus => "'-'",
            .minus_equal => "'-='",
            .asterisk => "'*'",
            .asterisk_equal => "'*='",
            .slash => "'/'",
            .slash_equal => "'/='",
            .percent => "'%'",
            .percent_equal => "'%='",
            .equal => "'='",
            .equal_equal => "'=='",
            .bang => "'!'",
            .bang_equal => "'!='",
            .less => "'<'",
            .less_equal => "'<='",
            .less_less => "'<<'",
            .greater => "'>'",
            .greater_equal => "'>='",
            .greater_greater => "'>>'",
            .ampersand => "'&'",
            .ampersand_ampersand => "'&&'",
            .pipe => "'|'",
            .pipe_pipe => "'||'",
            .caret => "'^'",
            .tilde => "'~'",
            .period => "'.'",
            .comma => "','",
            .colon => "':'",
            .semicolon => "';'",
            .l_brace => "'{'",
            .r_brace => "'}'",
            .l_paren => "'('",
            .r_paren => "')'",
            .l_bracket => "'['",
            .r_bracket => "']'",
            .eof => "end of file",
            else => @tagName(self.kind),
        };
    }
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
    binary: BinaryExpression,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .identifier => |*identifier| identifier.deinit(allocator),
            .binary => |*binary| binary.deinit(allocator),
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

pub const BinaryExpression = struct {
    const Self = @This();

    pub const Op = enum {
        add,
        sub,
        mul,
        div,
        mod,
        eq,
        ne,
        lt,
        le,
        gt,
        ge,
        log_and,
        log_or,
        bit_and,
        bit_or,
        bit_xor,
        shift_left,
        shift_right,

        pub fn fromTokenKind(kind: Token.Kind) Op {
            return switch (kind) {
                .plus => .add,
                .minus => .sub,
                .asterisk => .mul,
                .slash => .div,
                .percent => .mod,
                .equal_equal => .eq,
                .bang_equal => .ne,
                .less => .lt,
                .less_equal => .le,
                .greater => .gt,
                .greater_equal => .ge,
                .ampersand_ampersand => .log_and,
                .pipe_pipe => .log_or,
                .ampersand => .bit_and,
                .pipe => .bit_or,
                .caret => .bit_xor,
                .less_less => .shift_left,
                .greater_greater => .shift_right,
                else => unreachable,
            };
        }
    };

    op: Op,
    left: *Expression,
    right: *Expression,

    pub fn init(allocator: std.mem.Allocator, op: Op, left: Expression, right: Expression) !Self {
        var self = BinaryExpression{ .op = op, .left = undefined, .right = undefined };

        self.left = try allocator.create(Expression);
        errdefer allocator.destroy(self.left);
        self.left.* = left;

        self.right = try allocator.create(Expression);
        errdefer allocator.destroy(self.right);
        self.right.* = right;

        return self;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.left.deinit(allocator);
        allocator.destroy(self.left);
        self.right.deinit(allocator);
        allocator.destroy(self.right);
        self.* = undefined;
    }
};

pub const UnaryExpression = struct {
    const Self = @This();

    pub const Op = enum {
        pos,
        neg,

        pub fn fromTokenKind(kind: Token.Kind) Op {
            return switch (kind) {
                .plus => .pos,
                .minus => .neg,
                else => unreachable,
            };
        }
    };

    op: Op,
    expr: *Expression,
};
