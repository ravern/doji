const std = @import("std");

pub const GC = struct {
    child_allocator: std.mem.Allocator,
    mutator: Mutator,
    objects: ObjectList,

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

    fn markTracer(self: *GC) Tracer {
        return .{
            .ptr = self,
            .vtable = &.{
                .trace = markAndTrace,
            },
        };
    }

    fn finalizeTracer(self: *GC) Tracer {
        return .{
            .ptr = self,
            .vtable = &.{
                .trace = traceAndFinalize,
            },
        };
    }

    pub fn init(child_allocator: std.mem.Allocator, mutator: Mutator) GC {
        return GC{
            .child_allocator = child_allocator,
            .mutator = mutator,
            .objects = .{},
        };
    }

    pub fn deinit(self: *GC) void {
        while (self.objects.popFirst()) |node| {
            self.destroyObjectNode(node);
        }
        self.* = undefined;
    }

    fn alloc(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *GC = @ptrCast(@alignCast(ctx));

        const node = self.createObjectNode(len, log2_ptr_align, ret_addr) orelse return null;
        self.objects.prepend(node);

        return @ptrCast(@alignCast(self.getPtr(node)));
    }

    fn resize(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = log2_buf_align;
        _ = ret_addr;
        _ = new_len;
        unreachable;
    }

    fn markAndTrace(ctx: *anyopaque, gc: *GC) void {
        _ = ctx;
        _ = gc;
        unreachable;
    }

    fn traceAndFinalize(ctx: *anyopaque, gc: *GC) void {
        _ = ctx;
        _ = gc;
        unreachable;
    }

    fn createObjectNode(self: *GC, len: usize, log2_ptr_align: u8, ret_addr: usize) ?*ObjectList.Node {
        const ptr_align = @as(usize, 1) << @as(std.mem.Allocator.Log2Align, @intCast(log2_ptr_align));
        const node_len = std.mem.alignForward(usize, @sizeOf(ObjectList.Node), ptr_align);
        const full_len = node_len + len;
        const raw_ptr = self.child_allocator.rawAlloc(full_len, log2_ptr_align, ret_addr) orelse return null;
        const node = @as(*ObjectList.Node, @ptrCast(@alignCast(raw_ptr)));
        node.* = .{ .data = .{ .log2_ptr_align = @intCast(log2_ptr_align), .len = len } };
        return node;
    }

    fn destroyObjectNode(self: *GC, node: *ObjectList.Node) void {
        const ptr_align = calculatePtrAlign(node.data.log2_ptr_align);
        const node_len = calculateNodeLen(ptr_align);
        const full_len = node_len + node.data.len;
        const raw_ptr = @as([*]u8, @ptrCast(@alignCast(node)));
        const buf = raw_ptr[0..full_len];
        self.mutator.vtable.finalize(self.mutator.ptr, self, @ptrCast(@alignCast(raw_ptr + node_len)));
        self.child_allocator.rawFree(buf, node.data.log2_ptr_align, @returnAddress()); // FIXME: is @returnAddress() correct here?
    }

    fn getObjectNode(self: *GC, comptime T: type, ptr: *T) *ObjectList.Node {
        _ = self;

        const ptr_align = @alignOf(T);
        const node_len = calculateNodeLen(ptr_align);
        const raw_ptr = @as([*]u8, @ptrCast(@alignCast(ptr)));
        return @ptrCast(@alignCast(raw_ptr - node_len));
    }

    fn getPtr(self: *GC, node: *ObjectList.Node) *anyopaque {
        _ = self;

        const ptr_align = calculatePtrAlign(node.data.log2_ptr_align);
        const node_len = calculateNodeLen(ptr_align);
        const raw_ptr = @as([*]u8, @ptrCast(@alignCast(node)));
        return @ptrCast(@alignCast(raw_ptr + node_len));
    }

    inline fn calculatePtrAlign(log2_ptr_align: u8) usize {
        return @as(usize, 1) << @as(std.mem.Allocator.Log2Align, @intCast(log2_ptr_align));
    }

    inline fn calculateNodeLen(ptr_align: usize) usize {
        return std.mem.alignForward(usize, @sizeOf(ObjectList.Node), ptr_align);
    }
};

pub const Mutator = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        trace: *const fn (ctx: *anyopaque, gc: *GC, tracer: *Tracer, ptr: *anyopaque) void,
        finalize: *const fn (ctx: *anyopaque, gc: *GC, ptr: *anyopaque) void,
    };
};

pub const Tracer = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        trace: *const fn (ctx: *anyopaque, gc: *GC, ptr: *anyopaque) void,
    };
};

pub const Object = packed struct {
    color: u2 = 0,
    log2_ptr_align: u6,
    len: usize,
};

test Object {
    try std.testing.expectEqual(1, @sizeOf(Object));
}
