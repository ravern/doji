const std = @import("std");
const Tracer = @import("../gc.zig").Tracer;

pub const Color = u2;

const Tag = u8;
const Ptr = u48;

pub fn Object(comptime object_types: anytype, comptime FinalizeContext: type) type {
    verifyObjectTypes(object_types);

    return packed struct {
        const Self = @This();

        is_root: bool = false,
        color: Color,
        _pad: u5 = undefined,
        tag: Tag,
        next: Ptr = 0, // null

        const max_align = @max(@alignOf(Self), findMaxAlign(object_types));
        const log2_max_align = std.math.log2_int(usize, max_align);
        const header_len = std.mem.alignForward(usize, @sizeOf(Self), max_align);

        pub fn create(comptime ObjectType: type, allocator: std.mem.Allocator, color: Color) !*Self {
            const total_len = header_len + @sizeOf(ObjectType);
            const ptr = allocator.rawAlloc(total_len, max_align, @returnAddress()) orelse
                return std.mem.Allocator.Error.OutOfMemory;
            const object = @as(*Self, @ptrCast(@alignCast(ptr)));
            object.* = .{ .color = color, .tag = tagFromObjectType(object_types, ObjectType) };
            return object;
        }

        pub fn destroy(self: *Self, allocator: std.mem.Allocator) void {
            const total_len = header_len + objectSizeFromTag(object_types, self.tag);
            allocator.rawFree(@as([*]u8, @ptrCast(self))[0..total_len], max_align, @returnAddress());
        }

        pub fn trace(self: *Self, tracer: Tracer) void {
            callMethod(object_types, self.tag, self.toData(), "trace", tracer);
        }

        pub fn finalize(self: *Self, context: FinalizeContext) void {
            callMethod(object_types, self.tag, self.toData(), "finalize", context);
        }

        pub fn getNext(self: *Self) ?*Self {
            return @ptrFromInt(@as(usize, @intCast(self.next)));
        }

        pub fn setNext(self: *Self, next: ?*Self) void {
            self.next = @truncate(@intFromPtr(next));
        }

        pub fn removeNext(self: *Self) void {
            const next = self.getNext() orelse
                return;
            self.setNext(next.getNext());
        }

        pub fn fromData(data: *anyopaque) *Self {
            return @ptrFromInt(@intFromPtr(data) - header_len);
        }

        pub fn toData(self: *Self) *anyopaque {
            return @ptrFromInt(@intFromPtr(self) + header_len);
        }
    };
}

fn verifyObjectTypes(comptime object_types: anytype) void {
    const info = @typeInfo(@TypeOf(object_types));
    switch (info) {
        .Struct => |struct_info| {
            for (struct_info.fields) |field| {
                if (!@hasDecl(field.type, "trace") or !@hasDecl(field.type, "finalize")) {
                    @compileError("expected object type '" ++ @typeName(field.type) ++ "' to have trace and finalize member functions");
                }
            }
            return;
        },
        else => {},
    }
    @compileError("expected a literal array of object types");
}

fn findMaxAlign(comptime object_types: anytype) usize {
    const fields = getFields(object_types);
    comptime var max_align = 0;
    inline for (fields) |field| {
        const ObjectType = @field(object_types, field.name);
        max_align = @max(max_align, @alignOf(ObjectType));
    }
    return max_align;
}

// TODO: extend to accept multiple arguments
fn callMethod(
    comptime object_types: anytype,
    tag: Tag,
    object_data: *anyopaque,
    comptime method_name: []const u8,
    arg: anytype,
) void {
    const fields = getFields(object_types);
    inline for (fields) |field| {
        const ObjectType = @field(object_types, field.name);
        if (tag == tagFromObjectType(object_types, ObjectType, Tag)) {
            @field(ObjectType, method_name)(@as(*ObjectType, @ptrCast(@alignCast(object_data))), arg);
            return;
        }
    }
    unreachable;
}

fn tagFromObjectType(comptime object_types: anytype, comptime ObjectType: type) Tag {
    const fields = getFields(object_types);
    inline for (fields, 0..) |field, tag| {
        if (field.type == ObjectType) {
            return @intCast(tag);
        }
    }
    @compileError("unsupported object type '" ++ @typeName(ObjectType) ++ "'");
}

fn objectSizeFromTag(comptime object_types: anytype, tag: Tag) usize {
    const fields = getFields(object_types);
    inline for (fields) |field| {
        const ObjectType = @field(object_types, field.name);
        if (tag == tagFromObjectType(object_types, ObjectType)) {
            return @sizeOf(ObjectType);
        }
    }
    unreachable;
}

fn getFields(comptime object_types: anytype) []const std.builtin.Type.StructField {
    return @typeInfo(@TypeOf(object_types)).Struct.fields;
}
