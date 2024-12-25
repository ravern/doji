const std = @import("std");
const value = @import("value.zig");
const meta = @import("gc/meta.zig");

const object_types = .{
    value.String,
    value.List,
    value.Fiber,
};

comptime {
    meta.verifyObjectTypes(object_types);
}

const object_align = @max(@alignOf(ObjectHeader), meta.findMaxAlign(object_types));
const object_log2_align = std.math.log2_int(usize, object_align);
const object_header_len = std.mem.alignForward(usize, @sizeOf(ObjectHeader), object_align);

pub const Tracer = struct {
    gc: *GC,

    fn trace(self: *Tracer, object: *anyopaque) void {
        const object_header = headerFromData(object);
        if (object_header.color == self.gc.color_state.black)
            return;
        self.gc.mark(object);
    }
};

pub const FinalizeContext = struct {
    allocator: std.mem.Allocator,
};

pub const GC = struct {
    pub const Config = struct {};

    const ColorState = struct {
        white: ObjectColor = 0,
        black: ObjectColor = 1,
        gray: ObjectColor = 2,

        fn swapWhiteBlack(self: *ColorState) void {
            const tmp = self.white;
            self.white = self.black;
            self.black = tmp;
        }
    };

    child_allocator: std.mem.Allocator,
    config: Config,
    finalize_ctx: FinalizeContext,
    color_state: ColorState = .{},
    all_objects: ObjectHeaderList = .{},
    root_set: std.ArrayListUnmanaged(*ObjectHeader) = .{},
    gray_set: std.ArrayListUnmanaged(*ObjectHeader) = .{},

    pub fn init(child_allocator: std.mem.Allocator, config: Config, finalize_ctx: FinalizeContext) GC {
        return .{
            .child_allocator = child_allocator,
            .config = config,
            .finalize_ctx = finalize_ctx,
        };
    }

    pub fn deinit(self: *GC) void {
        self.root_set.deinit(self.child_allocator);
        self.gray_set.deinit(self.child_allocator);

        var curr_object_header = self.all_objects.first;
        while (curr_object_header) |curr| : (curr_object_header = curr.getNext())
            finalizeObject(dataFromHeader(curr), self.finalize_ctx);
        self.destroyObjectHeaderList(&self.all_objects);

        self.* = undefined;
    }

    pub fn create(self: *GC, comptime ObjectType: type) !*ObjectType {
        const tag = meta.tagFromObjectType(object_types, ObjectType, ObjectTag);

        const total_len = object_header_len + @sizeOf(ObjectType);
        const ptr = self.child_allocator.rawAlloc(total_len, object_log2_align, @returnAddress()) orelse
            return std.mem.Allocator.Error.OutOfMemory;
        const object_header = @as(*ObjectHeader, @ptrCast(@alignCast(ptr)));
        const object_data = @as(*ObjectType, @ptrCast(@alignCast(ptr[object_header_len..])));

        object_header.* = .{ .color = self.color_state.white, .tag = tag };
        self.all_objects.prepend(object_header);

        return object_data;
    }

    pub fn root(self: *GC, object: *anyopaque) !void {
        const object_header = headerFromData(object);
        object_header.is_root = true;
        try self.root_set.append(self.child_allocator, object_header);
    }

    pub fn unroot(self: *GC, object: *anyopaque) void {
        _ = self;
        const object_header = headerFromData(object);
        object_header.is_root = false;
    }

    pub fn mark(self: *GC, object: *anyopaque) !void {
        const object_header = headerFromData(object);
        if (object_header.color == self.color_state.gray)
            return;
        object_header.color = self.color_state.gray;
        try self.gray_set.append(self.child_allocator, object_header);
    }

    pub fn step(self: *GC) !void {
        try self.markRoots();

        for (0..2048) |_|
            self.blackenNext() orelse break;
        if (self.gray_set.items.len != 0)
            return;

        self.sweep();
        self.color_state.swapWhiteBlack();
    }

    pub fn collect(self: *GC) !void {
        try self.markRoots();

        while (true)
            self.blackenNext() orelse break;

        self.sweep();
        self.color_state.swapWhiteBlack();
    }

    fn markRoots(self: *GC) !void {
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

    fn blackenNext(self: *GC) ?void {
        const object_header = self.gray_set.popOrNull() orelse return null;
        self.blacken(dataFromHeader(object_header));
    }

    fn blacken(self: *GC, object: *anyopaque) void {
        const object_header = headerFromData(object);
        var tracer = Tracer{ .gc = self };
        traceObject(object, &tracer);
        object_header.color = self.color_state.black;
    }

    fn sweep(self: *GC) void {
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

    fn destroyObjectHeaderList(self: *GC, list: *ObjectHeaderList) void {
        while (list.popFirst()) |object_header|
            self.destroyObjectHeader(object_header);
    }

    fn destroyObjectHeader(self: *GC, object_header: *ObjectHeader) void {
        const total_len = object_header_len + meta.objectSizeFromTag(object_types, ObjectTag, object_header.tag);
        self.child_allocator.rawFree(@as([*]u8, @ptrCast(object_header))[0..total_len], object_log2_align, @returnAddress());
    }

    fn traceObject(object_data: *anyopaque, tracer: *Tracer) void {
        const object_header = headerFromData(object_data);
        meta.callObjectMethod(object_types, ObjectTag, object_header.tag, object_data, "trace", tracer);
    }

    fn finalizeObject(object_data: *anyopaque, finalize_ctx: FinalizeContext) void {
        const object_header = headerFromData(object_data);
        meta.callObjectMethod(object_types, ObjectTag, object_header.tag, object_data, "finalize", finalize_ctx);
    }
};

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

const ObjectColor = u2;
const ObjectTag = u8;
const ObjectRawPtr = u48;

const ObjectHeader = packed struct {
    is_root: bool = false,
    color: ObjectColor,
    _pad: u5 = undefined,
    tag: ObjectTag,
    next: ObjectRawPtr = 0, // null

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

inline fn headerFromData(data: *anyopaque) *ObjectHeader {
    return @ptrFromInt(@intFromPtr(data) - object_header_len);
}

inline fn dataFromHeader(header: *ObjectHeader) *anyopaque {
    return @ptrFromInt(@intFromPtr(header) + object_header_len);
}
