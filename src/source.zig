const std = @import("std");

pub const Source = struct {
    path: []const u8,
    content: []const u8,

    pub const Location = struct {
        line: usize,
        column: usize,

        pub const zero = .{ .line = 1, .column = 1 };
    };

    pub const Span = struct {
        offset: usize,
        len: usize,

        pub const zero = .{ .offset = 0, .len = 0 };
    };

    pub fn init(path: []const u8, content: []const u8) Source {
        return .{
            .path = path,
            .content = content,
        };
    }

    pub fn getLocation(self: *const Source, offset: usize) Location {
        var line: usize = 1;
        var column: usize = 1;
        for (self.content[0..offset]) |c| {
            // TODO: line endings
            if (c == '\n') {
                line += 1;
                column = 1;
            } else {
                column += 1;
            }
        }
        return .{ .line = line, .column = column };
    }

    pub fn getSlice(self: *const Source, span: Span) []const u8 {
        return self.content[span.offset .. span.offset + span.len];
    }
};

test Source {
    const source = Source{
        .path = "test.txt",
        .content = "lorem ipsum dolor sit amet\nconsectetur adipiscing elit",
    };

    const location_one = source.getLocation(10);
    try std.testing.expectEqual(1, location_one.line);
    try std.testing.expectEqual(11, location_one.column);

    const location_two = source.getLocation(27);
    try std.testing.expectEqual(2, location_two.line);
    try std.testing.expectEqual(1, location_two.column);

    const slice_one = source.getSlice(.{ .offset = 6, .len = 5 });
    try std.testing.expectEqualStrings("ipsum", slice_one);

    const slice_two = source.getSlice(.{ .offset = 18, .len = 9 });
    try std.testing.expectEqualStrings("sit amet\n", slice_two);
}
