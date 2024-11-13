const std = @import("std");

const Self = @This();

pub const Location = struct {
    offset: usize,
    line: usize,
    col: usize,

    pub const zero = Location{ .offset = 0, .line = 1, .col = 1 };
};

pub const zero = Self{ .start_loc = Location.zero, .end_loc = Location.zero };

start_loc: Location,
end_loc: Location,

pub fn merge(self: Self, other: Self) Self {
    const start_loc = if (self.start_loc.offset < other.start_loc.offset) self.start_loc else other.start_loc;
    const end_loc = if (self.end_loc.offset > other.end_loc.offset) self.end_loc else other.end_loc;
    return Self{ .start_loc = start_loc, .end_loc = end_loc };
}

pub fn getLength(self: Self) usize {
    return self.end_loc.offset - self.start_loc.offset;
}
