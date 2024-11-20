const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const Instruction = @import("chunk.zig").Instruction;
const Constant = @import("chunk.zig").Constant;
const GC = @import("gc.zig").GC;
const Input = @import("input.zig").Input;
const Value = @import("value.zig").Value;

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
    current_fiber: *Fiber,

    pub fn init(allocator: std.mem.Allocator) !VM {
        var self = VM{
            .allocator = allocator,
            .gc = undefined,
            .root_fiber = undefined,
            .current_fiber = undefined,
        };

        self.gc = GC.init(allocator, &self);

        self.root_fiber = try self.gc.create(Fiber);
        self.root_fiber.* = try Fiber.init(allocator);

        self.current_fiber = self.root_fiber;

        return self;
    }

    pub fn deinit(self: *VM) void {
        // self.root_fiber is gc-ed
        // self.current_fiber is gc-ed
        self.gc.deinit();
        self.* = undefined;
    }

    pub fn evaluate(self: *VM, input: *const Input) !Value {
        // TODO: compile the chunk
        _ = input;
        const chunk = demo_chunk;

        try self.current_fiber.pushFrame(self.allocator, 0, &chunk);

        var result: Value = undefined;
        while (true) {
            const instruction = try self.current_fiber.advance();
            switch (instruction.op) {
                .int => try self.current_fiber.push(self.allocator, .{ .raw = instruction.arg }),
                .add => {
                    const b = try self.current_fiber.pop();
                    const a = try self.current_fiber.pop();
                    try self.current_fiber.push(self.allocator, .{ .raw = a.raw + b.raw });
                },
                .ret => {
                    result = try self.current_fiber.pop();
                    break;
                },
                else => unreachable,
            }
        }

        try self.current_fiber.popFrame();
        return result;
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
