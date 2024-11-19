pub const Source = union(enum) {
    stdin,
    file: []const u8,
};

pub const Input = struct {
    source: Source,
    content: []const u8,
};
