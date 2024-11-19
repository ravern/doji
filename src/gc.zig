const std = @import("std");
const VM = @import("vm.zig").VM;

pub const GC = struct {
    child_allocator: std.mem.Allocator,
    roots: std.ArrayList(*VM),
    objects: std.SinglyLinkedList(Object),

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
            .roots = std.ArrayList(*VM).init(child_allocator),
        };
    }

    pub fn deinit(self: *GC) void {
        self.* = undefined;
    }

    pub fn addRoot(self: *GC, vm: *VM) !void {
        try self.roots.append(vm);
    }

    fn alloc(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *GC = @ptrCast(@alignCast(ctx));
        return self.child_allocator.rawAlloc(len, log2_ptr_align, ret_addr);
    }

    fn resize(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const self: *GC = @ptrCast(@alignCast(ctx));
        return self.child_allocator.rawResize(buf, log2_buf_align, new_len, ret_addr);
    }
};

pub const Object = struct {};
