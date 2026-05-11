const std = @import("std");

pub fn main() !void {
    @compileLog(@typeInfo(std.process));
}
