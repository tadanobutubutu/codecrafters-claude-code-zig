const std = @import("std");

pub fn main() !void {
    const ti = @typeInfo(std.json.Stringify);
    switch (ti) {
        .@"struct" => |s| {
            inline for (s.decls) |decl| {
                std.debug.print("std.json.Stringify: {s}\n", .{decl.name});
            }
        },
        else => {
            std.debug.print("std.json.Stringify is not a struct: {any}\n", .{ti});
        },
    }
}
