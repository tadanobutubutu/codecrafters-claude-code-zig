const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var list = std.ArrayList(u8){};
    defer list.deinit(allocator);

    const val = .{ .foo = "bar" };
    try std.json.Stringify.value(val, .{}, list.writer(allocator));
    
    std.debug.print("JSON: {s}\n", .{list.items});
}
