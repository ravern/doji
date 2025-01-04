const std = @import("std");
const Object = @import("gc/object.zig").Object(object_types, FinalizeContext);
const Color = @import("gc/object.zig").Color;

const object_types = .{
    u32,
    u64,
};

pub const FinalizeContext = struct {
    allocator: std.mem.Allocator,
};

const ObjectHeader = struct {};

const ObjectList = struct {
    first: ?*Object = null,

    pub fn prepend(self: *ObjectList, object: *Object) void {
        object.setNext(self.first);
        self.first = object;
    }

    pub fn pop(self: *ObjectList) ?*Object {
        const object = self.first orelse return null;
        self.first = object.getNext();
        return object;
    }
};

pub const GC = struct {
    all_objects: ObjectList = .{},
    gray_set: std.ArrayListUnmanaged(*Object) = .{},
    root_set: std.ArrayListUnmanaged(*Object) = .{},
    child_allocator: std.mem.Allocator,
    finalize_ctx: FinalizeContext,

    pub fn init(allocator: std.mem.Allocator, finalize_ctx: FinalizeContext) !GC {
        return GC{
            .all_objects = ObjectList{},
            .gray_set = std.ArrayListUnmanaged(*Object){},
            .root_set = std.ArrayListUnmanaged(*Object){},
            .child_allocator = allocator,
            .finalize_ctx = finalize_ctx,
        };
    }
};

pub const Tracer = struct {
    gc: *GC,
};
