const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var alloc_writer = std.Io.Writer.Allocating.init(allocator);
    defer alloc_writer.deinit();

    const w = &alloc_writer.writer;
    try w.writeAll("hello, allocating!");

    const slice = alloc_writer.written();
    std.debug.print("Written content: '{s}'\n", .{slice});
}
