const std = @import("std");

pub const GC = struct {
    child_allocator: std.mem.Allocator,
    objects: ObjectList,
    mutator: Mutator,

    pub const Mutator = struct {
        ptr: *anyopaque,
        // idea is to have all the specific mutator logic here, the VM is the mutator
        mark_roots: *const fn (ctx: *anyopaque, gc: *GC) void,
        finalize: *const fn (ctx: *anyopaque, gc: *GC) void,
    };

    const ObjectList = std.SinglyLinkedList(Object);

    pub fn allocator(self: *GC) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = std.mem.Allocator.noFree,
            },
        };
    }

    pub fn init(child_allocator: std.mem.Allocator) GC {
        return GC{
            .child_allocator = child_allocator,
            .objects = .{},
        };
    }

    pub fn deinit(self: *GC) void {
        self.roots.deinit();

        self.* = undefined;
    }

    pub fn setRoot(self: *GC, root: Root) void {
        self.root = root;
    }

    pub fn setFinalizer(self: *GC, finalizer: Finalizer) void {
        self.finalizer = finalizer;
    }

    pub fn printOnObject(comptime T: type, ptr: *T) void {
        const object = getObject(T, ptr);
        std.debug.print("is_gray: {}\n", .{object.is_gray});
        object.is_gray = !object.is_gray;
        std.debug.print("is_gray: {}\n", .{getObject(T, ptr).is_gray});
    }

    fn alloc(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *GC = @ptrCast(@alignCast(ctx));

        const ptr_align = @as(usize, 1) << @as(std.mem.Allocator.Log2Align, @intCast(log2_ptr_align));

        const node_len = std.mem.alignForward(usize, @sizeOf(ObjectList.Node), ptr_align);
        const full_len = node_len + len;

        const raw_ptr = self.child_allocator.rawAlloc(full_len, log2_ptr_align, ret_addr) orelse return null;

        const node = @as(*ObjectList.Node, @ptrCast(@alignCast(raw_ptr)));
        node.* = .{ .data = .{} };

        self.objects.prepend(node);

        return raw_ptr + node_len;
    }

    // TODO
    fn resize(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = log2_buf_align;
        _ = ret_addr;
        _ = new_len;
        unreachable;
    }

    fn getObject(comptime T: type, ptr: *T) *Object {
        const node_len = std.mem.alignForward(usize, @sizeOf(ObjectList.Node), @alignOf(T));
        const raw_ptr = @as([*]u8, @ptrCast(@alignCast(ptr)));
        const node = @as(*ObjectList.Node, @ptrCast(@alignCast(raw_ptr - node_len)));
        return &node.data;
    }
};

pub const Object = packed struct {
    is_gray: bool = false,
    is_black: bool = false,
    padding: u6 = 0,
};

test Object {
    try std.testing.expectEqual(1, @sizeOf(Object));
}
