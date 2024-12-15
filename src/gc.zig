const std = @import("std");
const code = @import("code.zig");
const value = @import("value.zig");

pub fn GC(comptime Object: type) type {
    // TODO: verify that each field of [Object] has [trace] and [deinit] methods

    return struct {
        const Self = @This();

        child_allocator: std.mem.Allocator,
        // in case objects use a different allocator for internal allocations (e.g., list items)
        deinit_allocator: std.mem.Allocator,
        objects: ObjectList = .{},
        // may contain unrooted objects, that will be removed during the sweep phase
        root_set: std.ArrayListUnmanaged(*ObjectHeader) = .{},
        gray_set: std.ArrayListUnmanaged(*ObjectHeader) = .{},
        colors: Colors = .{},

        // for now, only supports marking as an action, but we might want to extend support for other actions
        // to be performed on the object graph.
        pub const Tracer = struct {
            gc: *Self,
            action: Action,

            pub const Action = enum {
                mark,
            };

            pub fn trace(self: Tracer, object_data: *anyopaque) !void {
                switch (self.action) {
                    .mark => {
                        const object_header = headerFromData(object_data);
                        // during a trace, we don't need to re-mark black objects.
                        if (object_header.color == self.gc.colors.black) return;
                        try self.gc.mark(object_data);
                    },
                }
            }
        };

        const Colors = struct {
            white: u2 = 0,
            black: u2 = 1,
            gray: u2 = 2,

            fn swapWhiteBlack(self: *Colors) void {
                const tmp = self.white;
                self.white = self.black;
                self.black = tmp;
            }
        };

        const object_size_map = createObjectSizeMap(Object);
        const object_align = @max(@alignOf(ObjectHeader), findMaxAlign(Object));
        const object_log2_align = std.math.log2_int(usize, object_align);
        const object_header_len = std.mem.alignForward(usize, @sizeOf(ObjectHeader), object_align);

        pub fn init(child_allocator: std.mem.Allocator, deinit_allocator: std.mem.Allocator) Self {
            return Self{
                .child_allocator = child_allocator,
                .deinit_allocator = deinit_allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.destroyObjectList(&self.objects);
            self.root_set.deinit(self.child_allocator);
            self.gray_set.deinit(self.child_allocator);
            self.* = undefined;
        }

        pub fn isType(comptime T: type, object_data: *anyopaque) bool {
            return headerFromData(object_data).tag == tagFromObjectType(Object, T);
        }

        pub fn create(self: *Self, comptime T: type) !*T {
            verifyObjectType(Object, T);

            const total_len = object_header_len + @sizeOf(T);
            const ptr = self.child_allocator.rawAlloc(total_len, object_log2_align, @returnAddress()) orelse return std.mem.Allocator.Error.OutOfMemory;
            const object_header = @as(*ObjectHeader, @ptrCast(@alignCast(ptr)));
            const object_data = @as(*T, @ptrCast(@alignCast(ptr[object_header_len..])));

            object_header.* = .{
                .color = self.colors.white,
                .tag = tagFromObjectType(Object, T),
            };
            self.objects.prepend(object_header);

            return object_data;
        }

        pub fn root(self: *Self, object_data: *anyopaque) !void {
            const object_header = headerFromData(object_data);
            object_header.is_root = true;
            try self.root_set.append(self.child_allocator, object_header);
        }

        pub fn unroot(object_data: *anyopaque) void {
            const object_header = headerFromData(object_data);
            object_header.is_root = false;
        }

        pub fn mark(self: *Self, object_data: *anyopaque) !void {
            const object_header = headerFromData(object_data);
            if (object_header.color == self.colors.gray) return;
            object_header.color = self.colors.gray;
            try self.gray_set.append(self.child_allocator, object_header);
        }

        pub fn collect(self: *Self) !void {
            try self.markRoots();
            while (self.gray_set.popOrNull()) |object_header| {
                try self.blacken(object_header);
            }
            try self.sweep();
            self.colors.swapWhiteBlack();
        }

        fn markRoots(self: *Self) !void {
            var index: usize = 0;
            var end_index: usize = self.root_set.items.len;
            while (index < end_index) {
                if (self.root_set.items[index].is_root) {
                    try self.mark(dataFromHeader(self.root_set.items[index]));
                    index += 1;
                } else {
                    _ = self.root_set.swapRemove(index);
                    end_index -= 1;
                }
            }
        }

        fn blacken(self: *Self, object_header: *ObjectHeader) !void {
            var tracer = Tracer{ .gc = self, .action = .mark };
            inline for (getUnionFields(Object), 0..) |field, index| {
                if (object_header.tag == index) {
                    try @as(*field.type, @ptrCast(@alignCast(dataFromHeader(object_header)))).trace(&tracer);
                }
            }
            object_header.color = self.colors.black;
        }

        fn sweep(self: *Self) !void {
            // sweep the root set for unrooted objects
            var index: usize = 0;
            var end_index: usize = self.root_set.items.len;
            while (index < end_index) {
                if (self.root_set.items[index].is_root) {
                    index += 1;
                } else {
                    _ = self.root_set.swapRemove(index);
                    end_index -= 1;
                }
            }

            // sweep the entire objects list for white objects
            var white_set = ObjectList{};
            var prev_object_header: ?*ObjectHeader = null;
            var curr_object_header = self.objects.first;
            while (curr_object_header) |curr| {
                if (curr.color == self.colors.white) {
                    if (prev_object_header) |prev| {
                        prev.setNext(curr.getNext());
                        curr_object_header = curr.getNext();
                    } else {
                        self.objects.first = curr.getNext();
                        curr_object_header = curr.getNext();
                    }
                    white_set.prepend(curr);
                } else {
                    prev_object_header = curr;
                    curr_object_header = curr.getNext();
                }
            }
            self.destroyObjectList(&white_set);
        }

        fn destroyObjectList(self: *const Self, objects: *ObjectList) void {
            var curr_object_header = objects.first;
            while (curr_object_header) |object_header| : (curr_object_header = object_header.getNext()) {
                inline for (getUnionFields(Object), 0..) |field, index| {
                    if (object_header.tag == index) {
                        @as(*field.type, @ptrCast(@alignCast(dataFromHeader(object_header)))).deinit(self.child_allocator);
                    }
                }
            }
            while (objects.popFirst()) |object_header| {
                self.destroyObjectHeader(object_header);
            }
        }

        fn destroyObjectHeader(self: *const Self, object_header: *ObjectHeader) void {
            const total_len = object_header_len + object_size_map[object_header.tag];
            self.child_allocator.rawFree(@as([*]u8, @ptrCast(object_header))[0..total_len], object_log2_align, @returnAddress());
        }

        fn headerFromData(ptr: *anyopaque) *ObjectHeader {
            return @ptrFromInt(@intFromPtr(ptr) - object_header_len);
        }

        fn dataFromHeader(header: *ObjectHeader) *anyopaque {
            return @ptrFromInt(@intFromPtr(header) + object_header_len);
        }
    };
}

test GC {
    const TestResult = struct {
        freed_objects: std.StringHashMap(void),

        const Self = @This();

        fn init(allocator: std.mem.Allocator) Self {
            return Self{ .freed_objects = std.StringHashMap(void).init(allocator) };
        }

        fn deinit(self: *Self) void {
            self.freed_objects.deinit();
        }

        fn hasFreedObject(self: *Self, key: []const u8) bool {
            return self.freed_objects.contains(key);
        }

        fn putFreedObject(self: *Self, key: []const u8) void {
            self.freed_objects.put(key, {}) catch unreachable;
        }
    };

    const TestObject = struct {
        result: *TestResult,
        key: []const u8,
        refs: std.StringHashMap(*Self),

        const Self = @This();

        fn init(allocator: std.mem.Allocator, key: []const u8, result: *TestResult) Self {
            return Self{ .result = result, .key = key, .refs = std.StringHashMap(*Self).init(allocator) };
        }

        fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            _ = allocator;
            self.result.putFreedObject(self.key);
            self.refs.deinit();
            self.* = undefined;
        }

        fn trace(self: *Self, tracer: anytype) !void {
            var it = self.refs.valueIterator();
            while (it.next()) |child_object| {
                try tracer.trace(child_object.*);
            }
        }

        fn addRef(self: *Self, child_object: *Self) !void {
            try self.refs.put(child_object.key, child_object);
        }

        fn removeRef(self: *Self, child_object: *Self) void {
            _ = self.refs.remove(child_object.key);
        }
    };

    const TestGC = GC(union { test_object: TestObject });

    const allocator = std.testing.allocator;

    var result = TestResult.init(allocator);
    defer result.deinit();

    var gc = TestGC.init(allocator, allocator);
    defer gc.deinit();

    var root_object = try gc.create(TestObject);
    root_object.* = TestObject.init(allocator, "root", &result);
    try gc.root(root_object);
    defer TestGC.unroot(root_object);

    // basic example

    const basic_1_object = try gc.create(TestObject);
    basic_1_object.* = TestObject.init(gc.child_allocator, "basic_1", &result);
    const basic_2_object = try gc.create(TestObject);
    basic_2_object.* = TestObject.init(gc.child_allocator, "basic_2", &result);

    try root_object.addRef(basic_1_object);
    try root_object.addRef(basic_2_object);
    try gc.collect();
    try std.testing.expect(!result.hasFreedObject("basic_1"));
    try std.testing.expect(!result.hasFreedObject("basic_2"));

    root_object.removeRef(basic_1_object);
    try gc.collect();
    try std.testing.expect(result.hasFreedObject("basic_1"));
    try std.testing.expect(!result.hasFreedObject("basic_2"));

    root_object.removeRef(basic_2_object);
    try gc.collect();
    try std.testing.expect(result.hasFreedObject("basic_1"));
    try std.testing.expect(result.hasFreedObject("basic_2"));

    // multiple layers

    const layers_1_object = try gc.create(TestObject);
    layers_1_object.* = TestObject.init(gc.child_allocator, "layers_1", &result);
    const layers_2_object = try gc.create(TestObject);
    layers_2_object.* = TestObject.init(gc.child_allocator, "layers_2", &result);
    const layers_3_object = try gc.create(TestObject);
    layers_3_object.* = TestObject.init(gc.child_allocator, "layers_3", &result);
    const layers_4_object = try gc.create(TestObject);
    layers_4_object.* = TestObject.init(gc.child_allocator, "layers_4", &result);
    const layers_5_object = try gc.create(TestObject);
    layers_5_object.* = TestObject.init(gc.child_allocator, "layers_5", &result);

    try root_object.addRef(layers_1_object);
    try root_object.addRef(layers_2_object);
    try layers_2_object.addRef(layers_3_object);
    try layers_2_object.addRef(layers_4_object);
    try layers_3_object.addRef(layers_5_object);
    try gc.collect();
    try std.testing.expect(!result.hasFreedObject("layers_1"));
    try std.testing.expect(!result.hasFreedObject("layers_2"));
    try std.testing.expect(!result.hasFreedObject("layers_3"));
    try std.testing.expect(!result.hasFreedObject("layers_4"));
    try std.testing.expect(!result.hasFreedObject("layers_5"));

    root_object.removeRef(layers_1_object);
    try gc.collect();
    try std.testing.expect(result.hasFreedObject("layers_1"));
    try std.testing.expect(!result.hasFreedObject("layers_2"));
    try std.testing.expect(!result.hasFreedObject("layers_3"));
    try std.testing.expect(!result.hasFreedObject("layers_4"));
    try std.testing.expect(!result.hasFreedObject("layers_5"));

    root_object.removeRef(layers_2_object);
    try gc.collect();
    try std.testing.expect(result.hasFreedObject("layers_1"));
    try std.testing.expect(result.hasFreedObject("layers_2"));
    try std.testing.expect(result.hasFreedObject("layers_3"));
    try std.testing.expect(result.hasFreedObject("layers_4"));
    try std.testing.expect(result.hasFreedObject("layers_5"));

    // circular references

    const circular_1_object = try gc.create(TestObject);
    circular_1_object.* = TestObject.init(gc.child_allocator, "circular_1", &result);
    const circular_2_object = try gc.create(TestObject);
    circular_2_object.* = TestObject.init(gc.child_allocator, "circular_2", &result);

    try root_object.addRef(circular_1_object);
    try circular_1_object.addRef(circular_2_object);
    try circular_2_object.addRef(circular_1_object);
    try gc.collect();
    try std.testing.expect(!result.hasFreedObject("circular_1"));
    try std.testing.expect(!result.hasFreedObject("circular_2"));

    root_object.removeRef(circular_1_object);
    try gc.collect();
    try std.testing.expect(result.hasFreedObject("circular_1"));
    try std.testing.expect(result.hasFreedObject("circular_2"));

    // pointing to root

    const point_root_object = try gc.create(TestObject);
    point_root_object.* = TestObject.init(gc.child_allocator, "point_root", &result);

    try point_root_object.addRef(root_object);
    try gc.collect();
    try std.testing.expect(result.hasFreedObject("point_root"));
}

