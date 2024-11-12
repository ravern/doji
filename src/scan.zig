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

    pub fn init(reporter: *Reporter, source: Source) Self {
        return Self{
            .reporter = reporter,
            .source = source,
            .cur_span = Span.zero,
        };
    }

    pub fn next(self: *Self) !ast.Token {
        const c = self.peek() orelse return ast.Token{
            .kind = .eof,
            .span = self.cur_span,
        };
        if (std.ascii.isDigit(c)) {
            return self.nextNumber();
        } else {
            try self.reporter.report(self.source, self.cur_span, "unexpected character: '{c}'", .{c});
            return error.ParseFailed;
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

    fn buildToken(self: *Self, kind: ast.Token.Kind) ast.Token {
        const token = ast.Token{
            .kind = kind,
            .span = self.cur_span,
        };
        self.cur_span.start_loc = self.cur_span.end_loc;
        return token;
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
