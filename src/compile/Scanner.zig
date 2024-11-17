const std = @import("std");
const ast = @import("ast.zig");
const compile = @import("../compile.zig");
const Source = @import("../Source.zig");

const Self = @This();

context: *compile.Context,
source: *const Source,
accumulated_span: Source.Span,

const punctuation = std.StaticStringMap(ast.Token.Kind).initComptime(.{
    .{ "+", .plus },
    .{ "-", .minus },
    .{ "*", .asterisk },
    .{ "/", .slash },
    .{ "%", .percent },
    .{ "=", .equal },
    .{ "!", .bang },
    .{ "<", .less },
    .{ ">", .greater },
    .{ "&", .ampersand },
    .{ "|", .pipe },
    .{ "^", .caret },
    .{ "~", .tilde },
    .{ ".", .period },
    .{ ",", .comma },
    .{ ":", .colon },
    .{ ";", .semicolon },
    .{ "{", .l_brace },
    .{ "}", .r_brace },
    .{ "(", .l_paren },
    .{ ")", .r_paren },
    .{ "[", .l_bracket },
    .{ "]", .r_bracket },
});

const punctuation2 = std.StaticStringMap(ast.Token.Kind).initComptime(.{
    .{ "+=", .plus_equal },
    .{ "-=", .minus_equal },
    .{ "*=", .asterisk_equal },
    .{ "/=", .slash_equal },
    .{ "%=", .percent_equal },
    .{ "==", .equal_equal },
    .{ "!=", .bang_equal },
    .{ "<=", .less_equal },
    .{ ">=", .greater_equal },
    .{ "&&", .ampersand_ampersand },
    .{ "||", .pipe_pipe },
    .{ "<<", .less_less },
    .{ ">>", .greater_greater },
});

const keywords = std.StaticStringMap(ast.Token.Kind).initComptime(.{
    .{ "nil", .nil },
    .{ "true", .true },
    .{ "false", .false },
    .{ "let", .let },
});

pub fn init(context: *compile.Context, source: *const Source) Self {
    return Self{
        .context = context,
        .source = source,
        .accumulated_span = Source.Span.zero,
    };
}

pub fn next(self: *Self) !ast.Token {
    self.skipWhitespace();
    const c = self.peek() orelse return ast.Token{
        .kind = .eof,
        .span = self.accumulated_span,
    };
    if (punctuation.get(&.{c})) |kind| {
        self.advance();
        const c2 = self.peek() orelse return self.buildToken(kind);
        if (punctuation2.get(&.{ c, c2 })) |kind2| {
            self.advance();
            return self.buildToken(kind2);
        }
        return self.buildToken(kind);
    } else if (std.ascii.isDigit(c)) {
        return self.nextNumber();
    } else if (std.ascii.isAlphabetic(c)) {
        return self.nextIdentifier();
    } else {
        std.debug.print(
            "{s}:{d}:{d}: unexpected character: '{c}'\n",
            .{ self.source.getPath(), self.accumulated_span.start.line, self.accumulated_span.start.col, c },
        );
        return error.CompileFailed;
    }
}

fn nextNumber(self: *Self) !ast.Token {
    self.advance();
    var is_float = false;
    while (true) {
        const c = self.peek() orelse break;
        if (c == '.' and !is_float) {
            is_float = true;
            self.advance();
            continue;
        }
        if (!std.ascii.isDigit(c)) break;
        self.advance();
    }
    return self.buildToken(if (is_float) .float else .int);
}

fn nextIdentifier(self: *Self) !ast.Token {
    self.advance();
    while (true) {
        const c = self.peek() orelse break;
        if (!std.ascii.isAlphabetic(c) and !std.ascii.isDigit(c) and c != '_') break;
        self.advance();
    }
    const identifier = self.source.getContentSpan(self.accumulated_span);
    if (keywords.get(identifier)) |kind| return self.buildToken(kind);
    return self.buildToken(.identifier);
}

fn skipWhitespace(self: *Self) void {
    while (true) {
        const c = self.peek() orelse break;
        if (!std.ascii.isWhitespace(c)) break;
        self.advance();
    }
    self.resetSpan();
}

fn buildToken(self: *Self, kind: ast.Token.Kind) ast.Token {
    const token = ast.Token{
        .kind = kind,
        .span = self.accumulated_span,
    };
    self.resetSpan();
    return token;
}

fn resetSpan(self: *Self) void {
    self.cur_span.start = self.cur_span.end;
}

fn advance(self: *Self) void {
    const c = self.peek() orelse return;
    if (c == '\n') {
        self.accumulated_span.end.line += 1;
        self.accumulated_span.end.col = 1;
    } else {
        self.accumulated_span.end.col += 1;
    }
    self.accumulated_span.end.offset += 1;
}

fn peek(self: *Self) ?u8 {
    if (self.accumulated_span.end.offset >= self.source.content.len) {
        return null;
    }
    return self.source.content[self.accumulated_span.end.offset];
}
