const std = @import("std");
const Chunk = @import("chunk.zig").Chunk;
const Instruction = @import("chunk.zig").Instruction;
const Constant = @import("chunk.zig").Constant;
const GC = @import("gc.zig").GC;
const Input = @import("input.zig").Input;
const Value = @import("value.zig").Value;

const demo_chunk = Chunk{
    .code = &[_]Instruction{
        .{ .op = .nop, .arg = 0 },
    },
    .constants = &[_]Constant{},
};

const stack_init_size = 1024;

pub const VM = struct {
    allocator: std.mem.Allocator,
    gc_allocator: std.mem.Allocator,
    root_fiber: *Fiber,
    current_fiber: *Fiber,

    const Error = error{StackUnderflow};

    pub fn init(allocator: std.mem.Allocator, gc: *GC) !VM {
        var self = VM{
            .allocator = allocator,
            .gc_allocator = gc.allocator(),
            .root_fiber = undefined,
            .current_fiber = undefined,
        };

        self.root_fiber = try self.gc_allocator.create(Fiber);
        self.root_fiber.* = try Fiber.init(allocator, self.gc_allocator);

        self.current_fiber = self.root_fiber;

        try gc.addRoot(&self);

        return self;
    }

    pub fn deinit(self: *VM) void {
        self.* = undefined;
    }

    pub fn evaluate(self: *VM, input: *const Input) !Value {
        try self.current_fiber.pushFrame(&demo_chunk);
        try self.current_fiber.push(.{ .raw = 0 });
        const value = try self.current_fiber.pop();
        try self.current_fiber.popFrame();
        std.debug.print("{s}\n", .{input.content});
        return value;
    }
};

pub const Fiber = struct {
    gc_allocator: std.mem.Allocator,
    call_frames: std.ArrayList(CallFrame),
    stack: std.ArrayList(Value),

    pub const CallFrame = struct {
        chunk: *const Chunk,
        bp: [*]Value,
        sp: [*]Value,
        ip: [*]const Instruction,
    };

    pub fn init(allocator: std.mem.Allocator, gc_allocator: std.mem.Allocator) !Fiber {
        return Fiber{
            .gc_allocator = gc_allocator,
            .call_frames = std.ArrayList(CallFrame).init(allocator),
            .stack = try std.ArrayList(Value).initCapacity(allocator, stack_init_size),
        };
    }

    pub fn pushFrame(self: *Fiber, chunk: *const Chunk) !void {
        try self.call_frames.append(.{
            .chunk = chunk,
            .bp = self.stack.items.ptr,
            .sp = self.stack.items.ptr,
            .ip = chunk.code.ptr,
        });
    }

    pub fn popFrame(self: *Fiber) !void {
        if (self.call_frames.items.len == 0) {
            return error.StackUnderflow;
        }
        _ = self.call_frames.pop();
    }

    pub fn push(self: *Fiber, value: Value) !void {
        var frame = self.getCurrentFrame();

        const stack_ptr = self.stack.items.ptr;

        try self.stack.append(value);
        frame.sp += 1;

        // check if stack items have been moved (due to realloc), if so, move bp and sp accordingly
        if (stack_ptr != self.stack.items.ptr) {
            const bp_offset = @intFromPtr(frame.bp) - @intFromPtr(stack_ptr);
            const sp_offset = @intFromPtr(frame.sp) - @intFromPtr(stack_ptr);
            frame.bp = @ptrFromInt(@intFromPtr(self.stack.items.ptr) + bp_offset);
            frame.sp = @ptrFromInt(@intFromPtr(self.stack.items.ptr) + sp_offset);
        }
    }

    pub fn pop(self: *Fiber) !Value {
        var frame = self.getCurrentFrame();
        if (self.stack.items.len == 0 or frame.sp == frame.bp) {
            return error.StackUnderflow;
        }
        frame.sp -= 1;
        return self.stack.pop();
    }

    pub fn advance(self: *Fiber) Instruction {
        var frame = self.getCurrentFrame();
        const instruction = frame.ip[0];
        frame.ip += 1;
        return instruction;
    }

    inline fn getCurrentFrame(self: *Fiber) *CallFrame {
        return &self.call_frames.items[self.call_frames.items.len - 1];
    }
};
