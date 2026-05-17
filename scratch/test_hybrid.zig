const std = @import("std");

fn main015() !void {
    const allocator = std.heap.page_allocator;
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();
    const flag = args.next() orelse {
        std.debug.print("0.15: No args\n", .{});
        return;
    };
    std.debug.print("0.15: flag={s}\n", .{flag});
}

fn main016(init: anytype) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 2) {
        std.debug.print("0.16: No args\n", .{});
        return;
    }
    std.debug.print("0.16: flag={s}\n", .{args[1]});
}

pub const main = if (@hasDecl(std.process, "Init"))
    struct {
        // 0.16 用の main
        pub fn main(init: std.process.Init) !void {
            try main016(init);
        }
    }.main
else
    struct {
        // 0.15 用の main
        pub fn main() !void {
            try main015();
        }
    }.main;