const ObjectHeader = packed struct {
    is_root: bool = false,
    color: u2,
    padding: u5 = 0,
    tag: u8,
    next_ptr: u48 = 0,

    fn getNext(self: *ObjectHeader) ?*ObjectHeader {
        return @as(?*ObjectHeader, @ptrFromInt(self.next_ptr));
    }

    fn setNext(self: *ObjectHeader, object_header: ?*ObjectHeader) void {
        if (object_header) |header| {
            self.next_ptr = @intCast(@intFromPtr(header));
        } else {
            self.next_ptr = 0;
        }
    }
};

const ObjectList = struct {
    first: ?*ObjectHeader = null,

    fn popFirst(self: *ObjectList) ?*ObjectHeader {
        const object_header = self.first orelse return null;
        self.first = object_header.getNext();
        return object_header;
    }

    fn prepend(self: *ObjectList, object_header: *ObjectHeader) void {
        object_header.setNext(self.first);
        self.first = object_header;
    }
};

fn verifyObjectType(comptime Object: type, comptime T: type) void {
    const fields = getUnionFields(Object);
    inline for (fields) |field| {
        if (field.type == T) return;
    }
    @compileError(@typeName(T) ++ " is not a valid GC object type");
}

fn tagFromObjectType(comptime Object: type, comptime T: type) u8 {
    const fields = getUnionFields(Object);
    inline for (fields, 0..) |field, index| {
        if (field.type == T) return @intCast(index);
    }
    @compileError(@typeName(T) ++ " is not a valid GC object type");
}

