const std = @import("std");
const VM = @import("vm.zig").VM;
const Fiber = @import("vm.zig").Fiber;
const value = @import("value.zig");

pub const GC = struct {
    allocator: std.mem.Allocator,
    vm: *VM,
    objects: ObjectList = .{},
    gray_set: std.ArrayListUnmanaged(*Object) = .{},

    // colors are defined dynamically; we want to swap white and black colors dynamically, so we don't have
    // to re-trace the entire object graph to reset objects to white after each collection cycle.
    colors: Colors = .{},

    const Colors = struct {
        white: u8 = 0,
        black: u8 = 1,
        gray: u8 = 2,

        fn swapWhiteAndBlack(self: *Colors) void {
            const tmp = self.white;
            self.white = self.black;
            self.black = tmp;
        }
    };

    pub fn init(allocator: std.mem.Allocator, vm: *VM) GC {
        return GC{
            .allocator = allocator,
            .vm = vm,
        };
    }

    pub fn deinit(self: *GC) void {
        self.gray_set.deinit(self.allocator);
        self.objects.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn create(self: *GC, comptime T: type) !*T {
        const object = try self.allocator.create(Object);
        object.* = Object.init(self.colors.white, T);

        self.objects.prepend(object);

        return object.cast(T).?;
    }

    pub fn cast(comptime T: type, ptr: *anyopaque) ?*T {
        return Object.fromPtr(ptr).cast(T);
    }

    pub fn mark(self: *GC, ptr: *anyopaque) !void {
        const object = Object.fromPtr(ptr);
        if (object.header.color == self.colors.gray) return;
        try self.gray_set.append(self.allocator, object);
    }

    pub fn collect(self: *GC) !void {
        try self.vm.markRoots();
        while (self.gray_set.popOrNull()) |object| {
            try self.blacken(object);
        }
        self.sweep();
        self.colors.swapWhiteAndBlack();
    }

    fn blacken(self: *GC, object: *Object) !void {
        if (object.header.color == self.colors.black) return;
        try object.trace(self, Tracer.mark);
        object.header.color = self.colors.black;
    }

    fn sweep(self: *GC) void {
        // no need to sweep if there are no objects
        if (self.objects.first == null) return;

        var white_set = ObjectList{};

        // traverse the objects list, remove each white object and add it to the white set
        var prev_object: ?*Object = null;
        var curr_object = self.objects.first;
        while (curr_object) |curr| {
            if (curr.header.color == self.colors.white) {
                if (prev_object) |prev| {
                    white_set.prepend(prev.removeNext().?);
                    curr_object = prev.getNext();
                } else {
                    white_set.prepend(self.objects.popFirst().?);
                    curr_object = self.objects.first;
                }
            } else {
                prev_object = curr;
                curr_object = curr.getNext();
            }
        }

        // deinit the object list all at once
        white_set.deinit(self.allocator);
    }
};

pub const Tracer = enum {
    mark,

    pub fn trace(self: *const Tracer, gc: *GC, ptr: *anyopaque) !void {
        switch (self.*) {
            .mark => try gc.mark(ptr),
        }
    }
};

const ObjectList = struct {
    first: ?*Object = null,

    fn deinit(self: *ObjectList, allocator: std.mem.Allocator) void {
        var curr_object = self.first;
        while (curr_object) |object| : (curr_object = object.getNext()) {
            object.data.deinit(object.header.tag, allocator);
        }
        while (self.popFirst()) |object| {
            allocator.destroy(object);
        }
    }

    fn popFirst(self: *ObjectList) ?*Object {
        const object = self.first orelse return null;
        self.first = object.getNext();
        return object;
    }

    fn prepend(self: *ObjectList, object: *Object) void {
        object.setNext(self.first);
        self.first = object;
    }
};

const Object = struct {
    header: Header,
    data: Data,

    // TODO: there's probably a way to build this at comptime from [Data]
    const Tag = enum(u8) {
        fiber,
        list,
        map,
    };

    const Header = packed struct {
        color: u8,
        tag: Tag,
        next_ptr: u48 = 0,
    };

    const Data = union {
        fiber: Fiber,
        list: value.List,
        map: value.Map,

        fn deinit(self: *Data, tag: Tag, allocator: std.mem.Allocator) void {
            switch (tag) {
                .fiber => self.fiber.deinit(allocator),
                .list => self.list.deinit(allocator),
                .map => self.map.deinit(allocator),
            }
            self.* = undefined;
        }
    };

    fn init(color: u8, comptime T: type) Object {
        const field_name = comptime fieldNameFromType(T);

        const tag = @field(Tag, field_name);
        return .{
            .header = .{
                .color = color,
                .tag = @field(Tag, field_name),
            },
            // TODO: probably a more Zig-y way to do this
            .data = switch (tag) {
                .fiber => .{ .fiber = undefined },
                .list => .{ .list = undefined },
                .map => .{ .map = undefined },
            },
        };
    }

    fn cast(self: *Object, comptime T: type) ?*T {
        const field_name = comptime fieldNameFromType(T);
        if (self.header.tag != @field(Tag, field_name)) return null;
        return &@field(self.data, field_name);
    }

    fn fromPtr(ptr: *anyopaque) *Object {
        return @fieldParentPtr("data", @as(*Data, @ptrCast(@alignCast(ptr))));
    }

    fn setNext(self: *Object, next: ?*Object) void {
        // TODO: add check to ensure that pointers only take up 48 bits
        self.header.next_ptr = @intCast(@intFromPtr(next));
    }

    fn getNext(self: *const Object) ?*Object {
        return @ptrFromInt(self.header.next_ptr);
    }

    fn removeNext(self: *Object) ?*Object {
        const next = self.getNext() orelse return null;
        self.setNext(next.getNext());
        return next;
    }

    fn trace(self: *Object, gc: *GC, tracer: Tracer) !void {
        switch (self.header.tag) {
            .fiber => try self.data.fiber.trace(gc, tracer),
            .list => try self.data.list.trace(gc, tracer),
            .map => try self.data.map.trace(gc, tracer),
        }
    }

    fn fieldNameFromType(comptime T: type) []const u8 {
        var field_name: ?[]const u8 = null;
        for (@typeInfo(Data).Union.fields) |field| {
            if (field.type == T) {
                field_name = field.name;
                break;
            }
        }
        return field_name.?;
    }
};
