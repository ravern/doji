const std = @import("std");
const code = @import("code.zig");
const value = @import("value.zig");

pub const GC = GarbageCollector(union {
    // values
    string: value.String,
    list: value.List,
    map: value.Map,
    closure: value.Closure,
    fiber: value.Fiber,
    // non-values
    chunk: code.Chunk,
    upvalue: value.Upvalue,
});

pub fn GarbageCollector(
    // union of all the types allowed by this gc instance (max 255 types). this type won't actually be used, but instead
    // be converted into an [ObjectTag] type which has all the same field names. [ObjectTag] comes in handy when trying
    // to decipher what is the type of an [*anyopaque].
    comptime Object: type,
) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        mutator: Mutator,
        objects: ObjectList = .{},
        gray_set: std.ArrayListUnmanaged(*ObjectHeader) = .{},

        colors: struct {
            white: u8 = 0,
            black: u8 = 1,
            gray: u8 = 2,
        } = .{},

        pub const Error = std.mem.Allocator.Error;

        pub const ObjectTag = TagFromObject(Object);

        const default_color = 0;

        const ObjectHeader = packed struct {
            color: u8,
            tag: ObjectTag,
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

        const object_size_map = createObjectSizeMap(Object);

        const object_align = @max(@alignOf(ObjectHeader), findMaxAlign(Object));
        const object_log2_align = std.math.log2_int(usize, object_align);
        const object_header_len = std.mem.alignForward(usize, @sizeOf(ObjectHeader), object_align);

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

        pub const Mutator = struct {
            ptr: *anyopaque,
            vtable: *const VTable,

            pub const VTable = struct {
                mark_roots: *const fn (ctx: *anyopaque, gc: *Self) Error!void,
                trace: *const fn (ctx: *anyopaque, tracer: *Tracer, tag: ObjectTag, data: *anyopaque) Error!void,
                finalize: *const fn (ctx: *anyopaque, tag: ObjectTag, data: *anyopaque) void,
            };
        };

        pub const Tracer = struct {
            gc: *Self,
            action: Action,

            pub const Action = enum {
                mark,
            };

            pub fn trace(self: Tracer, object_data: *anyopaque) !void {
                switch (self.action) {
                    .mark => try self.gc.mark(object_data),
                }
            }
        };

        pub fn init(allocator: std.mem.Allocator, mutator: Mutator) Self {
            return Self{ .allocator = allocator, .mutator = mutator };
        }

        pub fn deinit(self: *Self) void {
            self.destroyObjectList(&self.objects);
            self.gray_set.deinit(self.allocator);
            self.* = undefined;
        }

        pub fn create(self: *Self, comptime T: type) !*T {
            verifyObjectType(Object, T);

            const total_len = object_header_len + @sizeOf(T);
            const ptr = self.allocator.rawAlloc(total_len, object_log2_align, @returnAddress()) orelse return std.mem.Allocator.Error.OutOfMemory;
            const object_header = @as(*ObjectHeader, @ptrCast(@alignCast(ptr)));
            const object_data = @as(*T, @ptrCast(@alignCast(ptr[object_header_len..])));

            object_header.* = .{
                .color = self.colors.white,
                .tag = tagFromObjectType(Object, T),
            };
            self.objects.prepend(object_header);

            return object_data;
        }

        pub fn getTag(self: *const Self, object_data: *anyopaque) ObjectTag {
            _ = self;

            return headerFromData(object_data).tag;
        }

        pub fn mark(self: *Self, object_data: *anyopaque) !void {
            const object_header = headerFromData(object_data);
            if (object_header.color == self.colors.gray or object_header.color == self.colors.black) return;
            object_header.color = self.colors.gray;
            try self.gray_set.append(self.allocator, object_header);
        }

        pub fn collect(self: *Self) !void {
            try self.mutator.vtable.mark_roots(self.mutator.ptr, self);
            while (self.gray_set.popOrNull()) |object_header| {
                try self.blacken(object_header);
            }
            try self.sweep();
            self.swapWhiteBlack();
        }

        fn blacken(self: *Self, object_header: *ObjectHeader) !void {
            var tracer = Tracer{ .gc = self, .action = .mark };
            const object_data = dataFromHeader(object_header);
            try self.mutator.vtable.trace(self.mutator.ptr, &tracer, object_header.tag, object_data);
            object_header.color = self.colors.black;
        }

        fn sweep(self: *Self) !void {
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
                self.mutator.vtable.finalize(self.mutator.ptr, object_header.tag, dataFromHeader(object_header));
            }
            while (objects.popFirst()) |object_header| {
                self.destroyObjectHeader(object_header);
            }
        }

        fn destroyObjectHeader(self: *const Self, object_header: *ObjectHeader) void {
            const total_len = object_header_len + object_size_map.get(object_header.tag);
            self.allocator.rawFree(@as([*]u8, @ptrCast(object_header))[0..total_len], object_log2_align, @returnAddress());
        }

        fn swapWhiteBlack(self: *Self) void {
            const tmp = self.colors.white;
            self.colors.white = self.colors.black;
            self.colors.black = tmp;
        }

        fn headerFromData(ptr: *anyopaque) *ObjectHeader {
            return @ptrFromInt(@intFromPtr(ptr) - object_header_len);
        }

        fn dataFromHeader(header: *ObjectHeader) *anyopaque {
            return @ptrFromInt(@intFromPtr(header) + object_header_len);
        }
    };
}

