const std = @import("std");
const Source = @import("Source.zig");

const Self = @This();

pub const Item = struct {
    pub const Level = enum {
        hint,
        warning,
        @"error",
    };

    level: Level,
    source: Source,
    location: Source.Location,
    message: []const u8,
};

items: std.ArrayList(Item),

pub fn init(allocator: std.mem.Allocator) Self {
    return Self{
        .items = std.ArrayList(Item).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    self.items.deinit();
    self.* = undefined;
}

pub fn appendItem(self: *Self, level: Item.Level, source: Source, location: Source.Location, comptime fmt: []const u8, args: anytype) !void {
    try self.items.append(.{ .level = level, .source = source, .location = location, .message = try std.fmt.allocPrint(self.allocator, fmt, args) });
}

// writes to the writer and resets the items to start collecting reports again.
pub fn write(self: Self, writer: anytype) !void {
    for (self.items.items) |item| {
        try writer.print("{s}: {s}:{d}:{d}: {s}\n", .{ @tagName(item.level), item.source.getPath(), item.location.line, item.location.column, item.message });
    }
    self.items.clearRetainingCapacity();
}
