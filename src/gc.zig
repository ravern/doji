const std = @import("std");

pub const GC = struct {
    child_allocator: std.mem.Allocator,
    mutator: Mutator,
    objects: ObjectList,
    gray_set: std.ArrayList(*ObjectNode),

    // these colors swap after each collection cycle, so that we don't have to traverse the entire object graph again
    // to change all the colors back from black to white.
    color_white: u2 = 0,
    color_black: u2 = 1,

    const color_gray = 2;

    const ObjectList = std.SinglyLinkedList(Object);
    const ObjectNode = ObjectList.Node;

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

    pub fn init(child_allocator: std.mem.Allocator, mutator: Mutator) GC {
        return GC{
            .child_allocator = child_allocator,
            .mutator = mutator,
            .objects = .{},
            .gray_set = std.ArrayList(*ObjectNode).init(child_allocator),
        };
    }

    pub fn deinit(self: *GC) void {
        var curr_node = self.objects.first;
        while (curr_node) |node| : (curr_node = node.next) {
            self.mutator.vtable.finalize_object(self.mutator.ptr, getPtr(node));
        }
        while (self.objects.popFirst()) |node| {
            self.destroyObjectNode(node, @returnAddress());
        }
        self.gray_set.deinit();
        self.* = undefined;
    }

    pub fn mark(self: *GC, ptr: anytype) !void {
        const node = getObjectNode(ptr);
        if (node.data.color == self.color_black) return;
        node.data.color = color_gray;
        try self.gray_set.append(node);
    }

    pub fn collect(self: *GC) !void {
        try self.mutator.vtable.mark_roots(self.mutator.ptr, self);

        while (self.gray_set.popOrNull()) |node| {
            try self.blacken(node); // might push more nodes into gray_set

        }

        self.sweep();

        self.swapColors();
    }

    fn blacken(self: *GC, node: *ObjectNode) !void {
        var tracer = Tracer{ .action = .mark };
        const ptr = getPtr(node);
        try self.mutator.vtable.trace_object(self.mutator.ptr, ptr, self, &tracer);
        node.data.color = self.color_black;
    }

    fn sweep(self: *GC) void {
        var white_set = ObjectList{};

        // except the first node, remove all the white nodes and add them to the white set
        var curr_node = self.objects.first;
        while (curr_node) |node| {
            if (node.next) |next_node| {
                if (next_node.data.color == self.color_white) {
                    const removed_node = node.removeNext().?;
                    white_set.prepend(removed_node);
                    continue;
                }
            }
            curr_node = node.next;
        }

        // now remove the first node if necessary
        if (self.objects.first) |first_node| {
            if (first_node.data.color == self.color_white) {
                _ = self.objects.popFirst();
                white_set.prepend(first_node);
            }
        }

        // now we finalize and destroy all the white nodes
        curr_node = white_set.first;
        while (curr_node) |node| : (curr_node = node.next) {
            self.mutator.vtable.finalize_object(self.mutator.ptr, getPtr(node));
        }
        while (white_set.popFirst()) |node| {
            self.destroyObjectNode(node, @returnAddress());
        }
    }

    fn swapColors(self: *GC) void {
        const tmp = self.color_white;
        self.color_white = self.color_black;
        self.color_black = tmp;
    }

    fn alloc(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const self: *GC = @ptrCast(@alignCast(ctx));

        const node = self.createObjectNode(len, log2_ptr_align, ret_addr) orelse return null;
        self.objects.prepend(node);

        return @ptrCast(getPtr(node));
    }

    fn resize(ctx: *anyopaque, buf: []u8, log2_buf_align: u8, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = log2_buf_align;
        _ = ret_addr;
        _ = new_len;
        unreachable;
    }

    fn createObjectNode(self: *GC, len: usize, log2_ptr_align: u8, ret_addr: usize) ?*ObjectNode {
        const info = calculatePtrInfo(log2_ptr_align);
        const full_len = info.node_len + len;
        const raw_ptr = self.child_allocator.rawAlloc(full_len, info.log2_ptr_align, ret_addr) orelse return null;
        const node = @as(*ObjectNode, @ptrCast(@alignCast(raw_ptr)));
        node.* = .{
            .data = .{
                .color = self.color_white,
                .log2_ptr_align = @intCast(log2_ptr_align),
            },
        };
        return node;
    }

    fn destroyObjectNode(self: *GC, node: *ObjectNode, ret_addr: usize) void {
        const info = calculatePtrInfo(node.data.log2_ptr_align);
        const raw_ptr = @as([*]u8, @ptrCast(node));
        const ptr = @as(*anyopaque, @ptrCast(raw_ptr + info.node_len));
        const full_len = info.node_len + self.mutator.vtable.size_of_object(self.mutator.ptr, ptr);
        self.child_allocator.rawFree(raw_ptr[0..full_len], info.log2_ptr_align, ret_addr);
    }

    inline fn getObjectNode(ptr: anytype) *ObjectNode {
        const log2_ptr_align = std.math.log2_int(usize, @alignOf(@TypeOf(ptr)));
        const info = calculatePtrInfo(log2_ptr_align);
        const raw_ptr = @as([*]u8, @ptrCast(ptr));
        return @as(*ObjectNode, @ptrCast(@alignCast(raw_ptr - info.node_len)));
    }

    inline fn getPtr(node: *ObjectNode) *anyopaque {
        const info = calculatePtrInfo(node.data.log2_ptr_align);
        const raw_ptr = @as([*]u8, @ptrCast(node));
        return @ptrCast(raw_ptr + info.node_len);
    }

    // From the given [log2_ptr_align], and taking into account the alignment of the [ObjectNode], calculate all
    // the relevant pointer info.
    inline fn calculatePtrInfo(log2_ptr_align: u8) struct {
        log2_ptr_align: u8,
        ptr_align: usize,
        node_len: usize,
    } {
        const ptr_align = @as(usize, 1) << @as(std.mem.Allocator.Log2Align, @intCast(log2_ptr_align));
        const actual_ptr_align = @max(@alignOf(ObjectNode), ptr_align);
        const actual_log2_ptr_align = std.math.log2_int(usize, actual_ptr_align);
        const node_len = std.mem.alignForward(usize, @sizeOf(ObjectNode), actual_ptr_align);
        return .{ .ptr_align = actual_ptr_align, .log2_ptr_align = actual_log2_ptr_align, .node_len = node_len };
    }
};

