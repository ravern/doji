const std = @import("std");

const max_file_size = 50 << 20; // 50MB

pub const Resolver = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        resolve: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]const u8,
    };
};

pub const FileResolver = struct {
    pub fn resolver(self: *FileResolver) Resolver {
        return .{
            .ptr = self,
            .vtable = &.{
                .resolve = resolve,
            },
        };
    }

    pub fn resolve(ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
        _ = ctx;
        const file = try std.fs.cwd().openFile(path, .{});
        return file.readToEndAlloc(allocator, max_file_size);
    }
};

pub const MockResolver = struct {
    pub fn resolver(self: *MockResolver) Resolver {
        return .{
            .ptr = self,
            .vtable = &.{
                .resolve = resolve,
            },
        };
    }

    pub fn resolve(ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
        _ = ctx;
        _ = allocator;
        _ = path;
        return "";
    }
};
