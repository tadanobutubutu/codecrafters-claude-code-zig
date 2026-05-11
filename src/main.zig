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

    var client: std.http.Client = .{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();

    const uri_str = try std.fmt.allocPrint(allocator, "{s}/chat/completions", .{base_url});
    defer allocator.free(uri_str);

    // Build request body
    var body_out: std.Io.Writer.Allocating = .init(allocator);
    defer body_out.deinit();
    var jw: std.json.Stringify = .{ .writer = &body_out.writer };
    try jw.write(.{
        .model = "anthropic/claude-3.5-sonnet",
        .messages = &[_]struct { role: []const u8, content: []const u8 }{
            .{ .role = "user", .content = prompt_str },
        },
        .tools = &[_]struct { type: []const u8, function: struct { name: []const u8, description: []const u8, parameters: struct { type: []const u8, properties: struct { file_path: struct { type: []const u8, description: []const u8 } }, required: []const []const u8 } } }{
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
                        .required = &[_][]const u8{"file_path"},
                    },
                },
            },
        },
    });
    const body = body_out.written();

    const auth_value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
    defer allocator.free(auth_value);

    var response_out: std.Io.Writer.Allocating = .init(allocator);
    defer response_out.deinit();

    _ = try client.fetch(.{
        .location = .{ .url = uri_str },
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
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_body, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const choices = parsed.value.object.get("choices") orelse @panic("No choices");
    const choice = choices.array.items[0];
    const message = choice.object.get("message") orelse @panic("No message");

    if (message.object.get("tool_calls")) |tool_calls| {
        for (tool_calls.array.items) |tool_call| {
            const func = tool_call.object.get("function").?.object;
            const name = func.get("name").?.string;
            if (std.mem.eql(u8, name, "Read")) {
                const func_args_str = func.get("arguments").?.string;
                const func_args = try std.json.parseFromSlice(struct { file_path: []const u8 }, allocator, func_args_str, .{ .ignore_unknown_fields = true });
                defer func_args.deinit();

                var file = try std.Io.Dir.cwd().openFile(io, func_args.value.file_path, .{});
                defer file.close();
                
                // Read using allocRemaining or similar. Wait, earlier it was said "readPositional" or "readStreaming".
                // I will use @compileLog to see what File has if the test fails.
                    @compileLog("File decls:", @typeInfo(std.Io.File).@"struct".decls);
                    
                    // Dummy usage to pass zig's unused variable checks
                    _ = file;
                    
                    try std.Io.File.stdout().writeStreamingAll(io, "dummy");
            }
        }
    } else if (message.object.get("content")) |content| {
        if (content == .string) {
            try std.Io.File.stdout().writeStreamingAll(io, content.string);
        }
    }
}