pub const Mutator = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        mark_roots: *const fn (ctx: *anyopaque, gc: *GC) std.mem.Allocator.Error!void,
        size_of_object: *const fn (ctx: *anyopaque, ptr: *anyopaque) usize,
        trace_object: *const fn (ctx: *anyopaque, ptr: *anyopaque, gc: *GC, tracer: *Tracer) std.mem.Allocator.Error!void,
        finalize_object: *const fn (ctx: *anyopaque, ptr: *anyopaque) void,
    };
};

pub const Tracer = struct {
    action: Action,

    const Action = enum {
        mark,
    };

    pub fn trace(self: *Tracer, gc: *GC, ptr: anytype) !void {
        switch (self.action) {
            .mark => try gc.mark(ptr),
        }
    }
};

const Object = packed struct {
    color: u2,
    log2_ptr_align: u6,
};

test GC {
    const TestResult = struct {
        freed_objects: std.StringHashMap(void),

        const Self = @This();

        fn init(allocator: std.mem.Allocator) Self {
            return Self{ .freed_objects = std.StringHashMap(void).init(allocator) };
        }

        fn deinit(self: *Self) void {
            self.freed_objects.deinit();
        }

        fn isEmpty(self: *Self) bool {
            return self.freed_objects.count() == 0;
        }

        fn hasFreedObject(self: *Self, key: []const u8) bool {
            return self.freed_objects.contains(key);
        }

        fn putFreedObject(self: *Self, key: []const u8) void {
            self.freed_objects.put(key, {}) catch unreachable;
        }
    };

    const TestObject = struct {
        result: *TestResult,
        key: []const u8,
        refs: std.StringHashMap(*Self),

        const Self = @This();

        fn init(allocator: std.mem.Allocator, key: []const u8, result: *TestResult) Self {
            return Self{ .result = result, .key = key, .refs = std.StringHashMap(*Self).init(allocator) };
        }

        fn deinit(self: *Self) void {
            self.result.putFreedObject(self.key);
            self.refs.deinit();
        }

        fn addRef(self: *Self, child_object: *Self) !void {
            try self.refs.put(child_object.key, child_object);
        }

        fn removeRef(self: *Self, child_object: *Self) void {
            _ = self.refs.remove(child_object.key);
        }
    };

    const TestMutator = struct {
        allocator: std.mem.Allocator,
        gc: GC,
        gc_allocator: std.mem.Allocator,
        root_object: *TestObject,

        const Self = @This();

        fn mutator(self: *Self) Mutator {
            return .{
                .ptr = self,
                .vtable = &.{
                    .mark_roots = markRoots,
                    .size_of_object = sizeOfObject,
                    .trace_object = traceObject,
                    .finalize_object = finalizeObject,
                },
            };
        }

        fn init(allocator: std.mem.Allocator, result: *TestResult) !*Self {
            var self = try allocator.create(Self);
            self.* = .{ .allocator = allocator, .gc = undefined, .gc_allocator = allocator, .root_object = undefined };

            self.gc = GC.init(allocator, self.mutator());

            self.gc_allocator = self.gc.allocator();

            self.root_object = try self.gc_allocator.create(TestObject);
            self.root_object.* = TestObject.init(self.allocator, "__root__", result);

            return self;
        }

        fn deinit(self: *Self) void {
            self.gc.deinit();
            self.allocator.destroy(self);
        }

        fn markRoots(ctx: *anyopaque, gc: *GC) !void {
            const self = @as(*Self, @ptrCast(@alignCast(ctx)));

            try gc.mark(self.root_object);
        }

        fn sizeOfObject(ctx: *anyopaque, ptr: *anyopaque) usize {
            _ = ctx;
            _ = ptr;

            return @sizeOf(TestObject);
        }

        fn traceObject(ctx: *anyopaque, ptr: *anyopaque, gc: *GC, tracer: *Tracer) !void {
            _ = ctx;

            const object = @as(*TestObject, @ptrCast(@alignCast(ptr)));
            var it = object.refs.valueIterator();
            while (it.next()) |child_object| {
                try tracer.trace(gc, child_object.*);
            }
        }

        fn finalizeObject(ctx: *anyopaque, ptr: *anyopaque) void {
            _ = ctx;

            const object = @as(*TestObject, @ptrCast(@alignCast(ptr)));
            object.deinit();
        }
    };

    var result = TestResult.init(std.testing.allocator);
    defer result.deinit();

    var mutator = try TestMutator.init(std.testing.allocator, &result);
    defer mutator.deinit();

    // basic example

    const basic_1_object = try mutator.gc_allocator.create(TestObject);
    basic_1_object.* = TestObject.init(mutator.allocator, "basic_1", &result);
    const basic_2_object = try mutator.gc_allocator.create(TestObject);
    basic_2_object.* = TestObject.init(mutator.allocator, "basic_2", &result);

    try mutator.root_object.addRef(basic_1_object);
    try mutator.root_object.addRef(basic_2_object);
    try mutator.gc.collect();
    try std.testing.expect(!result.hasFreedObject("basic_1"));
    try std.testing.expect(!result.hasFreedObject("basic_2"));

    mutator.root_object.removeRef(basic_1_object);
    try mutator.gc.collect();
    try std.testing.expect(result.hasFreedObject("basic_1"));
    try std.testing.expect(!result.hasFreedObject("basic_2"));

    mutator.root_object.removeRef(basic_2_object);
    try mutator.gc.collect();
    try std.testing.expect(result.hasFreedObject("basic_1"));
    try std.testing.expect(result.hasFreedObject("basic_2"));

    // multiple layers

    const layers_1_object = try mutator.gc_allocator.create(TestObject);
    layers_1_object.* = TestObject.init(mutator.allocator, "layers_1", &result);
    const layers_2_object = try mutator.gc_allocator.create(TestObject);
    layers_2_object.* = TestObject.init(mutator.allocator, "layers_2", &result);
    const layers_3_object = try mutator.gc_allocator.create(TestObject);
    layers_3_object.* = TestObject.init(mutator.allocator, "layers_3", &result);
    const layers_4_object = try mutator.gc_allocator.create(TestObject);
    layers_4_object.* = TestObject.init(mutator.allocator, "layers_4", &result);
    const layers_5_object = try mutator.gc_allocator.create(TestObject);
    layers_5_object.* = TestObject.init(mutator.allocator, "layers_5", &result);

    try mutator.root_object.addRef(layers_1_object);
    try mutator.root_object.addRef(layers_2_object);
    try layers_2_object.addRef(layers_3_object);
    try layers_2_object.addRef(layers_4_object);
    try layers_3_object.addRef(layers_5_object);
    try mutator.gc.collect();
    try std.testing.expect(!result.hasFreedObject("layers_1"));
    try std.testing.expect(!result.hasFreedObject("layers_2"));
    try std.testing.expect(!result.hasFreedObject("layers_3"));
    try std.testing.expect(!result.hasFreedObject("layers_4"));
    try std.testing.expect(!result.hasFreedObject("layers_5"));

    mutator.root_object.removeRef(layers_1_object);
    try mutator.gc.collect();
    try std.testing.expect(result.hasFreedObject("layers_1"));
    try std.testing.expect(!result.hasFreedObject("layers_2"));
    try std.testing.expect(!result.hasFreedObject("layers_3"));
    try std.testing.expect(!result.hasFreedObject("layers_4"));
    try std.testing.expect(!result.hasFreedObject("layers_5"));

    mutator.root_object.removeRef(layers_2_object);
    try mutator.gc.collect();
    try std.testing.expect(result.hasFreedObject("layers_1"));
    try std.testing.expect(result.hasFreedObject("layers_2"));
    try std.testing.expect(result.hasFreedObject("layers_3"));
    try std.testing.expect(result.hasFreedObject("layers_4"));
    try std.testing.expect(result.hasFreedObject("layers_5"));

    // circular references

    const circular_1_object = try mutator.gc_allocator.create(TestObject);
    circular_1_object.* = TestObject.init(mutator.allocator, "circular_1", &result);
    const circular_2_object = try mutator.gc_allocator.create(TestObject);
    circular_2_object.* = TestObject.init(mutator.allocator, "circular_2", &result);

    try mutator.root_object.addRef(circular_1_object);
    try circular_1_object.addRef(circular_2_object);
    try circular_2_object.addRef(circular_1_object);
    try mutator.gc.collect();
    try std.testing.expect(!result.hasFreedObject("circular_1"));
    try std.testing.expect(!result.hasFreedObject("circular_2"));

    mutator.root_object.removeRef(circular_1_object);
    try mutator.gc.collect();
    try std.testing.expect(result.hasFreedObject("circular_1"));
    try std.testing.expect(result.hasFreedObject("circular_2"));

    // pointing to root

    const point_root_object = try mutator.gc_allocator.create(TestObject);
    point_root_object.* = TestObject.init(mutator.allocator, "point_root", &result);

    try point_root_object.addRef(mutator.root_object);
    try mutator.gc.collect();
    try std.testing.expect(result.hasFreedObject("point_root"));
}
