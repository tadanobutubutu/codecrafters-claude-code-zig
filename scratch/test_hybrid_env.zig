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
    const api_key = std.process.getEnvVarOwned(allocator, "OPENROUTER_API_KEY") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            std.debug.print("OPENROUTER_API_KEY not found\n", .{});
            return;
        },
        else => return err,
    };
    defer allocator.free(api_key);
    std.debug.print("0.15: flag={s} api_key={s}\n", .{flag, api_key});
}

fn main016(init: anytype) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 2) {
        std.debug.print("0.16: No args\n", .{});
        return;
    }
    const api_key = init.environ_map.get("OPENROUTER_API_KEY") orelse {
        std.debug.print("0.16: OPENROUTER_API_KEY not found\n", .{});
        return;
    };
    std.debug.print("0.16: flag={s} api_key={s}\n", .{args[1], api_key});
}

pub const main = if (@hasDecl(std.process, "Init"))
    struct {
        pub fn main(init: std.process.Init) !void {
            try main016(init);
        }
    }.main
else
    struct {
        pub fn main() !void {
            try main015();
        }
    }.main;
