const std = @import("std");

pub fn main() !void {
    const args = std.os.argv;
    for (args) |arg| {
        const slice = std.mem.span(arg);
        _ = slice;
    }
}
