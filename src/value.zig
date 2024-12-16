const std = @import("std");

pub fn Value(comptime GC: type) type {
    _ = GC;

    return struct {
        raw: u64,
    };
}

pub const String = union(enum) {
    const HashMapContext = struct {
        pub fn hash(self: HashMapContext, value: Value) u64 {
            _ = self;
            return std.hash.Wyhash.hash(0, value.get());
        }

        pub fn eql(self: HashMapContext, left: Value, right: Value) bool {
            _ = self;
            return std.mem.eql(u8, left.get(), right.get());
        }
    };

    small: [16]u8, // any small string
    static: []const u8, // present in source code
    dynamic: []const u8, // runtime-created

    pub fn initStatic(str: []const u8) String {
        return .{ .static = str };
    }

    pub fn initDynamic(allocator: std.mem.Allocator, str: []const u8) !String {
        const dynamic = try allocator.dupe(u8, str);
        return .{ .dynamic = dynamic };
    }

    pub fn deinit(self: *String, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .small => {},
            .static => {},
            .dynamic => allocator.free(self.dynamic),
        }
        self.* = undefined;
    }

    pub fn trace(self: *String, tracer: anytype) void {
        _ = self;
        _ = tracer;
    }

    pub fn finalize(self: *String, allocator: std.mem.Allocator) void {
        self.deinit(allocator);
    }

    pub fn get(self: *const String) []const u8 {
        switch (self.*) {
            .small => return self.small[1..self.getLen()],
            .static => return self.static,
            .dynamic => return self.dynamic,
        }
    }

    pub fn getLen(self: String) usize {
        switch (self) {
            .small => return @intCast(self.small[0]),
            .static => return self.static.len,
            .dynamic => return self.dynamic.len,
        }
    }
};
