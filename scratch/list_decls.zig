const std = @import("std");

pub fn main() !void {
    inline for (std.meta.declarations(std.io)) |decl| {
        @compileLog(decl.name);
    }
}
