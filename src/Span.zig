const Self = @This();

start: usize,
len: usize,

pub fn init(start: usize) Self {
    return Self{
        .start = start,
        .len = 0,
    };
}

pub fn initZero() Self {
    return Self.init(0);
}

pub fn merge(self: Self, other: Self) Self {
    const start = @min(self.start, other.start);
    const end = @max(self.start + self.len, other.start + other.len);
    return Self{
        .start = start,
        .len = end - start,
    };
}

pub fn toString(self: Self, source: []const u8) []const u8 {
    return source[self.start..self.getEnd()];
}

pub fn getEnd(self: Self) usize {
    return self.start + self.len;
}
