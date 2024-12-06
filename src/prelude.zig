const std = @import("std");
const Value = @import("value.zig").Value;
const ForeignFn = @import("value.zig").ForeignFn;

pub const add_foreign_fn = &ForeignFn{
    .arity = 2,
    .step_fns = &[_]ForeignFn.StepFn{add},
};

fn add(ctx: ForeignFn.Context) !ForeignFn.Result {
    const left = ctx.fiber.pop().?;
    const right = ctx.fiber.pop().?;
    _ = ctx.fiber.pop();
    return .{ .ret = Value.add(left, right).? };
}
