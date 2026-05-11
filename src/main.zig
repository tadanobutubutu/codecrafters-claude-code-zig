const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const io = init.io;

    var arg_it = try std.process.Args.Iterator.initAllocator(init.minimal.args, allocator);
    defer arg_it.deinit();

    _ = arg_it.next(); // argv0
    const flag = arg_it.next() orelse @panic("Usage: main -p <prompt>");
    const prompt_str = arg_it.next() orelse @panic("Usage: main -p <prompt>");
    if (!std.mem.eql(u8, flag, "-p")) {
        @panic("Usage: main -p <prompt>");
    }

    const api_key = init.environ_map.get("OPENROUTER_API_KEY") orelse @panic("OPENROUTER_API_KEY is not set");
    const base_url = init.environ_map.get("OPENROUTER_BASE_URL") orelse "https://openrouter.ai/api/v1";

    // Build request body
    var body_out: std.Io.Writer.Allocating = .init(allocator);
    defer body_out.deinit();
    var jw: std.json.Stringify = .{ .writer = &body_out.writer };
    try jw.write(.{
        .model = "anthropic/claude-haiku-4.5",
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
    });
    const body = body_out.written();

    // Build URL and auth header
    const url_str = try std.fmt.allocPrint(allocator, "{s}/chat/completions", .{base_url});
    defer allocator.free(url_str);

    const auth_value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
    defer allocator.free(auth_value);

    // Make HTTP request
    var client: std.http.Client = .{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();

    var response_out: std.Io.Writer.Allocating = .init(allocator);
    defer response_out.deinit();

    _ = try client.fetch(.{
        .location = .{ .url = url_str },
        .method = .POST,
        .payload = body,
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
            .{ .name = "authorization", .value = auth_value },
        },
        .response_writer = &response_out.writer,
    });
    const response_body = response_out.written();

    // Parse response
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_body, .{});
    defer parsed.deinit();

    const choices = parsed.value.object.get("choices") orelse @panic("No choices in response");
    if (choices.array.items.len == 0) {
        @panic("No choices in response");
    }

    const message = choices.array.items[0].object.get("message") orelse @panic("No message in response");
    if (message.object.get("tool_calls")) |tool_calls| {
        if (tool_calls == .array) {
            for (tool_calls.array.items) |tool_call| {
                const func = tool_call.object.get("function").?.object;
                if (std.mem.eql(u8, func.get("name").?.string, "Read")) {
                    const args_str = func.get("arguments").?.string;
                    const args = try std.json.parseFromSlice(struct { file_path: []const u8 }, allocator, args_str, .{ .ignore_unknown_fields = true });
                    defer args.deinit();

                    const file_content = try std.fs.cwd().readFileAlloc(allocator, args.value.file_path, 1024 * 1024);
                    defer allocator.free(file_content);

                    try std.Io.File.stdout().writeStreamingAll(io, file_content);
                }
            }
        }
    } else {
        const content = message.object.get("content") orelse @panic("No content in response");
        if (content != .null) {
            try std.Io.File.stdout().writeStreamingAll(io, content.string);
        }
    }
}
