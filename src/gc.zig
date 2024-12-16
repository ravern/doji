const std = @import("std");

pub const Config = struct {
    FinalizationContext: ?type = null,
};

pub fn GC(
    comptime ObjectTypes: anytype,
    comptime config: Config,
) type {
    comptime verifyObjectTypes(ObjectTypes);

    const init_finalize_ctx = if (config.FinalizationContext) |FinalizationContext|
        FinalizationContext{}
    else
        ({});

    const FinalizationContext = if (config.FinalizationContext) |FinalizationContext|
        FinalizationContext
    else
        void;

    const object_align = @max(@alignOf(Header), findMaxAlign(ObjectTypes));
    const object_log2_align = std.math.log2_int(usize, object_align);
    const object_header_len = std.mem.alignForward(usize, @sizeOf(Header), object_align);

    return struct {
        const Self = @This();

        const ColorState = struct {
            white: Color = 0,
            black: Color = 1,
            gray: Color = 2,

            fn swapWhiteBlack(self: *ColorState) void {
                const tmp = self.white;
                self.white = self.black;
                self.black = tmp;
            }
        };

        pub const Tracer = struct {
            gc: *Self,

            fn trace(self: *Tracer, object: *anyopaque) void {
                _ = self;
                _ = object;
            }
        };

        child_allocator: std.mem.Allocator,
        finalize_ctx: FinalizationContext = init_finalize_ctx,
        color_state: ColorState = .{},
        all_objects: HeaderList = .{},
        root_set: std.ArrayListUnmanaged(*Header) = .{},
        gray_set: std.ArrayListUnmanaged(*Header) = .{},

        pub fn init(child_allocator: std.mem.Allocator) Self {
            return Self{
                .child_allocator = child_allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.* = undefined;
        }

        pub fn create(self: *Self, comptime ObjectType: type) !*ObjectType {
            const tag = tagFromObjectType(ObjectTypes, ObjectType);

            const total_len = object_header_len + @sizeOf(ObjectType);
            const ptr = self.child_allocator.rawAlloc(total_len, object_log2_align, @returnAddress()) orelse
                return std.mem.Allocator.Error.OutOfMemory;
            const object_header = @as(*Header, @ptrCast(@alignCast(ptr)));
            const object_data = @as(*ObjectType, @ptrCast(@alignCast(ptr[object_header_len..])));

            object_header.* = .{ .color = self.color_state.white, .tag = tag };
            self.all_objects.prepend(object_header);

            var tracer = Tracer{ .gc = self };
            traceObject(object_data, &tracer);
            finalizeObject(object_data, self.finalize_ctx);

            return object_data;
        }

        fn traceObject(object: *anyopaque, tracer: *Tracer) void {
            const object_header = headerFromData(object);
            callObjectMethod(ObjectTypes, object_header.tag, object, "trace", tracer);
        }

        fn finalizeObject(object: *anyopaque, finalize_ctx: FinalizationContext) void {
            const object_header = headerFromData(object);
            callObjectMethod(ObjectTypes, object_header.tag, object, "finalize", finalize_ctx);
        }

        inline fn headerFromData(data: *anyopaque) *Header {
            return @ptrFromInt(@intFromPtr(data) - object_header_len);
        }

        inline fn dataFromHeader(header: *Header) *anyopaque {
            return @ptrFromInt(@intFromPtr(header) + object_header_len);
        }
    };
}

const HeaderList = struct {
    first: ?*Header = null,

    pub fn prepend(self: *HeaderList, header: *Header) void {
        header.setNext(self.first);
        self.first = header;
    }

    pub fn popFirst(self: *HeaderList) ?*Header {
        const header = self.first orelse return null;
        self.first = header.getNext();
        return header;
    }
};

const Color = u2;
const Tag = u8;
const Ptr = u48;

const Header = packed struct {
    is_root: bool = false,
    color: Color,
    _pad: u5 = undefined,
    tag: Tag,
    next: Ptr = 0, // null

    pub fn getNext(self: *Header) ?*Header {
        return @ptrFromInt(@as(usize, @intCast(self.next)));
    }

    pub fn setNext(self: *Header, next: ?*Header) void {
        self.next = @truncate(@intFromPtr(next));
    }

    pub fn removeNext(self: *Header) void {
        const next = self.getNext() orelse return;
        self.setNext(next.getNext());
    }
};

fn ObjectTypeMap(comptime ObjectTypes: anytype) type {
    return [ObjectTypes.len]type;
}

fn buildObjectTypeMap(comptime ObjectTypes: anytype) ObjectTypeMap(ObjectTypes) {
    const fields = getFields(ObjectTypes);
    var map: ObjectTypeMap(ObjectTypes) = undefined;
    for (fields, 0..) |field, tag| {
        const ObjectType = @field(ObjectTypes, field.name);
        map[tag] = ObjectType;
    }
    return map;
}

fn tagFromObjectType(comptime ObjectTypes: anytype, comptime ObjectType: type) Tag {
    const object_type_map = buildObjectTypeMap(ObjectTypes);
    inline for (object_type_map, 0..) |object_type, tag| {
        if (ObjectType == object_type)
            return tag;
    }
    @compileError("Unsupported object type " ++ @typeName(ObjectType) ++ ".");
}

fn callObjectMethod(
    comptime ObjectTypes: anytype,
    tag: Tag,
    object: *anyopaque,
    comptime method_name: []const u8,
    arg: anytype,
) void {
    inline for (getFields(ObjectTypes)) |field| {
        const ObjectType = @field(ObjectTypes, field.name);
        if (tag == tagFromObjectType(ObjectTypes, ObjectType)) {
            @field(ObjectType, method_name)(@as(*ObjectType, @ptrCast(@alignCast(object))), arg);
        }
    }
}

fn findMaxAlign(comptime ObjectTypes: anytype) usize {
    const fields = getFields(ObjectTypes);
    comptime var max_align = 0;
    inline for (fields) |field| {
        const ObjectType = @field(ObjectTypes, field.name);
        max_align = @max(max_align, @alignOf(ObjectType));
    }
    return max_align;
}

fn getFields(comptime ObjectTypes: anytype) []const std.builtin.Type.StructField {
    return @typeInfo(@TypeOf(ObjectTypes)).Struct.fields;
}

fn verifyObjectTypes(comptime ObjectTypes: anytype) void {
    const info = @typeInfo(@TypeOf(ObjectTypes));
    switch (info) {
        .Struct => |struct_info| {
            const max_type_count = std.math.maxInt(Tag) - 1;
            if (struct_info.fields.len > max_type_count)
                @compileError("Too many object types, max is " ++ max_type_count ++ ".");
            for (struct_info.fields) |field| {
                const ObjectType = @field(ObjectTypes, field.name);
                comptime verifyObjectType(ObjectType);
            }
            return;
        },
        else => {},
    }
    @compileError("Expected an anonymous struct literal containing object types.");
}

fn verifyObjectType(comptime ObjectType: type) void {
    const has_trace = @hasDecl(ObjectType, "trace");
    const has_finalize = @hasDecl(ObjectType, "finalize");
    if (!has_trace or !has_finalize)
        @compileError("Expected object type " ++ @typeName(ObjectType) ++ " to have trace and finalize member functions.");
}
