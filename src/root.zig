const gc = @import("gc.zig");

pub const GC = gc.GC(.{value.String}, .{});
pub const value = @import("value.zig");
