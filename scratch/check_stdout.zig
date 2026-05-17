const std = @import("std");
pub fn main() !void {
    var stdout = std.fs.File.stdout().writer(&.{});
    try stdout.interface.print("test\n", .{});
}
