const std = @import("std");
const Error = @import("../compile.zig").Error;
const ParseError = @import("../compile.zig").ParseError;
const Source = @import("../source.zig").Source;

const keywords = std.StaticStringMap(Token.Type).initComptime(.{
    .{ "true", .true },
    .{ "false", .false },
});

pub const Token = struct {
    ty: Type,
    span: Source.Span,

    pub const Type = enum {
        int,
        float,
        identifier,

        true,
        false,

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
        return self.nextNumber();
    }

    fn nextIdentifier(self: *Scanner) !Token {
        var is_first = true;
        while (true) {
            switch (try self.peek()) {
                'a'...'z', 'A'...'Z', '_' => {
                    is_first = false;
                    self.advance();
                },
                '0'...'9' => if (is_first) {
                    return self.parseError(.digit, .{ .alphabet, .{ .char = '_' } });
                } else {
                    self.advance();
                },
                else => break,
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
            switch (self.peek() orelse break) {
                '0'...'9' => self.advance(),
                '.' => if (is_float) {
                    return self.parseError(.{ .char = '.' }, &.{.digit});
                } else {
                    is_float = true;
                    self.advance();

                    // next char must be a digit
                    switch (self.peek() orelse return self.parseError(.end_of_input, &.{.digit})) {
                        '0'...'9' => {},
                        else => |c| return self.parseError(.{ .char = c }, &.{.digit}),
                    }
                },
                else => break,
            }
        }
        return self.confirmToken(if (is_float) .float else .int);
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
