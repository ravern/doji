const std = @import("std");
const Span = @import("Span.zig");

const Self = @This();

pub const Kind = union(enum) {
    stdin,
};

kind: Kind,
content: []const u8,

// Takes ownership of content.
pub fn initStdin(content: []const u8) Self {
    return Self{
        .kind = .stdin,
        .content = content,
    };
}

pub fn path(self: Self) []const u8 {
    return switch (self.kind) {
        .stdin => "<stdin>",
    };
}

pub fn contentSlice(self: Self, span: Span) []const u8 {
    return self.content[span.start_loc.offset..span.end_loc.offset];
}