test GarbageCollector {
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

        fn deinit(self: *Self) void {
            self.result.putFreedObject(self.key);
            self.refs.deinit();
        }

        fn addRef(self: *Self, child_object: *Self) !void {
            try self.refs.put(child_object.key, child_object);
        }

        fn removeRef(self: *Self, child_object: *Self) void {
            _ = self.refs.remove(child_object.key);
        }
    };

    const Object = union { test_object: TestObject };
    const TestGC = GarbageCollector(Object);

    const TestMutator = struct {
        allocator: std.mem.Allocator,
        gc: TestGC,
        root_object: *TestObject,

        const Self = @This();

        fn mutator(self: *Self) TestGC.Mutator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .mark_roots = markRoots,
                    .trace = traceObject,
                    .finalize = finalizeObject,
                },
            };
        }

        fn init(allocator: std.mem.Allocator, result: *TestResult) !*Self {
            var self = try allocator.create(Self);
            self.* = .{ .allocator = allocator, .gc = undefined, .root_object = undefined };

            self.gc = TestGC.init(allocator, self.mutator());

            self.root_object = try self.gc.create(TestObject);
            self.root_object.* = TestObject.init(self.allocator, "__root__", result);

            return self;
        }

        fn deinit(self: *Self) void {
            self.gc.deinit();
            self.allocator.destroy(self);
        }

        fn markRoots(ctx: *anyopaque, gc: *TestGC) !void {
            const self = @as(*Self, @ptrCast(@alignCast(ctx)));

            try gc.mark(self.root_object);
        }

        fn traceObject(ctx: *anyopaque, tracer: *TestGC.Tracer, object_tag: TestGC.ObjectTag, object_data: *anyopaque) !void {
            _ = ctx;
            _ = object_tag;

            const object = @as(*TestObject, @ptrCast(@alignCast(object_data)));
            var it = object.refs.valueIterator();
            while (it.next()) |child_object| {
                try tracer.trace(child_object.*);
            }
        }

        fn finalizeObject(ctx: *anyopaque, tag: TestGC.ObjectTag, object_data: *anyopaque) void {
            _ = ctx;
            _ = tag;

            const object = @as(*TestObject, @ptrCast(@alignCast(object_data)));
            object.deinit();
        }
    };

    var result = TestResult.init(std.testing.allocator);
    defer result.deinit();

    var mutator = try TestMutator.init(std.testing.allocator, &result);
    defer mutator.deinit();

    // basic example

    const basic_1_object = try mutator.gc.create(TestObject);
    basic_1_object.* = TestObject.init(mutator.allocator, "basic_1", &result);
    const basic_2_object = try mutator.gc.create(TestObject);
    basic_2_object.* = TestObject.init(mutator.allocator, "basic_2", &result);

    try mutator.root_object.addRef(basic_1_object);
    try mutator.root_object.addRef(basic_2_object);
    try mutator.gc.collect();
    try std.testing.expect(!result.hasFreedObject("basic_1"));
    try std.testing.expect(!result.hasFreedObject("basic_2"));

    mutator.root_object.removeRef(basic_1_object);
    try mutator.gc.collect();
    try std.testing.expect(result.hasFreedObject("basic_1"));
    try std.testing.expect(!result.hasFreedObject("basic_2"));

    mutator.root_object.removeRef(basic_2_object);
    try mutator.gc.collect();
    try std.testing.expect(result.hasFreedObject("basic_1"));
    try std.testing.expect(result.hasFreedObject("basic_2"));

    // multiple layers

    const layers_1_object = try mutator.gc.create(TestObject);
    layers_1_object.* = TestObject.init(mutator.allocator, "layers_1", &result);
    const layers_2_object = try mutator.gc.create(TestObject);
    layers_2_object.* = TestObject.init(mutator.allocator, "layers_2", &result);
    const layers_3_object = try mutator.gc.create(TestObject);
    layers_3_object.* = TestObject.init(mutator.allocator, "layers_3", &result);
    const layers_4_object = try mutator.gc.create(TestObject);
    layers_4_object.* = TestObject.init(mutator.allocator, "layers_4", &result);
    const layers_5_object = try mutator.gc.create(TestObject);
    layers_5_object.* = TestObject.init(mutator.allocator, "layers_5", &result);

    try mutator.root_object.addRef(layers_1_object);
    try mutator.root_object.addRef(layers_2_object);
    try layers_2_object.addRef(layers_3_object);
    try layers_2_object.addRef(layers_4_object);
    try layers_3_object.addRef(layers_5_object);
    try mutator.gc.collect();
    try std.testing.expect(!result.hasFreedObject("layers_1"));
    try std.testing.expect(!result.hasFreedObject("layers_2"));
    try std.testing.expect(!result.hasFreedObject("layers_3"));
    try std.testing.expect(!result.hasFreedObject("layers_4"));
    try std.testing.expect(!result.hasFreedObject("layers_5"));

    mutator.root_object.removeRef(layers_1_object);
    try mutator.gc.collect();
    try std.testing.expect(result.hasFreedObject("layers_1"));
    try std.testing.expect(!result.hasFreedObject("layers_2"));
    try std.testing.expect(!result.hasFreedObject("layers_3"));
    try std.testing.expect(!result.hasFreedObject("layers_4"));
    try std.testing.expect(!result.hasFreedObject("layers_5"));

    mutator.root_object.removeRef(layers_2_object);
    try mutator.gc.collect();
    try std.testing.expect(result.hasFreedObject("layers_1"));
    try std.testing.expect(result.hasFreedObject("layers_2"));
    try std.testing.expect(result.hasFreedObject("layers_3"));
    try std.testing.expect(result.hasFreedObject("layers_4"));
    try std.testing.expect(result.hasFreedObject("layers_5"));

    // circular references

    const circular_1_object = try mutator.gc.create(TestObject);
    circular_1_object.* = TestObject.init(mutator.allocator, "circular_1", &result);
    const circular_2_object = try mutator.gc.create(TestObject);
    circular_2_object.* = TestObject.init(mutator.allocator, "circular_2", &result);

    try mutator.root_object.addRef(circular_1_object);
    try circular_1_object.addRef(circular_2_object);
    try circular_2_object.addRef(circular_1_object);
    try mutator.gc.collect();
    try std.testing.expect(!result.hasFreedObject("circular_1"));
    try std.testing.expect(!result.hasFreedObject("circular_2"));

    mutator.root_object.removeRef(circular_1_object);
    try mutator.gc.collect();
    try std.testing.expect(result.hasFreedObject("circular_1"));
    try std.testing.expect(result.hasFreedObject("circular_2"));

    // pointing to root

    const point_root_object = try mutator.gc.create(TestObject);
    point_root_object.* = TestObject.init(mutator.allocator, "point_root", &result);

    try point_root_object.addRef(mutator.root_object);
    try mutator.gc.collect();
    try std.testing.expect(result.hasFreedObject("point_root"));
}

