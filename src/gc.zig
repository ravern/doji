const std = @import("std");
const VM = @import("vm.zig").VM;
const Fiber = @import("vm.zig").Fiber;
const value = @import("value.zig");

pub const GC = struct {
    allocator: std.mem.Allocator,
    vm: *VM,
    colors: Colors = .{},
    objects: ObjectList = .{},
    gray_set: std.ArrayListUnmanaged(*Object) = .{},

    const Colors = struct {
        white: u8 = 0,
        black: u8 = 1,
        gray: u8 = 2,

        fn swapWhiteBlack(self: *Colors) void {
            const tmp = self.white;
            self.white = self.black;
            self.black = tmp;
        }
    };

    pub fn cast(comptime T: type, ptr: *anyopaque) ?*T {
        return Object.fromPtr(ptr).cast(T);
    }

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
        self.colors.swapWhiteBlack();
    }

    fn blacken(self: *GC, object: *Object) !void {
        if (object.header.color == self.colors.black) return;
        try object.mark(self);
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
        return .{
            .header = .{
                .color = color,
                .tag = switch (T) {
                    Fiber => .fiber,
                    value.List => .list,
                    value.Map => .map,
                    else => throwInvalidGCTypeError(T),
                },
            },
            .data = switch (T) {
                Fiber => .{ .fiber = undefined },
                value.List => .{ .list = undefined },
                value.Map => .{ .map = undefined },
                else => throwInvalidGCTypeError(T),
            },
        };
    }

    fn cast(self: *Object, comptime T: type) ?*T {
        return switch (T) {
            Fiber => if (self.header.tag == .fiber) &self.data.fiber else null,
            value.List => if (self.header.tag == .list) &self.data.list else null,
            value.Map => if (self.header.tag == .map) &self.data.map else null,
            else => throwInvalidGCTypeError(T),
        };
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

    fn mark(self: *Object, gc: *GC) !void {
        switch (self.header.tag) {
            .fiber => try self.data.fiber.mark(gc),
            .list => try self.data.list.mark(gc),
            .map => try self.data.map.mark(gc),
        }
    }
};

fn throwInvalidGCTypeError(comptime T: type) void {
    @compileError(T.name ++ " is not a valid GC object");
}