test tagFromObjectType {
    try std.testing.expectEqual(0, tagFromObjectType(union { a: u8, b: u16 }, u8));
    try std.testing.expectEqual(1, tagFromObjectType(union { a: u8, b: u16 }, u16));
}

fn createObjectSizeMap(comptime Object: type) [getUnionFields(Object).len]usize {
    const fields = getUnionFields(Object);
    var map: [fields.len]usize = undefined;
    inline for (fields, 0..) |field, index| {
        map[index] = @sizeOf(field.type);
    }
    return map;
}

test createObjectSizeMap {
    try std.testing.expectEqual([1]usize{1}, createObjectSizeMap(union { a: u8 }));
    try std.testing.expectEqual([2]usize{ 1, 2 }, createObjectSizeMap(union { a: u8, b: u16 }));
    try std.testing.expectEqual([3]usize{ 1, 2, 4 }, createObjectSizeMap(union { a: u8, b: u16, c: u32 }));
    try std.testing.expectEqual([4]usize{ 1, 2, 4, 8 }, createObjectSizeMap(union { a: u8, b: u16, c: u32, d: u64 }));
    try std.testing.expectEqual([5]usize{ 1, 2, 4, 8, 16 }, createObjectSizeMap(union { a: u8, b: u16, c: u32, d: u64, e: u128 }));
}

