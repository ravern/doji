const std = @import("std");
const Value = @import("Value.zig");

pub const Instruction = packed struct {
    const Self = @This();

    pub const Op = enum(u8) {
        int,
        constant,
    };
    pub const Arg = u24;

    op: Op,
    arg: Arg,
};

pub const Chunk = struct {
    const Self = @This();

    code: std.ArrayListUnmanaged(Instruction) = .{},
    constants: std.ArrayListUnmanaged(Value) = .{},

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.code.deinit(allocator);
        self.constants.deinit(allocator);
    }

    pub fn appendInst(self: *Self, allocator: std.mem.Allocator, op: Instruction.Op) !usize {
        const offset = self.code.items.len;
        try self.code.append(allocator, .{ .op = op, .arg = 0 });
        return offset;
    }

    pub fn appendInstArg(self: *Self, allocator: std.mem.Allocator, op: Instruction.Op, arg: Instruction.Arg) !usize {
        const offset = self.code.items.len;
        try self.code.append(allocator, .{ .op = op, .arg = arg });
        return offset;
    }

    pub fn appendConstant(self: *Self, allocator: std.mem.Allocator, value: Value) !usize {
        const index = self.constants.items.len;
        try self.constants.append(allocator, value);
        return index;
    }
};
