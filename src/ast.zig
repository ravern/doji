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
    unary: UnaryExpression,
    binary: BinaryExpression,
    block: Block,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .identifier => |*identifier| identifier.deinit(allocator),
            .unary => |*unary| unary.deinit(allocator),
            .binary => |*binary| binary.deinit(allocator),
            .block => |*block| block.deinit(allocator),
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

pub const UnaryExpression = struct {
    const Self = @This();

    pub const Op = enum {
        pos,
        neg,
        log_not,

        pub fn fromTokenKind(kind: Token.Kind) Op {
            return switch (kind) {
                .plus => .pos,
                .minus => .neg,
                .bang => .log_not,
                else => unreachable,
            };
        }
    };

    op: Op,
    expr: *Expression,

    pub fn init(allocator: std.mem.Allocator, op: Op, expr: Expression) !Self {
        var self = UnaryExpression{ .op = op, .expr = undefined };
        self.expr = try allocator.create(Expression);
        errdefer allocator.destroy(self.expr);
        self.expr.* = expr;
        return self;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.expr.deinit(allocator);
        allocator.destroy(self.expr);
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
        neq,
        lt,
        le,
        gt,
        ge,
        log_and,
        log_or,
        bit_and,
        bit_or,
        bit_xor,
        shl,
        shr,

        pub fn fromTokenKind(kind: Token.Kind) Op {
            return switch (kind) {
                .plus => .add,
                .minus => .sub,
                .asterisk => .mul,
                .slash => .div,
                .percent => .mod,
                .equal_equal => .eq,
                .bang_equal => .neq,
                .less => .lt,
                .less_equal => .le,
                .greater => .gt,
                .greater_equal => .ge,
                .ampersand_ampersand => .log_and,
                .pipe_pipe => .log_or,
                .ampersand => .bit_and,
                .pipe => .bit_or,
                .caret => .bit_xor,
                .less_less => .shl,
                .greater_greater => .shr,
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

pub const Block = struct {
    const Self = @This();

    stmts: []Statement,
    ret_expr: ?*Expression,
    span: Span,

    pub fn init(allocator: std.mem.Allocator, stmts: []Statement, ret_expr: ?Expression, span: Span) !Self {
        var self = Self{ .stmts = undefined, .ret_expr = null, .span = span };

        self.stmts = try allocator.dupe(Statement, stmts);

        if (ret_expr) |expr| {
            self.ret_expr = try allocator.create(Expression);
            errdefer allocator.destroy(self.ret_expr.?);
            self.ret_expr.?.* = expr;
        }

        return self;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.stmts) |*stmt| {
            stmt.deinit(allocator);
        }
        allocator.free(self.stmts);

        if (self.ret_expr) |expr| {
            expr.deinit(allocator);
            allocator.destroy(expr);
        }

        self.* = undefined;
    }
};

pub const Statement = union(enum) {
    const Self = @This();

    expr: ExpressionStatement,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .expr => |*expr| expr.deinit(allocator),
        }
        self.* = undefined;
    }
};

pub const ExpressionStatement = struct {
    const Self = @This();

    expr: *Expression,
    span: Span,

    pub fn init(allocator: std.mem.Allocator, expr: Expression, span: Span) !Self {
        var self = Self{ .expr = undefined, .span = span };
        self.expr = try allocator.create(Expression);
        errdefer allocator.destroy(self.expr);
        self.expr.* = expr;
        return self;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.expr.deinit(allocator);
        allocator.destroy(self.expr);
        self.* = undefined;
    }
};
