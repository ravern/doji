const std = @import("std");
const String = @import("value.zig").String;
const GC = @import("root.zig").GC;

pub const StringPool = struct {
    gc: *GC,
    data: std.StringHashMap(*String),

    pub fn init(allocator: std.mem.Allocator, gc: *GC) StringPool {
        return .{
            .gc = gc,
            .data = std.StringHashMap(*String).init(allocator),
        };
    }

    pub fn deinit(self: *StringPool) void {
        self.data.deinit();
    }

    pub fn get(self: *StringPool, str: []const u8) ?*String {
        return self.data.get(str);
    }

    pub fn intern(self: *StringPool, str: []const u8) !*String {
        const result = try self.data.getOrPut(str);
        if (!result.found_existing) {
            result.value_ptr.* = try self.gc.create(String);
            result.value_ptr.*.* = String.init(try self.gc.child_allocator.dupe(u8, str));
        }
        return result.value_ptr.*;
    }
};

test StringPool {
    const allocator = std.testing.allocator;

    var gc = GC.init(allocator, allocator);
    defer gc.deinit();

    var pool = StringPool.init(allocator, &gc);
    defer pool.deinit();

    const string_one = try pool.intern("one");
    const string_two = try pool.intern("one");
    const string_three = try pool.intern("three");

    try std.testing.expect(String.eql(string_one, string_two));
    try std.testing.expect(!String.eql(string_one, string_three));

    try std.testing.expect(String.eql(pool.get("one").?, string_one));
}
