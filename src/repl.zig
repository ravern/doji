const std = @import("std");
const doji = @import("doji");

fn readLine(allocator: std.mem.Allocator, reader: anytype) ![]const u8 {
    return reader.readUntilDelimiterAlloc(allocator, '\n', std.math.maxInt(usize));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const in = std.io.getStdIn().reader();
    const out = std.io.getStdOut().writer();

    var gc = doji.GC.init(.{}, allocator, .{ .allocator = allocator });
    defer gc.deinit();

    try out.writeAll("Dōji v0.0.0\n");
    while (true) {
        try out.writeAll("> ");

        const line = readLine(allocator, in) catch |err| {
            switch (err) {
                error.EndOfStream => {
                    try out.print("\nbye.\n", .{});
                    return;
                },
                else => return err,
            }
        };
        defer allocator.free(line);

        const line_string = try gc.create(doji.value.String);
        line_string.* = doji.value.String{ .gc = try allocator.dupe(u8, line) };

        try out.print("{s}\n", .{line_string.toStr()});

        try gc.step();
    }
}
