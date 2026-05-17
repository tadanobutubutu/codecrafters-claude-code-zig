const std = @import("std");

pub fn main() !void {
    var buf: [1024]u8 = undefined;
    var stdout_buffered = std.fs.File.stdout().writer(&buf);
    const stdout = &stdout_buffered.interface;

    try stdout.print("Hello from Zig 0.15.2!\n", .{});
    try stdout.flush();
}
