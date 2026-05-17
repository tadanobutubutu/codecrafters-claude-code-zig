const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    _ = gpa.allocator();

    var buf: [1024]u8 = undefined;
    var stdout_buffered = std.fs.File.stdout().writer(&buf);
    const stdout = stdout_buffered.writer();

    try stdout.print("Hello from Zig 0.15!\n", .{});
    try stdout_buffered.flush();
}
