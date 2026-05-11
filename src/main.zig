const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 3) return;
    const prompt_str = args[2];

    const api_key = std.posix.getenv("OPENROUTER_API_KEY") orelse return;
    const base_url = std.posix.getenv("OPENROUTER_BASE_URL") orelse "https://openrouter.ai/api/v1";

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri_str = try std.fmt.allocPrint(allocator, "{s}/chat/completions", .{base_url});
    defer allocator.free(uri_str);
    const uri = try std.Uri.parse(uri_str);

    var body_buf = std.ArrayList(u8).empty;
    defer body_buf.deinit(allocator);

    // Advertise Read tool
    try body_buf.writer(allocator).print("{f}", .{std.json.fmt(.{
        .model = "anthropic/claude-3.5-sonnet",
        .messages = &.{
            .{ .role = "user", .content = prompt_str },
        },
        .tools = &.{
            .{
                .type = "function",
                .function = .{
                    .name = "Read",
                    .description = "Read and return the contents of a file",
                    .parameters = .{
                        .type = "object",
                        .properties = .{
                            .file_path = .{
                                .type = "string",
                                .description = "The path to the file to read",
                            },
                        },
                        .required = &.{ "file_path" },
                    },
                },
            },
        },
    }, .{})});

    var response_buf = std.ArrayListUnmanaged(u8).empty;
    var response_alloc_writer = std.io.Writer.Allocating.fromArrayList(allocator, &response_buf);
    defer response_alloc_writer.deinit();

    const auth_header = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
    defer allocator.free(auth_header);

    _ = try client.fetch(.{
        .method = .POST,
        .location = .{ .uri = uri },
        .payload = body_buf.items,
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "Authorization", .value = auth_header },
        },
        .response_writer = &response_alloc_writer.writer,
    });

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_alloc_writer.written(), .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const choices = parsed.value.object.get("choices") orelse return;
    const choice = choices.array.items[0];
    const message = choice.object.get("message") orelse return;

    if (message.object.get("tool_calls")) |tool_calls| {
        for (tool_calls.array.items) |tool_call| {
            const func = tool_call.object.get("function").?.object;
            const name = func.get("name").?.string;
            if (std.mem.eql(u8, name, "Read")) {
                const func_args_str = func.get("arguments").?.string;
                const func_args = try std.json.parseFromSlice(struct { file_path: []const u8 }, allocator, func_args_str, .{ .ignore_unknown_fields = true });
                defer func_args.deinit();

                const content = try std.fs.cwd().readFileAlloc(allocator, func_args.value.file_path, 1024 * 1024);
                defer allocator.free(content);

                try std.fs.File.stdout().writeAll(content);
            }
        }
    } else if (message.object.get("content")) |content| {
        if (content == .string) {
            try std.fs.File.stdout().writeAll(content.string);
        }
    }
}
