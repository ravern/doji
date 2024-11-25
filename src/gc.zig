const std = @import("std");
const assert = std.debug.assert;
const value = @import("value.zig");
const Fiber = @import("vm.zig").Fiber;

pub const GC = struct {
    child_allocator: std.mem.Allocator,
    roots: ObjectList,
    objects: ObjectList,

    const ObjectList = std.SinglyLinkedList(Object);

    pub fn init(child_allocator: std.mem.Allocator) GC {
        return GC{
            .child_allocator = child_allocator,
            .roots = .{},
            .objects = .{},
        };
    }

    pub fn deinit(self: *GC) void {
        while (self.objects.popFirst()) |node| {
            node.data.deinit(self.child_allocator);
            self.child_allocator.destroy(node);
        }
        self.* = undefined;
    }

    pub fn create(self: *GC, comptime T: type) !*T {
        const node = try self.child_allocator.create(ObjectList.Node);
        node.* = .{ .data = Object.init(T) };

        self.objects.prepend(node);

        return node.data.getData(T);
    }

    pub fn root(self: *GC, data: anytype) void {
        const node = nodeFromObject(Object.fromData(data));
        self.roots.prepend(node);
    }

    pub fn mark(self: *GC, data: anytype) void {
        _ = self;

        const object = Object.fromData(data);
        _ = object;
    }

    fn nodeFromObject(object: *Object) *ObjectList.Node {
        return @fieldParentPtr("data", object);
    }
};

// TODO: Zig-ify all the comptime stuff, with Tag as the source of truth.
const Object = struct {
    header: Header,
    data: Data,

    const Header = packed struct {
        color: u2 = 0,
        tag: Tag,
    };

    const Tag = enum(u6) {
        list,
        fiber,
    };

    const Data = union {
        list: value.List,
        fiber: Fiber,
    };

    fn init(comptime T: type) Object {
        return Object{
            .header = .{ .tag = tagFromType(T) },
            .data = undefinedDataFromType(T),
        };
    }

    fn fromData(data: anytype) *Object {
        const T = unwrapPointer(@TypeOf(data));
        return @fieldParentPtr("data", @as(*Object.Data, @fieldParentPtr(@tagName(tagFromType(T)), data)));
    }

    fn deinit(self: *Object, allocator: std.mem.Allocator) void {
        switch (self.header.tag) {
            .list => self.data.list.deinit(allocator),
            .fiber => self.data.fiber.deinit(allocator),
        }
        self.* = undefined;
    }

    fn getData(self: *Object, comptime T: type) *T {
        assert(self.header.tag == tagFromType(T));
        return &@field(self.data, @tagName(tagFromType(T)));
    }

    fn undefinedDataFromType(comptime T: type) Data {
        return switch (T) {
            value.List => .{ .list = undefined },
            Fiber => .{ .fiber = undefined },
            else => @compileError("Invalid type for GC: *" ++ @typeName(T)),
        };
    }

    fn tagFromType(comptime T: type) Tag {
        switch (T) {
            value.List => return .list,
            Fiber => return .fiber,
            else => @compileError("Invalid type for GC: *" ++ @typeName(T)),
        }
    }
};

fn unwrapPointer(T: type) type {
    const info = @typeInfo(T);
    switch (info) {
        .Pointer => return info.Pointer.child,
        else => @compileError("Invalid type for GC: " ++ @typeName(T)),
    }
}
