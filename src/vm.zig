const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const Instruction = @import("chunk.zig").Instruction;
const Constant = @import("chunk.zig").Constant;
const GC = @import("gc.zig").GC;
const Input = @import("input.zig").Input;
const Value = @import("value.zig").Value;
const List = @import("value.zig").List;

const demo_chunk = Chunk{
    .code = &[_]Instruction{
        .{ .op = .int, .arg = 2 },
        .{ .op = .int, .arg = 3 },
        .{ .op = .add, .arg = 0 },
        .{ .op = .ret, .arg = 0 },
    },
    .constants = &[_]Constant{},
};

const stack_init_size = 1024;

pub const VM = struct {
    allocator: std.mem.Allocator,
    gc: GC,
    root_fiber: *Fiber,
    curr_fiber: *Fiber,

    pub fn init(allocator: std.mem.Allocator) !*VM {
        var self = try allocator.create(VM);
        self.* = .{
            .allocator = allocator,
            .gc = GC.init(allocator, self),
            .root_fiber = undefined,
            .curr_fiber = undefined,
        };

        self.root_fiber = try self.gc.create(Fiber);
        self.root_fiber.* = try Fiber.init(allocator);

        self.curr_fiber = self.root_fiber;

        return self;
    }

    pub fn deinit(self: *VM) void {
        self.gc.deinit();
        self.allocator.destroy(self);
    }

    pub fn evaluate(self: *VM, input: *const Input) !Value {
        // TODO: compile the chunk
        _ = input;
        const chunk = demo_chunk;

        try self.curr_fiber.pushFrame(self.allocator, 0, &chunk);

        var result: Value = undefined;
        while (true) {
            const instruction = try self.curr_fiber.advance();
            switch (instruction.op) {
                .int => try self.curr_fiber.push(self.allocator, Value.init(@as(i48, @intCast(instruction.arg)))),
                .add => {
                    const right = (try self.curr_fiber.pop()).cast(i48).?;
                    const left = (try self.curr_fiber.pop()).cast(i48).?;
                    try self.curr_fiber.push(self.allocator, Value.init(left + right));
                },
                .ret => {
                    result = try self.curr_fiber.pop();
                    break;
                },
                else => unreachable,
            }

            try self.gc.collect();
        }

        try self.curr_fiber.popFrame();
        return result;
    }

    pub fn markRoots(self: *VM) !void {
        try self.gc.mark(self.curr_fiber);
    }
};

pub const Fiber = struct {
    stack: std.ArrayListUnmanaged(Value),
    frames: std.ArrayListUnmanaged(CallFrame),

    pub const CallFrame = struct {
        chunk: *const Chunk,
        bp: [*]Value,
        sp: [*]Value,
        ip: [*]const Instruction,
    };

    pub const Error = error{
        StackUnderflow,
        EmptyFrameStack,
        FrameStackUnderflow,
    };

    pub fn init(allocator: std.mem.Allocator) !Fiber {
        return Fiber{
            .stack = try std.ArrayListUnmanaged(Value).initCapacity(allocator, stack_init_size),
            .frames = .{},
        };
    }

    pub fn deinit(self: *Fiber, allocator: std.mem.Allocator) void {
        self.stack.deinit(allocator);
        self.frames.deinit(allocator);
        self.* = undefined;
    }

    pub fn mark(self: *Fiber, gc: *GC) !void {
        _ = self;
        _ = gc;
    }

    pub fn pushFrame(self: *Fiber, allocator: std.mem.Allocator, arity: u8, chunk: *const Chunk) !void {
        if (self.stack.items.len < arity) return error.StackUnderflow;
        const bp = if (self.stack.items.len == 0) undefined else if (self.getCurrentFrameOrNull()) |frame| frame.sp + 1 - arity else self.stack.items.ptr;
        const sp = if (self.stack.items.len == 0) undefined else if (arity == 0) bp else bp + arity - 1;
        try self.frames.append(allocator, .{
            .chunk = chunk,
            .bp = bp,
            .sp = sp,
            .ip = chunk.code.ptr,
        });
    }

    pub fn popFrame(self: *Fiber) !void {
        _ = self.frames.popOrNull() orelse return error.FrameStackUnderflow;
    }

    pub fn push(self: *Fiber, allocator: std.mem.Allocator, value: Value) !void {
        var frame = try self.getCurrentFrame();

        const stack_ptr = self.stack.items.ptr;

        try self.stack.append(allocator, value);
        if (self.stack.items.len == 1) {
            frame.bp = self.stack.items.ptr;
            frame.sp = self.stack.items.ptr;
        } else {
            frame.sp += 1;
        }

        // check if stack items have been moved (due to realloc), if so, move bp and sp accordingly
        if (stack_ptr != self.stack.items.ptr) {
            const bp_offset = @intFromPtr(frame.bp) - @intFromPtr(stack_ptr);
            const sp_offset = @intFromPtr(frame.sp) - @intFromPtr(stack_ptr);
            frame.bp = @ptrFromInt(@intFromPtr(self.stack.items.ptr) + bp_offset);
            frame.sp = @ptrFromInt(@intFromPtr(self.stack.items.ptr) + sp_offset);
        }
    }

    pub fn pop(self: *Fiber) !Value {
        var frame = try self.getCurrentFrame();
        if (self.stack.items.len == 0) return error.StackUnderflow;
        if (self.stack.items.len == 1 or frame.sp == frame.bp) {
            frame.bp = undefined;
            frame.sp = undefined;
        } else {
            frame.sp -= 1;
        }
        return self.stack.pop();
    }

    pub fn advance(self: *Fiber) !Instruction {
        var frame = try self.getCurrentFrame();
        const instruction = frame.ip[0];
        frame.ip += 1;
        return instruction;
    }

    inline fn getCurrentFrame(self: *Fiber) !*CallFrame {
        return self.getCurrentFrameOrNull() orelse error.EmptyFrameStack;
    }

    inline fn getCurrentFrameOrNull(self: *Fiber) ?*CallFrame {
        if (self.frames.items.len == 0) return null;
        return &self.frames.items[self.frames.items.len - 1];
    }
};
