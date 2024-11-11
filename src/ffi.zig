const std = @import("std");
const Allocator = std.mem.Allocator;

const DojiError = @import("./errors.zig").DojiError;
const fiber = @import("./fiber.zig");
const Fiber = fiber.Fiber;
const Stack = fiber.Stack;
const Value = @import("./vm/value.zig").Value;

pub const ExecContext = struct {
    allocator: Allocator,
    fiber: *Fiber,
    stack: *Stack,

    pub fn load(self: *ExecContext, slot: usize) !void {
        _ = self;
        _ = slot;
        return Value{};
    }

    pub fn store(self: *ExecContext, slot: usize, val: Value) !void {
        _ = self;
        _ = slot;
        _ = val;
        return Value{};
    }
};

pub const ForeignFunction = struct {
    arity: u8,
    steps: []const ForeignFunctionStep,
};

pub const ForeignFunctionStep = fn (*ExecContext, Value) ForeignFunctionResult;

pub const ForeignFunctionResult = union(enum) {
    Yield: Value,
    Call: struct {},
    Ret: struct {},
};
