const std = @import("std");
const doji = @import("root.zig");

fn readLine(allocator: std.mem.Allocator, reader: anytype) ![]const u8 {
    return reader.readUntilDelimiterAlloc(allocator, '\n', std.math.maxInt(usize));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = try doji.VM.init(allocator);
    defer vm.deinit();

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

        const input = doji.Input{ .source = .stdin, .content = line };
        const result = try vm.evaluate(&input);
        try out.print("{d}\n", .{result.cast(i48).?});
    }
}
