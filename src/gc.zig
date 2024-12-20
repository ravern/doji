const std = @import("std");

pub const Strategy = union(enum) {
    disable_gc: void,
    disable_incremental: void,
    incremental_fixed: usize,
};

pub const Config = struct {
    strategy: Strategy = .{ .incremental_fixed = 1024 },
    FinalizeContext: type = void,
    enable_stats: bool = true,
};

pub fn GC(
    comptime ObjectTypes: anytype,
    comptime config: Config,
) type {
    comptime verifyObjectTypes(ObjectTypes);

    const object_align = @max(@alignOf(ObjectHeader), findMaxAlign(ObjectTypes));
    const object_log2_align = std.math.log2_int(usize, object_align);
    const object_header_len = std.mem.alignForward(usize, @sizeOf(ObjectHeader), object_align);

    const FinalizeContext = config.FinalizeContext;

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

        pub const Statistics = if (config.enable_stats)
            struct {
                live_objects: usize = 0,
                created_objects: usize = 0,
                destroyed_objects: usize = 0,
                live_bytes: usize = 0,
                created_bytes: usize = 0,
                destroyed_bytes: usize = 0,
            }
        else
            void;

        pub const Tracer = struct {
            gc: *Self,

            fn trace(self: *Tracer, object: *anyopaque) void {
                const object_header = headerFromData(object);
                if (object_header.color == self.gc.color_state.black)
                    return;
                self.gc.mark(object);
            }
        };

        child_allocator: std.mem.Allocator,
        finalize_ctx: FinalizeContext,
        color_state: ColorState = .{},
        all_objects: ObjectHeaderList = .{},
        root_set: std.ArrayListUnmanaged(*ObjectHeader) = .{},
        gray_set: std.ArrayListUnmanaged(*ObjectHeader) = .{},
        stats: Statistics = .{},

        pub fn init(child_allocator: std.mem.Allocator, finalize_ctx: FinalizeContext) Self {
            return Self{
                .child_allocator = child_allocator,
                .finalize_ctx = finalize_ctx,
            };
        }

        pub fn deinit(self: *Self) void {
            self.root_set.deinit(self.child_allocator);
            self.gray_set.deinit(self.child_allocator);

            var curr_object_header = self.all_objects.first;
            while (curr_object_header) |curr| : (curr_object_header = curr.getNext())
                finalizeObject(dataFromHeader(curr), self.finalize_ctx);
            self.destroyObjectHeaderList(&self.all_objects);

            self.* = undefined;
        }

        pub fn create(self: *Self, comptime ObjectType: type) !*ObjectType {
            const tag = tagFromObjectType(ObjectTypes, ObjectType);

            const total_len = object_header_len + @sizeOf(ObjectType);
            const ptr = self.child_allocator.rawAlloc(total_len, object_log2_align, @returnAddress()) orelse
                return std.mem.Allocator.Error.OutOfMemory;
            const object_header = @as(*ObjectHeader, @ptrCast(@alignCast(ptr)));
            const object_data = @as(*ObjectType, @ptrCast(@alignCast(ptr[object_header_len..])));

            object_header.* = .{ .color = self.color_state.white, .tag = tag };
            self.all_objects.prepend(object_header);

            if (config.enable_stats) {
                self.stats.live_objects += 1;
                self.stats.live_bytes += total_len;
                self.stats.created_objects += 1;
                self.stats.created_bytes += total_len;
            }

            return object_data;
        }

        pub fn root(self: *Self, object: *anyopaque) !void {
            const object_header = headerFromData(object);
            object_header.is_root = true;
            try self.root_set.append(self.child_allocator, object_header);
        }

        pub fn unroot(self: *Self, object: *anyopaque) void {
            _ = self;
            const object_header = headerFromData(object);
            object_header.is_root = false;
        }

        pub fn mark(self: *Self, object: *anyopaque) !void {
            const object_header = headerFromData(object);
            if (object_header.color == self.color_state.gray)
                return;
            object_header.color = self.color_state.gray;
            try self.gray_set.append(self.child_allocator, object_header);
        }

        pub fn step(self: *Self) !void {
            switch (config.strategy) {
                .disable_gc => return,
                .disable_incremental => return self.collect(),
                else => {},
            }

            try self.markRoots();

            for (0..calculateStepObjectCount()) |_|
                self.blackenNext() orelse break;
            if (self.gray_set.items.len != 0)
                return;

            self.sweep();
            self.color_state.swapWhiteBlack();
        }

        pub fn collect(self: *Self) !void {
            switch (config.strategy) {
                .disable_gc => return,
                else => {},
            }

            try self.markRoots();

            while (true)
                self.blackenNext() orelse break;

            self.sweep();
            self.color_state.swapWhiteBlack();
        }

        fn markRoots(self: *Self) !void {
            var i: usize = 0;
            while (i < self.root_set.items.len) {
                const object_header = self.root_set.items[i];

                // if the object is not a root, remove it from the root set
                if (!object_header.is_root) {
                    _ = self.root_set.swapRemove(i);
                    continue;
                }

                // otherwise, mark the root
                try self.mark(dataFromHeader(object_header));
                i += 1;
            }
        }

        fn blackenNext(self: *Self) ?void {
            const object_header = self.gray_set.popOrNull() orelse return null;
            self.blacken(dataFromHeader(object_header));
        }

        fn blacken(self: *Self, object: *anyopaque) void {
            const object_header = headerFromData(object);
            var tracer = Tracer{ .gc = self };
            traceObject(object, &tracer);
            object_header.color = self.color_state.black;
        }

        fn sweep(self: *Self) void {
            var white_objects = ObjectHeaderList{};

            var prev_object_header: ?*ObjectHeader = null;
            var curr_object_header = self.all_objects.first;
            while (curr_object_header) |curr| {
                if (curr.color == self.color_state.white) {
                    if (prev_object_header) |prev| {
                        prev.removeNext();
                        curr_object_header = prev.getNext();
                    } else {
                        curr_object_header = curr.getNext();
                        self.all_objects.first = curr_object_header;
                    }

                    // add the object to the white set, and finalize it at the same time (instead
                    // of a second loop to finalize all white objects).
                    white_objects.prepend(curr);
                    finalizeObject(dataFromHeader(curr), self.finalize_ctx);
                } else {
                    prev_object_header = curr;
                    curr_object_header = curr.getNext();
                }
            }

            self.destroyObjectHeaderList(&white_objects);
        }

        fn destroyObjectHeaderList(self: *Self, list: *ObjectHeaderList) void {
            while (list.popFirst()) |object_header|
                self.destroyObjectHeader(object_header);
        }

        fn destroyObjectHeader(self: *Self, object_header: *ObjectHeader) void {
            const total_len = object_header_len + objectSizeFromTag(ObjectTypes, object_header.tag);
            self.child_allocator.rawFree(@as([*]u8, @ptrCast(object_header))[0..total_len], object_log2_align, @returnAddress());

            if (config.enable_stats) {
                self.stats.live_objects -= 1;
                self.stats.live_bytes -= total_len;
                self.stats.destroyed_objects += 1;
                self.stats.destroyed_bytes += total_len;
            }
        }

        fn traceObject(object_data: *anyopaque, tracer: *Tracer) void {
            const object_header = headerFromData(object_data);
            callObjectMethod(ObjectTypes, object_header.tag, object_data, "trace", tracer);
        }

        fn finalizeObject(object_data: *anyopaque, finalize_ctx: FinalizeContext) void {
            const object_header = headerFromData(object_data);
            callObjectMethod(ObjectTypes, object_header.tag, object_data, "finalize", finalize_ctx);
        }

        inline fn calculateStepObjectCount() usize {
            return switch (config.strategy) {
                .incremental_fixed => |count| count,
                else => unreachable,
            };
        }

        inline fn headerFromData(data: *anyopaque) *ObjectHeader {
            return @ptrFromInt(@intFromPtr(data) - object_header_len);
        }

        inline fn dataFromHeader(header: *ObjectHeader) *anyopaque {
            return @ptrFromInt(@intFromPtr(header) + object_header_len);
        }
    };
}

