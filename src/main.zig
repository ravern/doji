const std = @import("std");
const doji = @import("root.zig");

const Doji = doji.Doji(.{});
const VM = Doji.VM;
const GC = Doji.GC;
const String = Doji.String;

fn readLine(allocator: std.mem.Allocator, reader: anytype) ![]const u8 {
    return reader.readUntilDelimiterAlloc(allocator, '\n', std.math.maxInt(usize));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var gc = GC.init(allocator, allocator);
    defer gc.deinit();

    const in = std.io.getStdIn().reader();
    const out = std.io.getStdOut().writer();

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

        const string = try gc.create(String);
        string.* = try String.initDynamic(allocator, line);

        try out.print("{s}\n", .{line});
    }
}
