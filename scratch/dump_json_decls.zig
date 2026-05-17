const std = @import("std");

pub fn main() !void {
    const ti = @typeInfo(std.json);
    switch (ti) {
        .@"struct" => |s| {
            inline for (s.decls) |decl| {
                std.debug.print("std.json: {s}\n", .{decl.name});
            }
        },
        else => {},
    }
}
