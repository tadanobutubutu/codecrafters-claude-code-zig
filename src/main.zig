const std = @import("std");

const ToolCall = struct {
    id: []const u8,
    type: []const u8 = "function",
    function: struct {
        name: []const u8,
        arguments: []const u8,
    },
};

const Message = struct {
    role: []const u8,
    content: ?[]const u8 = null,
    tool_calls: ?[]const ToolCall = null,
    tool_call_id: ?[]const u8 = null,
};

const Response = struct {
    choices: []struct {
        message: struct {
            role: []const u8,
            content: ?[]const u8 = null,
            tool_calls: ?[]const ToolCall = null,
        },
    },
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.next(); // argv0
    const flag = args.next() orelse {
        std.debug.print("Usage: main -p <prompt>\n", .{});
        return;
    };
    const prompt_str = args.next() orelse {
        std.debug.print("Usage: main -p <prompt>\n", .{});
        return;
    };
    if (!std.mem.eql(u8, flag, "-p")) {
        std.debug.print("Usage: main -p <prompt>\n", .{});
        return;
    }

    const api_key = std.process.getEnvVarOwned(allocator, "OPENROUTER_API_KEY") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => {
            std.debug.print("OPENROUTER_API_KEY is not set\n", .{});
            return err;
        },
        else => return err,
    };
    defer allocator.free(api_key);

    const base_url = std.process.getEnvVarOwned(allocator, "OPENROUTER_BASE_URL") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => try allocator.dupe(u8, "https://openrouter.ai/api/v1"),
        else => return err,
    };
    defer allocator.free(base_url);

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri_str = try std.fmt.allocPrint(allocator, "{s}/chat/completions", .{base_url});
    defer allocator.free(uri_str);
    const parsed_uri = try std.Uri.parse(uri_str);

    const auth_value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
    defer allocator.free(auth_value);

    // Initial message history
    var messages = std.ArrayList(Message){};
    defer {
        for (messages.items) |msg| {
            allocator.free(msg.role);
            if (msg.content) |c| allocator.free(c);
            if (msg.tool_call_id) |id| allocator.free(id);
            if (msg.tool_calls) |tcs| {
                for (tcs) |tc| {
                    allocator.free(tc.id);
                    allocator.free(tc.type);
                    allocator.free(tc.function.name);
                    allocator.free(tc.function.arguments);
                }
                allocator.free(tcs);
            }
        }
        messages.deinit(allocator);
    }

    try messages.append(allocator, .{ 
        .role = try allocator.dupe(u8, "user"), 
        .content = try allocator.dupe(u8, prompt_str) 
    });

    while (true) {
        // Build request body
        var body_buf = std.io.Writer.Allocating.init(allocator);
        defer body_buf.deinit();

        try std.json.Stringify.value(.{
            .model = "anthropic/claude-3.5-sonnet",
            .messages = messages.items,
            .tools = &[_]struct {
                type: []const u8,
                function: struct {
                    name: []const u8,
                    description: []const u8,
                    parameters: struct {
                        type: []const u8,
                        properties: struct {
                            file_path: struct {
                                type: []const u8,
                                description: []const u8,
                            },
                        },
                        required: []const []const u8,
                    },
                },
            }{
                .{
                    .type = "function",
                    .function = .{
                        .name = "read_file",
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
        }, .{}, &body_buf.writer);

        var response_buf = std.io.Writer.Allocating.init(allocator);
        defer response_buf.deinit();

        const fetch_res = try client.fetch(.{
            .location = .{ .uri = parsed_uri },
            .method = .POST,
            .payload = body_buf.written(),
            .response_writer = &response_buf.writer,
            .extra_headers = &.{
                .{ .name = "content-type", .value = "application/json" },
                .{ .name = "authorization", .value = auth_value },
            },
        });

        if (fetch_res.status != .ok) {
            std.debug.print("API returned status {d}: {s}\n", .{ @intFromEnum(fetch_res.status), response_buf.written() });
            return error.ApiError;
        }

        const response_body = response_buf.written();

        const parsed = try std.json.parseFromSlice(Response, allocator, response_body, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        if (parsed.value.choices.len == 0) return error.NoChoicesInResponse;
        
        const res_msg = parsed.value.choices[0].message;
        
        // Add assistant message to history
        try messages.append(allocator, .{
            .role = try allocator.dupe(u8, res_msg.role),
            .content = if (res_msg.content) |c| try allocator.dupe(u8, c) else null,
            .tool_calls = if (res_msg.tool_calls) |tcs| try dupeToolCalls(allocator, tcs) else null,
        });

        if (res_msg.tool_calls) |tool_calls| {
            for (tool_calls) |tool_call| {
                if (std.mem.eql(u8, tool_call.function.name, "read_file")) {
                    const args_parsed = try std.json.parseFromSlice(struct { file_path: []const u8 }, allocator, tool_call.function.arguments, .{ .ignore_unknown_fields = true });
                    defer args_parsed.deinit();

                    const file_path = args_parsed.value.file_path;
                    const content = std.fs.cwd().readFileAlloc(allocator, file_path, 1024 * 1024) catch |err| {
                        const err_msg = try std.fmt.allocPrint(allocator, "Error reading file: {any}", .{err});
                        try messages.append(allocator, .{
                            .role = try allocator.dupe(u8, "tool"),
                            .tool_call_id = try allocator.dupe(u8, tool_call.id),
                            .content = err_msg,
                        });
                        continue;
                    };
                    
                    // Add tool result to history
                    try messages.append(allocator, .{
                        .role = try allocator.dupe(u8, "tool"),
                        .tool_call_id = try allocator.dupe(u8, tool_call.id),
                        .content = content,
                    });
                }
            }
            // Continue loop to feed tool results back to LLM
        } else {
            // Final response
            if (res_msg.content) |content| {
                try std.fs.File.stdout().writeAll(content);
            }
            break;
        }
    }
}

fn dupeToolCalls(allocator: std.mem.Allocator, tcs: []const ToolCall) ![]ToolCall {
    const new_tcs = try allocator.alloc(ToolCall, tcs.len);
    for (tcs, 0..) |tc, i| {
        new_tcs[i] = .{
            .id = try allocator.dupe(u8, tc.id),
            .type = try allocator.dupe(u8, tc.type),
            .function = .{
                .name = try allocator.dupe(u8, tc.function.name),
                .arguments = try allocator.dupe(u8, tc.function.arguments),
            },
        };
    }
    return new_tcs;
}
