const std = @import("std");

pub fn main() !void {
    const T = std.Io.Writer.Allocating;
    std.debug.print("std.Io.Writer.Allocating Type: {s}\n", .{@typeName(T)});

    const ti = @typeInfo(T);
    switch (ti) {
        .@"struct" => |s| {
            inline for (s.decls) |decl| {
                std.debug.print("decl: {s}\n", .{decl.name});
            }
        },
        else => {
            std.debug.print("not a struct: {any}\n", .{ti});
        },
    }
}