fn findMaxAlign(comptime Object: type) usize {
    const fields = getUnionFields(Object);
    comptime var max_align = 0;
    inline for (fields) |field| {
        max_align = @max(max_align, @alignOf(field.type));
    }
    return max_align;
}

test findMaxAlign {
    try std.testing.expectEqual(16, findMaxAlign(union { a: u8, b: u16, c: u32, d: u64, e: u128 }));
    try std.testing.expectEqual(16, findMaxAlign(union { a: u128, b: u64, c: u32, d: u16, e: u8 }));
    try std.testing.expectEqual(4, findMaxAlign(union { a: u8, b: u16, c: u32 }));
    try std.testing.expectEqual(8, findMaxAlign(union { a: struct { a: u8, b: u16 }, b: struct { a: u32, b: u64 } }));
    try std.testing.expectEqual(16, findMaxAlign(union { a: struct { a: u128, b: u64 }, b: struct { a: u32, b: u64 } }));
}

fn getUnionFields(comptime Object: type) []const std.builtin.Type.UnionField {
    // TODO: ensure field types are unique too
    return switch (@typeInfo(Object)) {
        .Union => |info| if (info.fields.len > 255) @compileError("Object must have <256 fields") else info.fields,
        else => @compileError("Object must be a union"),
    };
}
