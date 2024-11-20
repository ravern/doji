const std = @import("std");
const assert = std.debug.assert;
const value = @import("value.zig");
const Fiber = @import("vm.zig").Fiber;
const VM = @import("vm.zig").VM;

pub const GC = struct {
    allocator: std.mem.Allocator,
    vm: *VM,
    objects: ObjectList = .{},

    const ObjectList = std.SinglyLinkedList(Object);

    pub fn init(allocator: std.mem.Allocator, vm: *VM) GC {
        return GC{
            .allocator = allocator,
            .vm = vm,
        };
    }

    pub fn deinit(self: *GC) void {
        while (self.objects.popFirst()) |node| {
            node.data.deinit(self.allocator);
            self.allocator.destroy(node);
        }
        self.* = undefined;
    }

    pub fn create(self: *GC, comptime T: type) !*T {
        const node = try self.allocator.create(ObjectList.Node);
        node.data = Object.init(T);
        self.objects.prepend(node);
        return node.data.cast(T);
    }
};

const Object = struct {
    header: Header,
    data: Data,

    const Header = packed struct {
        is_gray: bool = false,
        is_black: bool = false,
    };

    const Data = union(enum) {
        list: value.List,
        fiber: Fiber,
    };

    fn init(comptime T: type) Object {
        return Object{
            .header = .{},
            .data = comptime undefinedDataFromType(T),
        };
    }

    fn deinit(self: *Object, allocator: std.mem.Allocator) void {
        switch (self.data) {
            .list => self.data.list.deinit(allocator),
            .fiber => self.data.fiber.deinit(allocator),
        }
    }

    fn cast(self: *Object, comptime T: type) !*T {
        return &@field(self.data, dataFieldNameFromType(T));
    }

    fn dataFieldNameFromType(comptime T: type) []const u8 {
        ensureValidObjectType(T);
        return switch (T) {
            value.List => "list",
            Fiber => "fiber",
            else => unreachable,
        };
    }

    fn undefinedDataFromType(comptime T: type) Data {
        ensureValidObjectType(T);
        return switch (T) {
            value.List => .{ .list = undefined },
            Fiber => .{ .fiber = undefined },
            else => unreachable,
        };
    }

    fn ensureValidObjectType(comptime T: type) void {
        comptime for (@typeInfo(Data).Union.fields) |field| {
            if (field.type == T) return;
        };
        @compileError("invalid gc.Object type: " ++ @typeName(T));
    }
};
