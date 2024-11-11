const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const StringHashMapUnmanaged = std.StringHashMapUnmanaged;

const Chunk = @import("./vm/bytecode.zig").Chunk;
const Error = @import("./errors.zig").Error;
const value = @import("./vm/value.zig");
const Value = value.Value;
const ValueHashMapUnmanaged = value.ValueHashMapUnmanaged;

pub const Environment = struct {
    identifiers: StringPool,
    constants: ConstantPool,

    module_registry: ModuleRegistry,

    err: ?Error,

    pub fn init(allocator: Allocator) Environment {
        return Environment{
            .identifiers = StringPool.init(allocator),
            .constants = ConstantPool.init(allocator),
            .module_registry = ModuleRegistry.init(),
            .err = null,
        };
    }

    pub fn deinit(self: *Environment, allocator: Allocator) void {
        self.identifiers.deinit();
        self.constants.deinit();
        if (self.err) |err| {
            err.deinit(allocator);
        }
    }

    pub fn reportError(self: *Environment, err: Error) void {
        self.err = err;
    }
};

pub const StringPool = struct {
    allocator: Allocator,
    strings: StringHashMapUnmanaged([]const u8) = .{},

    fn init(allocator: Allocator) StringPool {
        return StringPool{ .allocator = allocator };
    }

    fn deinit(self: *StringPool) void {
        var strings_iter = self.strings.keyIterator();
        while (strings_iter.next()) |string| {
            self.allocator.free(string.*);
        }
        self.strings.deinit(self.allocator);
    }

    pub fn intern(self: *StringPool, string: []const u8) ![]const u8 {
        if (self.strings.get(string)) |intern_string| {
            return intern_string;
        } else {
            const intern_string = try self.allocator.dupe(u8, string);
            try self.strings.put(self.allocator, intern_string, intern_string);
            return intern_string;
        }
    }
};

pub const ConstantPool = struct {
    allocator: Allocator,
    constant_indices: ValueHashMapUnmanaged(usize) = .{},
    constants: ArrayListUnmanaged(Value) = .{},

    fn init(allocator: Allocator) ConstantPool {
        return ConstantPool{ .allocator = allocator };
    }

    fn deinit(self: *ConstantPool) void {
        self.constant_indices.deinit(self.allocator);
        self.constants.deinit(self.allocator);
    }

    pub fn add(self: *ConstantPool, val: Value) !usize {
        const index = self.constants.items.len;
        try self.constants.append(self.allocator, val);
        try self.constant_indices.put(self.allocator, val, index);
        return index;
    }

    pub fn get(self: *ConstantPool, index: usize) Value {
        return self.constants.items[index];
    }
};

const ModuleRegistry = struct {
    pub fn init() ModuleRegistry {
        return ModuleRegistry{};
    }
};

const Module = union(enum) {
    Compiled: Chunk,
    Evaluted: Value,
};

test "StringPool" {
    const allocator = testing.allocator;
    var pool = StringPool.init(allocator);
    defer pool.deinit();
    const hello = "hello";
    const other_hello = try allocator.dupe(u8, hello);
    defer allocator.free(other_hello);
    const intern_hello = try pool.intern(hello);
    const intern_other_hello = try pool.intern(other_hello);
    try testing.expect(hello != other_hello.ptr);
    try testing.expectEqual(intern_hello.ptr, intern_other_hello.ptr);
}
