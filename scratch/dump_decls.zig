const std = @import("std");

pub fn main() !void {
    const ti = @typeInfo(std.Io);
    switch (ti) {
        .@"struct" => |s| {
            inline for (s.decls) |decl| {
                std.debug.print("std.Io: {s}\n", .{decl.name});
            }
        },
        else => {},
    }

    const ti_writer = @typeInfo(std.Io.Writer);
    switch (ti_writer) {
        .@"struct" => |s| {
            inline for (s.decls) |decl| {
                std.debug.print("std.Io.Writer: {s}\n", .{decl.name});
            }
        },
        else => {},
    }
}