fn TagFromObject(comptime Object: type) type {
    const union_fields = getUnionFields(Object);
    var enum_fields: [union_fields.len]std.builtin.Type.EnumField = undefined;
    inline for (union_fields, 0..) |union_field, index| {
        enum_fields[index] = .{
            .name = union_field.name,
            .value = @intCast(index),
        };
    }
    return @Type(.{
        .Enum = .{
            .tag_type = u8,
            .fields = &enum_fields,
            .decls = &.{},
            .is_exhaustive = true,
        },
    });
}

test TagFromObject {
    const Tag = TagFromObject(union { a: u8, b: u16 });
    try std.testing.expectEqual(0, @intFromEnum(Tag.a));
    try std.testing.expectEqual(1, @intFromEnum(Tag.b));
}

fn tagFromObjectType(comptime Object: type, comptime T: type) TagFromObject(Object) {
    const union_fields = getUnionFields(Object);
    const enum_fields = std.meta.fields(TagFromObject(Object));
    inline for (union_fields, enum_fields) |union_field, enum_field| {
        if (!std.mem.eql(u8, union_field.name, enum_field.name)) unreachable;
        if (union_field.type == T) return @enumFromInt(enum_field.value);
    }
    unreachable;
}

fn verifyObjectType(comptime Object: type, comptime T: type) void {
    const fields = getUnionFields(Object);
    inline for (fields) |field| {
        if (field.type == T) return;
    }
    @compileError(@typeName(T) ++ " is not a valid GC object type");
}

fn createObjectSizeMap(comptime Object: type) std.EnumArray(TagFromObject(Object), usize) {
    const fields = getUnionFields(Object);
    var map = std.EnumArray(TagFromObject(Object), usize).initUndefined();
    inline for (fields) |field| {
        map.set(tagFromObjectType(Object, field.type), @sizeOf(field.type));
    }
    return map;
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
    return switch (@typeInfo(Object)) {
        .Union => |info| if (info.fields.len > 255) @compileError("Object must have <256 fields") else info.fields,
        else => @compileError("Object must be a union"),
    };
}
