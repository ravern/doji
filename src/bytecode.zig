const std = @import("std");
const Value = @import("Value.zig");
const ast = @import("ast.zig");

pub const Instruction = packed struct {
    const Self = @This();

    pub const Op = enum(u8) {
        nil,
        true,
        false,
        int,
        constant,

        local,
        store_local,

        add,
        sub,
        mul,
        div,
        mod,
        pos,
        neg,
        eq,
        neq,
        lt,
        le,
        gt,
        ge,
        log_and,
        log_or,
        log_not,
        bit_and,
        bit_or,
        bit_xor,
        bit_not,
        shl,
        shr,

        ret,

        pub fn fromUnaryOp(op: ast.UnaryExpression.Op) Self.Op {
            return switch (op) {
                .pos => .pos,
                .neg => .neg,
                .log_not => .log_not,
            };
        }

        pub fn fromBinaryOp(op: ast.BinaryExpression.Op) Self.Op {
            return switch (op) {
                .add => .add,
                .sub => .sub,
                .mul => .mul,
                .div => .div,
                .mod => .mod,
                .eq => .eq,
                .neq => .neq,
                .lt => .lt,
                .le => .le,
                .gt => .gt,
                .ge => .ge,
                .log_and => .log_and,
                .log_or => .log_or,
                .bit_and => .bit_and,
                .bit_or => .bit_or,
                .bit_xor => .bit_xor,
                .shl => .shl,
                .shr => .shr,
            };
        }
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
