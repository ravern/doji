const std = @import("std");
const doji = @import("root.zig");

fn readLine(allocator: std.mem.Allocator, reader: anytype) ![]const u8 {
    return reader.readUntilDelimiterAlloc(allocator, '\n', std.math.maxInt(usize));
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const in = std.io.getStdIn().reader();
    const out = std.io.getStdOut().writer();

    var resolver = doji.FileResolver{};

    var gc = doji.GC.init(allocator);
    defer gc.deinit();

    var vm = try doji.VM.init(allocator, &gc, resolver.resolver());
    defer vm.deinit();

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

        const source = doji.Source.init("<stdin>", line);

        const result = vm.evaluate(&source) catch |err| {
            try out.print("error: {}\n", .{err});
            continue;
        };

        try out.print("{}\n", .{result});
    }
}
