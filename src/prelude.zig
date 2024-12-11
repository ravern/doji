const std = @import("std");
const compile = @import("compile.zig");
const Error = @import("value.zig").Error;
const Value = @import("value.zig").Value;
const String = @import("value.zig").String;
const ForeignFn = @import("value.zig").ForeignFn;

pub const add_foreign_fn = &ForeignFn{
    .arity = 2,
    .step_fns = &[_]ForeignFn.StepFn{add},
    .trace_items = &[_]Error.TraceItem{
        .{ .path = "prelude.zig", .location = .{ .line = 14, .column = 1 } },
    },
};

fn add(ctx: ForeignFn.Context) !ForeignFn.Result {
    const left = ctx.fiber.pop().?;
    const right = ctx.fiber.pop().?;
    _ = ctx.fiber.pop();
    return .{ .ret = Value.add(left, right).? };
}
