const std = @import("std");
const doji = @import("doji.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = try doji.VM.init(allocator);
    defer vm.deinit();

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

        const source = doji.Source.initStdin(line);
        const result = vm.eval(source) catch continue;
        std.debug.print("{}\n", .{result});
    }
}