const ObjectHeaderList = struct {
    first: ?*ObjectHeader = null,

    pub fn prepend(self: *ObjectHeaderList, header: *ObjectHeader) void {
        header.setNext(self.first);
        self.first = header;
    }

    pub fn popFirst(self: *ObjectHeaderList) ?*ObjectHeader {
        const header = self.first orelse return null;
        self.first = header.getNext();
        return header;
    }
};

const Color = u2;
const Tag = u8;
const Ptr = u48;

const ObjectHeader = packed struct {
    is_root: bool = false,
    color: Color,
    _pad: u5 = undefined,
    tag: Tag,
    next: Ptr = 0, // null

    pub fn getNext(self: *ObjectHeader) ?*ObjectHeader {
        return @ptrFromInt(@as(usize, @intCast(self.next)));
    }

    pub fn setNext(self: *ObjectHeader, next: ?*ObjectHeader) void {
        self.next = @truncate(@intFromPtr(next));
    }

    pub fn removeNext(self: *ObjectHeader) void {
        const next = self.getNext() orelse return;
        self.setNext(next.getNext());
    }
};

fn buildObjectTypeMap(comptime ObjectTypes: anytype) [ObjectTypes.len]type {
    const fields = getFields(ObjectTypes);
    var map: [ObjectTypes.len]type = undefined;
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
    @compileError("unsupported object type '" ++ @typeName(ObjectType) ++ "'");
}

fn objectSizeFromTag(comptime ObjectTypes: anytype, tag: Tag) usize {
    inline for (getFields(ObjectTypes)) |field| {
        const ObjectType = @field(ObjectTypes, field.name);
        if (tag == tagFromObjectType(ObjectTypes, ObjectType)) {
            return @sizeOf(ObjectType);
        }
    }
    unreachable;
}

// TODO: extend to accept multiple arguments
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
            return;
        }
    }
    unreachable;
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
                @compileError("too many object types, a max of " ++ max_type_count ++ " is supported");
            for (struct_info.fields) |field| {
                const ObjectType = @field(ObjectTypes, field.name);
                comptime verifyObjectType(ObjectType);
            }
            return;
        },
        else => {},
    }
    @compileError("expected an anonymous struct literal containing object types");
}

fn verifyObjectType(comptime ObjectType: type) void {
    const has_trace = @hasDecl(ObjectType, "trace");
    const has_finalize = @hasDecl(ObjectType, "finalize");
    if (!has_trace or !has_finalize)
        @compileError("expected object type '" ++ @typeName(ObjectType) ++ "' to have trace and finalize member functions");
}
