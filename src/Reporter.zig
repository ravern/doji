const std = @import("std");
const Span = @import("Span.zig");
const Source = @import("Source.zig");

const Self = @This();

allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .allocator = allocator,
    };
}

pub fn report(self: *Self, source: Source, span: Span, comptime fmt: []const u8, args: anytype) !void {
    const message = try std.fmt.allocPrint(self.allocator, fmt, args);
    defer self.allocator.free(message);
    try std.io.getStdErr().writer().print("error: {s}:{d}:{d}: {s}\n", .{ source.path(), span.start_loc.line, span.start_loc.col, message });
}
