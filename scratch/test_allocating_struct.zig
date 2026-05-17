const std = @import("std");

pub fn main() !void {
    const T = std.Io.Writer.Allocating;
    const ti = @typeInfo(T);
    switch (ti) {
        .@"struct" => |s| {
            inline for (s.fields) |field| {
                std.debug.print("field: {s} : {s}\n", .{field.name, @typeName(field.type)});
            }
        },
        else => {},
    }
}
