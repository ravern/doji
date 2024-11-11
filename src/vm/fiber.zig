const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const bytecode = @import("./bytecode.zig");
const Chunk = bytecode.Chunk;
const Instruction = bytecode.Instruction;
const DojiError = @import("../errors.zig").DojiError;
const Environment = @import("../global.zig").Environment;
const value = @import("./value.zig");
const Value = value.Value;
const Upvalue = value.Upvalue;

pub const Fiber = struct {
    chunk: *const Chunk,
    instruction: [*]const Instruction,
    stack: ValueStack,
    arg: usize = 0,

    pub fn init(gc_allocator: Allocator, chunk: *const Chunk) !Fiber {
        return Fiber{
            .chunk = chunk,
            .instruction = chunk.code.ptr,
            .stack = try ValueStack.initCapacity(gc_allocator, 128), // TODO: make configurable
        };
    }

    pub fn step(self: *Fiber, gc_allocator: Allocator, env: *Environment) !FiberStep {
        const instruction = self.advance();

        // accumulate the argument for the next instruction
        self.arg = (self.arg << @bitSizeOf(u8)) | @as(usize, @intCast(instruction.arg));
        if (instruction.op == .ext) return FiberStep.Continue;
        // reset the argument if the instruction is not an ext op
        const arg = self.arg;
        self.arg = 0;

        switch (instruction.op) {
            .ext => unreachable,
            .nil => {
                try self.stack.push(gc_allocator, Value.nil);
                return FiberStep.Continue;
            },
            .bool => {
                try self.stack.push(gc_allocator, Value.initBool(if (arg == 1) true else if (arg == 0) false else unreachable));
                return FiberStep.Continue;
            },
            .int => {
                try self.stack.push(gc_allocator, Value.initInt(@intCast(arg)));
                return FiberStep.Continue;
            },
            .constant => {
                const val = env.constants.get(@intCast(arg));
                try self.stack.push(gc_allocator, val);
                return FiberStep.Continue;
            },
            .ret => {
                const val = self.stack.pop() orelse unreachable; // TODO
                return FiberStep{ .Done = val };
            },
            else => unreachable, // TODO
        }

        self.arg = 0;
    }

    fn advance(self: *Fiber) Instruction {
        const instruction = self.instruction[0];
        self.instruction += 1;
        return instruction;
    }
};

pub const FiberStep = union(enum) {
    Continue,
    Yield: Value,
    Resume: *Fiber,
    Done: Value,
};

const ValueStack = struct {
    vals: ArrayListUnmanaged(Value) = .{},
    open_upvals: ?*Upvalue = null,

    pub fn initCapacity(gc_allocator: Allocator, capacity: usize) !ValueStack {
        return ValueStack{
            .vals = try ArrayListUnmanaged(Value).initCapacity(gc_allocator, capacity),
        };
    }

    pub fn push(self: *ValueStack, gc_allocator: Allocator, val: Value) !void {
        try self.vals.append(gc_allocator, val);
    }

    pub fn pop(self: *ValueStack) ?Value {
        return self.vals.popOrNull();
    }
};
