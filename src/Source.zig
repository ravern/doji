const std = @import("std");

const Self = @This();

pub const Location = struct {
    offset: usize,
    line: usize,
    col: usize,

    pub const zero = Location{ .offset = 0, .line = 1, .col = 1 };
};

pub const Span = struct {
    start: Location,
    end: Location,

    pub const zero = Span{ .start = Location.zero, .end = Location.zero };

    pub fn merge(self: Span, other: Span) Span {
        const start = if (self.start.offset < other.start.offset) self.start else other.start;
        const end = if (self.end.offset > other.end.offset) self.end else other.end;
        return .{ .start = start, .end = end };
    }

    pub fn getLength(self: Span) usize {
        return self.end.offset - self.start.offset;
    }
};

pub const Path = union(enum) {
    stdin,
};

path: Path,
content: []const u8,

pub fn initStdin(content: []const u8) Self {
    return Self{
        .path = .stdin,
        .content = content,
    };
}

pub fn getPath(self: Self) []const u8 {
    return switch (self.path) {
        .stdin => "<stdin>",
    };
}

pub fn getContentSpan(self: Self, span: Span) []const u8 {
    return self.content[span.start.offset..span.end.offset];
}
