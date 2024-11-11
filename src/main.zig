const std = @import("std");
const io = std.io;

const doji = @import("./root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = doji.Vm.init(allocator);
    defer vm.deinit();

    // start a quick repl
    const in = io.getStdIn().reader();
    const out = io.getStdOut().writer();
    while (true) {
        try out.print(">>> ", .{});
        const line = try in.readUntilDelimiterAlloc(allocator, '\n', 65535);
        _ = vm.execute(line) catch {
            _ = vm.getError().?;
            try out.print("error!\n", .{});
            continue;
        };
        try out.print("success.\n", .{});
    }
}
