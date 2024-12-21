const std = @import("std");
const doji = @import("doji");

fn readLine(allocator: std.mem.Allocator, reader: anytype) ![]const u8 {
    return reader.readUntilDelimiterAlloc(allocator, '\n', std.math.maxInt(usize));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var gc = doji.GC.init(allocator, allocator);
    defer gc.deinit();

    const in = std.io.getStdIn().reader();
    const out = std.io.getStdOut().writer();

    try out.writeAll("Dōji v0.0.1\n");
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

        const string = try gc.create(doji.String);
        string.* = try doji.String.initDynamic(allocator, line);

        try out.print("{s}\n", .{line});

        try gc.step();

        // std.debug.print("live object count: {d}\n", .{gc.stats.live_objects});
        // std.debug.print("live byte count: {d}\n", .{gc.stats.live_bytes});
        // std.debug.print("created object count: {d}\n", .{gc.stats.created_objects});
        // std.debug.print("created byte count: {d}\n", .{gc.stats.created_bytes});
        // std.debug.print("destroyed object count: {d}\n", .{gc.stats.destroyed_objects});
        // std.debug.print("destroyed byte count: {d}\n", .{gc.stats.destroyed_bytes});
    }
}
