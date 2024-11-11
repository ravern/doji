const std = @import("std");
const doji = @import("./doji.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const in = std.io.getStdIn().reader();
    const out = std.io.getStdOut().writer();

    while (true) {
        try out.writeAll("> ");

        const line = in.readUntilDelimiterAlloc(allocator, '\n', std.math.maxInt(usize)) catch |err| {
            switch (err) {
                error.EndOfStream => {
                    try out.print("\nbye.\n", .{});
                    break;
                },
                else => return err,
            }
        };
        defer allocator.free(line);

        try out.print("{s}\n", .{line});
    }
}
