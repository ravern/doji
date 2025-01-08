const std = @import("std");
const value = @import("value.zig");

pub const FinalizeContext = struct {
    allocator: std.mem.Allocator,
};

const object_types = [_]type{
    value.List,
    value.String,
};

const object_align = findMaxAlign();
const object_log2_align = std.math.log2(object_align);
const object_header_len = std.mem.alignForward(usize, @sizeOf(ObjectHeader), object_align);

fn findMaxAlign() usize {
    comptime var max_align: usize = @alignOf(ObjectHeader);
    inline for (object_types) |T| {
        max_align = @max(max_align, @alignOf(T));
    }
    return max_align;
}

fn tagFromObjectType(comptime T: type) Tag {
    inline for (object_types, 0..) |U, tag| {
        if (T == U) {
            return @intCast(tag);
        }
    }
    @compileError(@typeName(T) ++ " is not a valid GC object type");
}

fn objectSizeFromTag(tag: Tag) usize {
    inline for (0..object_types.len) |other_tag| {
        if (tag == other_tag) {
            return @sizeOf(object_types[other_tag]);
        }
    }
    @panic("invalid tag");
}

const Color = u2;

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

const Tag = u8;

const ObjectHeader = packed struct {
    _padding: u5 = 0,
    color: Color,
    is_root: bool = false,
    tag: Tag,
    next_ptr: u48 = 0,

    fn fromObject(data: *anyopaque) *ObjectHeader {
        return @ptrFromInt(@intFromPtr(data) - object_header_len);
    }

    fn castObject(self: *ObjectHeader, comptime T: type) ?*T {
        const tag = tagFromObjectType(T);
        if (self.tag != tag) {
            return null;
        }
        return @ptrCast(@alignCast(self.getObject()));
    }

    fn trace(self: *ObjectHeader, tracer: *Tracer) !void {
        inline for (object_types, 0..) |T, tag| {
            if (self.tag == tag) {
                try self.castObject(T).?.trace(tracer);
            }
        }
    }

    fn finalize(self: *ObjectHeader, finalize_ctx: *FinalizeContext) void {
        inline for (object_types, 0..) |T, tag| {
            if (self.tag == tag) {
                self.castObject(T).?.finalize(finalize_ctx);
            }
        }
    }

    fn getNext(self: *ObjectHeader) ?*ObjectHeader {
        return @ptrFromInt(self.next_ptr);
    }

    fn setNext(self: *ObjectHeader, next: ?*ObjectHeader) void {
        self.next_ptr = @truncate(@intFromPtr(next));
    }

    fn removeNext(self: *ObjectHeader) void {
        self.next_ptr = 0;
    }

    fn getObject(self: *ObjectHeader) *anyopaque {
        return @ptrFromInt(@intFromPtr(self) + object_header_len);
    }
};

const ObjectHeaderList = struct {
    first: ?*ObjectHeader = null,

    fn prepend(self: *ObjectHeaderList, header: *ObjectHeader) void {
        header.setNext(self.first);
        self.first = header;
    }

    fn popFirst(self: *ObjectHeaderList) ?*ObjectHeader {
        const header = self.first orelse return null;
        self.first = header.getNext();
        return header;
    }
};

pub const Object = enum {
    pub fn unroot(object: *anyopaque) void {
        const header = ObjectHeader.fromObject(object);
        header.is_root = false;
    }

    pub fn cast(object: *anyopaque, comptime T: type) ?*T {
        const header = ObjectHeader.fromObject(object);
        return header.castObject(T);
    }
};

pub const Tracer = struct {
    gc: *GC,

    pub fn trace(self: *Tracer, object: *anyopaque) !void {
        _ = self;
        _ = object;
    }
};

pub const GC = struct {
    pub const Config = struct {
        step_size: usize = 2048,
    };

    config: Config,
    child_allocator: std.mem.Allocator,
    finalize_ctx: FinalizeContext,
    color_state: ColorState = .{},
    all_objects: ObjectHeaderList = .{},
    gray_set: std.ArrayListUnmanaged(*ObjectHeader) = .{},
    root_set: std.ArrayListUnmanaged(*ObjectHeader) = .{},

    pub fn init(config: Config, child_allocator: std.mem.Allocator, finalize_ctx: FinalizeContext) GC {
        return GC{
            .config = config,
            .child_allocator = child_allocator,
            .finalize_ctx = finalize_ctx,
        };
    }

    pub fn deinit(self: *GC) void {
        self.root_set.deinit(self.child_allocator);
        self.gray_set.deinit(self.child_allocator);

        var curr_object_header = self.all_objects.first;
        while (curr_object_header) |curr| : (curr_object_header = curr.getNext()) {
            curr.finalize(&self.finalize_ctx);
        }
        self.destroyObjectHeaderList(&self.all_objects);

        self.* = undefined;
    }

    pub fn create(self: *GC, comptime T: type) !*T {
        std.debug.print("object_align: {d}\n", .{object_align});
        const total_len = object_header_len + @sizeOf(T);
        const ptr = self.child_allocator.rawAlloc(total_len, object_log2_align, @returnAddress()) orelse
            return std.mem.Allocator.Error.OutOfMemory;
        const header = @as(*ObjectHeader, @ptrCast(@alignCast(ptr)));
        header.* = .{ .color = self.color_state.white, .tag = tagFromObjectType(T) };
        self.all_objects.prepend(header);
        return @ptrCast(@alignCast(header.getObject()));
    }

    pub fn root(self: *GC, object: *anyopaque) !void {
        const header = ObjectHeader.fromObject(object);
        header.is_root = true;
        try self.root_set.append(self.child_allocator, header);
    }

    pub fn mark(self: *GC, object: *anyopaque) !void {
        const header = ObjectHeader.fromObject(object);
        if (header.color == self.color_state.gray) {
            return;
        }
        header.color = self.color_state.gray;
        try self.gray_set.append(self.child_allocator, header);
    }

    pub fn step(self: *GC) !void {
        try self.markRoots();

        for (0..self.config.step_size) |_| {
            self.blackenNext() orelse break;
        }
        if (self.gray_set.items.len != 0) {
            return;
        }

        self.sweep();
        self.color_state.swapWhiteBlack();
    }

    pub fn collect(self: *GC) !void {
        try self.markRoots();

        while (true) {
            self.blackenNext() orelse break;
        }

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
            try self.mark(object_header.getObject());
            i += 1;
        }
    }

    fn blackenNext(self: *GC) ?void {
        const object_header = self.gray_set.popOrNull() orelse return null;
        self.blacken(object_header.getObject());
    }

    fn blacken(self: *GC, object: *anyopaque) void {
        const object_header = ObjectHeader.fromObject(object);
        var tracer = Tracer{ .gc = self };
        try object_header.trace(&tracer);
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
                curr.finalize(&self.finalize_ctx);
            } else {
                prev_object_header = curr;
                curr_object_header = curr.getNext();
            }
        }

        self.destroyObjectHeaderList(&white_objects);
    }

    fn destroyObjectHeaderList(self: *GC, list: *ObjectHeaderList) void {
        while (list.popFirst()) |header| {
            self.destroyObjectHeader(header);
        }
    }

    fn destroyObjectHeader(self: *GC, header: *ObjectHeader) void {
        const total_len = object_header_len + objectSizeFromTag(header.tag);
        self.child_allocator.rawFree(@as([*]u8, @ptrCast(header))[0..total_len], object_log2_align, @returnAddress());
    }
};
