const std = @import("std");

pub fn main() !void {
    const stdout = std.Io.File.stdout;
    // How to get a writer?
    // In the previous code it used:
    // try std.Io.File.stdout().writeStreamingAll(io, content);
}
