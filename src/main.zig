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
    const auth_value = try std.fmt.allocPrint(allocator, "Bearer {s}", .{api_key});
    defer allocator.free(auth_value);

    // Initial message history
    var messages = std.ArrayList(std.json.Value).init(allocator);
    defer {
        // We should ideally clean up the values, but for a short-lived process it might be okay.
        // However, let's try to be clean if possible.
        messages.deinit();
    }

    var user_msg_map = std.json.ObjectMap.init(allocator);
    try user_msg_map.put("role", std.json.Value{ .string = "user" });
    try user_msg_map.put("content", std.json.Value{ .string = prompt_str });
    try messages.append(std.json.Value{ .object = user_msg_map });

    while (true) {
        // Build request body
        var body_out: std.Io.Writer.Allocating = .init(allocator);
        defer body_out.deinit();
        var jw: std.json.Stringify = .{ .writer = &body_out.writer };
        
        // Construct the request object
        try jw.beginObject();
        try jw.objectField("model");
        try jw.write("anthropic/claude-haiku-4.5");
        
        try jw.objectField("messages");
        try jw.write(messages.items);
        
        // Advertise tools
        try jw.objectField("tools");
        try jw.beginArray();
        try jw.beginObject();
        try jw.objectField("type");
        try jw.write("function");
        try jw.objectField("function");
        try jw.beginObject();
        try jw.objectField("name");
        try jw.write("Read");
        try jw.objectField("description");
        try jw.write("Read and return the contents of a file");
        try jw.objectField("parameters");
        try jw.beginObject();
        try jw.objectField("type");
        try jw.write("object");
        try jw.objectField("properties");
        try jw.beginObject();
        try jw.objectField("file_path");
        try jw.beginObject();
        try jw.objectField("type");
        try jw.write("string");
        try jw.objectField("description");
        try jw.write("The path to the file to read");
        try jw.endObject();
        try jw.endObject();
        try jw.objectField("required");
        try jw.beginArray();
        try jw.write("file_path");
        try jw.endArray();
        try jw.endObject();
        try jw.endObject();
        try jw.endObject();
        try jw.endArray();
        
        try jw.endObject();

        const body = body_out.written();

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

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, response_body, .{ .ignore_unknown_fields = true });
        
        const choices = parsed.value.object.get("choices") orelse @panic("No choices");
        const choice = choices.array.items[0];
        const message = choice.object.get("message") orelse @panic("No message");

        // Clone assistant message to persist in history
        const message_cloned = try cloneJsonValue(allocator, message);
        try messages.append(message_cloned);

        if (message.object.get("tool_calls")) |tool_calls| {
            for (tool_calls.array.items) |tool_call| {
                const tool_call_id = tool_call.object.get("id").?.string;
                const func = tool_call.object.get("function").?.object;
                const name = func.get("name").?.string;
                
                if (std.mem.eql(u8, name, "Read")) {
                    const func_args_str = func.get("arguments").?.string;
                    const func_args = try std.json.parseFromSlice(struct { file_path: []const u8 }, allocator, func_args_str, .{ .ignore_unknown_fields = true });
                    defer func_args.deinit();

                    const file_path = func_args.value.file_path;
                    var file = try std.Io.Dir.cwd().openFile(io, file_path, .{});
                    defer file.close(io);
                    
                    var buf: [1024 * 1024]u8 = undefined;
                    const bytes_read = try file.readPositionalAll(io, &buf, 0);
                    const file_content = try allocator.dupe(u8, buf[0..bytes_read]);
                    
                    // Add tool response to history
                    var tool_msg_map = std.json.ObjectMap.init(allocator);
                    try tool_msg_map.put("role", std.json.Value{ .string = "tool" });
                    try tool_msg_map.put("tool_call_id", std.json.Value{ .string = try allocator.dupe(u8, tool_call_id) });
                    try tool_msg_map.put("content", std.json.Value{ .string = file_content });
                    try messages.append(std.json.Value{ .object = tool_msg_map });
                }
            }
            parsed.deinit();
            // Continue loop
        } else {
            // No more tool calls, print content and exit
            if (message.object.get("content")) |content| {
                if (content == .string) {
                    try std.Io.File.stdout().writeStreamingAll(io, content.string);
                }
            }
            parsed.deinit();
            break;
        }
    }
}

fn cloneJsonValue(allocator: std.mem.Allocator, val: std.json.Value) !std.json.Value {
    switch (val) {
        .null => return .null,
        .bool => |b| return .{ .bool = b },
        .integer => |i| return .{ .integer = i },
        .float => |f| return .{ .float = f },
        .string => |s| return .{ .string = try allocator.dupe(u8, s) },
        .array => |a| {
            var new_arr = std.json.Array.init(allocator);
            for (a.items) |item| {
                try new_arr.append(try cloneJsonValue(allocator, item));
            }
            return .{ .array = new_arr };
        },
        .object => |o| {
            var new_obj = std.json.ObjectMap.init(allocator);
            var it = o.iterator();
            while (it.next()) |entry| {
                try new_obj.put(try allocator.dupe(u8, entry.key_ptr.*), try cloneJsonValue(allocator, entry.value_ptr.*));
            }
            return .{ .object = new_obj };
        },
        .number_string => |s| return .{ .number_string = try allocator.dupe(u8, s) },
    }
}
