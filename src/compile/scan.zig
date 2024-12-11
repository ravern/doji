const std = @import("std");
const Error = @import("../compile.zig").Error;
const ParseError = @import("../compile.zig").ParseError;
const Source = @import("../source.zig").Source;

const punctuation = std.StaticStringMap(Token.Type).initComptime(.{
    .{ "+", .plus },
    .{ ";", .semicolon },
    .{ "(", .o_paren },
    .{ ")", .c_paren },
});

const punctuation2 = std.StaticStringMap(Token.Type).initComptime(.{
    .{ "+=", .plus_eq },
});

const keywords = std.StaticStringMap(Token.Type).initComptime(.{
    .{ "true", .true },
    .{ "false", .false },
    .{ "foreign", .foreign },
});

pub const Token = struct {
    ty: Type,
    span: Source.Span,

    pub const Type = enum {
        int,
        float,
        string,
        identifier,

        true,
        false,
        foreign,

        plus,
        plus_eq,
        semicolon,
        o_paren,
        c_paren,

        end_of_input,
    };
};

pub const Scanner = struct {
    source: *const Source,
    err: *Error,
    curr_span: Source.Span,

    pub fn init(source: *const Source, err: *Error) Scanner {
        return .{
            .source = source,
            .err = err,
            .curr_span = Source.Span.zero,
        };
    }

    pub fn next(self: *Scanner) !Token {
        self.skipWhitespace();

        const c = self.peek() orelse return self.confirmToken(.end_of_input);
        if (punctuation.get(&.{c})) |_| {
            return self.nextPunctuation();
        } else if (std.ascii.isAlphabetic(c) or c == '_') {
            return self.nextIdentifier();
        } else if (std.ascii.isDigit(c)) {
            return self.nextNumber();
        } else {
            return self.parseError(.{ .char = c }, &.{.alphabet});
        }
    }

    fn nextPunctuation(self: *Scanner) !Token {
        const c = self.peek().?;
        const ty = punctuation.get(&.{c}).?;
        self.advance();
        const d = self.peek() orelse return self.confirmToken(ty);
        if (punctuation2.get(&.{ c, d })) |ty2| {
            self.advance();
            return self.confirmToken(ty2);
        } else {
            return self.confirmToken(ty);
        }
    }

    fn nextIdentifier(self: *Scanner) !Token {
        var is_first = true;
        while (true) {
            const c = self.peek() orelse break;
            if (std.ascii.isAlphabetic(c) or c == '_') {
                is_first = false;
                self.advance();
            } else if (std.ascii.isDigit(c)) {
                if (is_first) {
                    return self.parseError(.digit, &.{ .alphabet, .{ .char = '_' } });
                } else {
                    self.advance();
                }
            } else {
                break;
            }
        }
        if (keywords.get(self.source.getSlice(self.curr_span))) |ty| {
            return self.confirmToken(ty);
        } else {
            return self.confirmToken(.identifier);
        }
    }

    fn nextNumber(self: *Scanner) !Token {
        var is_float = false;
        while (true) {
            const c = self.peek() orelse break;
            if (std.ascii.isDigit(c)) {
                self.advance();
            } else if (c == '.') {
                if (is_float) {
                    return self.parseError(.{ .char = '.' }, &.{.digit});
                } else {
                    is_float = true;
                    self.advance();

                    // next char must be a digit
                    const d = self.peek() orelse return self.parseError(.end_of_input, &.{.digit});
                    if (!std.ascii.isDigit(d)) return self.parseError(.{ .char = d }, &.{.digit});
                }
            } else {
                break;
            }
        }
        return self.confirmToken(if (is_float) .float else .int);
    }

    fn skipWhitespace(self: *Scanner) void {
        while (true) {
            const c = self.peek() orelse break;
            if (!std.ascii.isWhitespace(c)) break;
            self.advance();
        }
    }

    fn confirmToken(self: *Scanner, ty: Token.Type) Token {
        const token = .{ .ty = ty, .span = self.curr_span };
        self.curr_span = .{ .offset = self.curr_span.offset + self.curr_span.len, .len = 0 };
        return token;
    }

    fn getCurrentLocation(self: *Scanner) Source.Location {
        return self.source.getLocation(self.curr_span.offset + self.curr_span.len);
    }

    fn expect(self: *Scanner, c: u8) !void {
        if (self.peek() != c) {
            return self.errorUnexpectedChar(c);
        }
        self.advance();
    }

    fn parseError(self: *Scanner, unexpected: ParseError.Item, expected: []const ParseError.Item) !Token {
        self.err.* = .{
            .path = self.source.path,
            .location = self.getCurrentLocation(),
            .data = .{ .parse = .{ .unexpected = unexpected, .expected = expected } },
        };
        return error.CompileFailed;
    }

    fn peek(self: *Scanner) ?u8 {
        if (self.curr_span.offset + self.curr_span.len >= self.source.content.len) return null;
        return self.source.content[self.curr_span.offset + self.curr_span.len];
    }

    fn advance(self: *Scanner) void {
        self.curr_span.len += 1;
    }
};
