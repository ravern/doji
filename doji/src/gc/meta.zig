const std = @import("std");

pub fn verifyObjectTypes(comptime object_types: anytype) void {
    const info = @typeInfo(@TypeOf(object_types));
    switch (info) {
        .Struct => |struct_info| {
            for (struct_info.fields) |field|
                comptime verifyObject(@field(object_types, field.name));
            return;
        },
        else => {},
    }
    @compileError("expected a literal array of object types");
}

fn verifyObject(comptime Object: type) void {
    if (!@hasDecl(Object, "trace") or
        !@hasDecl(Object, "finalize"))
        @compileError("expected object type '" ++ @typeName(Object) ++ "' to have trace and finalize member functions");
}

pub fn findMaxAlign(comptime object_types: anytype) usize {
    const fields = getFields(object_types);
    comptime var max_align = 0;
    inline for (fields) |field| {
        const Object = @field(object_types, field.name);
        max_align = @max(max_align, @alignOf(Object));
    }
    return max_align;
}

pub fn buildObjectTypeMap(comptime object_types: anytype) [object_types.len]type {
    const fields = getFields(object_types);
    var map: [object_types.len]type = undefined;
    for (fields, 0..) |field, tag| {
        const ObjectType = @field(object_types, field.name);
        map[tag] = ObjectType;
    }
    return map;
}

pub fn tagFromObjectType(comptime object_types: anytype, comptime ObjectType: type, comptime Tag: type) Tag {
    const object_type_map = buildObjectTypeMap(object_types);
    inline for (0..object_type_map.len) |tag| {
        if (ObjectType == object_type_map[tag])
            return tag;
    }
    @compileError("unsupported object type '" ++ @typeName(ObjectType) ++ "'");
}

pub fn objectSizeFromTag(comptime object_types: anytype, comptime Tag: type, tag: Tag) usize {
    inline for (getFields(object_types)) |field| {
        const ObjectType = @field(object_types, field.name);
        if (tag == tagFromObjectType(object_types, ObjectType, Tag)) {
            return @sizeOf(ObjectType);
        }
    }
    unreachable;
}

// TODO: extend to accept multiple arguments
pub fn callObjectMethod(
    comptime object_types: anytype,
    comptime Tag: type,
    tag: Tag,
    object: *anyopaque,
    comptime method_name: []const u8,
    arg: anytype,
) void {
    inline for (getFields(object_types)) |field| {
        const ObjectType = @field(object_types, field.name);
        if (tag == tagFromObjectType(object_types, ObjectType, Tag)) {
            @field(ObjectType, method_name)(@as(*ObjectType, @ptrCast(@alignCast(object))), arg);
            return;
        }
    }
    unreachable;
}

fn getFields(comptime object_types: anytype) []const std.builtin.Type.StructField {
    return @typeInfo(@TypeOf(object_types)).Struct.fields;
}
