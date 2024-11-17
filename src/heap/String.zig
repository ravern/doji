const std = @import("std");

const Self = @This();

str: []const u8,

pub fn init(str: []const u8) Self {
    return Self{
        .str = str,
    };
}
