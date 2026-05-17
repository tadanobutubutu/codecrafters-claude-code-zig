const std = @import("std");

pub fn main() !void {
    std.debug.print("init: {s}\n", .{@typeName(@TypeOf(std.Io.Writer.Allocating.init))});
    std.debug.print("fromArrayList: {s}\n", .{@typeName(@TypeOf(std.Io.Writer.Allocating.fromArrayList))});
}
