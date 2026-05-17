const std = @import("std");

pub fn main() !void {
    const T = @TypeOf(std.http.Client.fetch);
    @compileError(@typeName(T));
}
