const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const AL = std.ArrayList(u8);
    inline for (std.meta.declarations(AL)) |decl| {
        std.debug.print("Decl: {s}\n", .{decl.name});
    }
}
