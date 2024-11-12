const std = @import("std");
const ast = @import("ast.zig");
const Source = @import("Source.zig");
const Span = @import("Span.zig");
const Reporter = @import("Reporter.zig");

pub const Scanner = struct {
    const Self = @This();

    reporter: *Reporter,
    source: Source,
    cur_span: Span,

    const keywords = std.StaticStringMap(ast.Token.Kind).initComptime(.{
        .{ "true", .true },
        .{ "false", .false },
    });

    pub fn init(reporter: *Reporter, source: Source) Self {
        return Self{
            .reporter = reporter,
            .source = source,
            .cur_span = Span.zero,
        };
    }

    pub fn next(self: *Self) !ast.Token {
        self.skipWhitespace();
        const c = self.peek() orelse return ast.Token{
            .kind = .eof,
            .span = self.cur_span,
        };
        if (std.ascii.isDigit(c)) {
            return self.nextNumber();
        } else if (std.ascii.isAlphabetic(c)) {
            return self.nextIdentifier();
        } else {
            try self.reporter.report(self.source, self.cur_span, "unexpected character: '{c}'", .{c});
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
        const identifier = self.source.contentSlice(self.cur_span);
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
            .span = self.cur_span,
        };
        self.resetSpan();
        return token;
    }

    fn resetSpan(self: *Self) void {
        self.cur_span.start_loc = self.cur_span.end_loc;
    }

    fn advance(self: *Self) void {
        const c = self.peek() orelse return;
        if (c == '\n') {
            self.cur_span.end_loc.line += 1;
            self.cur_span.end_loc.col = 1;
        } else {
            self.cur_span.end_loc.col += 1;
        }
        self.cur_span.end_loc.offset += 1;
    }

    fn peek(self: *Self) ?u8 {
        if (self.cur_span.end_loc.offset >= self.source.content.len) {
            return null;
        }
        return self.source.content[self.cur_span.end_loc.offset];
    }
};
