const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const address = try std.net.Address.parseIp("0.0.0.0", 8080);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();
    std.debug.print("Сервер запущен...\n", .{});

    while (true) {
        const connection = try server.accept();
        const stream = connection.stream;
        defer stream.close();
        std.debug.print("Сервер принял подключение...\n", .{});

        var writerBuffer: [1024]u8 = undefined;
        var writerContext = stream.writer(&writerBuffer);
        const writer = &writerContext.interface;

        var readerBuffer: [1024]u8 = undefined;
        var readerContext = stream.reader(&readerBuffer);
        const reader = readerContext.interface();

        try handleClient(allocator, writer, reader);
    }
}

fn handleClient(allocator: std.mem.Allocator, writer: *std.Io.Writer, reader: *std.Io.Reader) !void {
    var userVariables = std.StringHashMap([]const u8).init(allocator);
    defer {
        var userVarsIterator = userVariables.iterator();
        while (userVarsIterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        userVariables.deinit();
    }
    while (true) {
        const userString = reader.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => {
                std.debug.print("Пользователь закончил ввод\n", .{});
                return;
            },
            else => return err,
        };

        const trimmed = std.mem.trim(u8, userString, "\r\n\t ");
        if (trimmed.len == 0) continue;

        var strIterator = std.mem.tokenizeScalar(u8, trimmed, ' ');
        const command = strIterator.next() orelse continue;
        const variable = strIterator.next() orelse "";
        const value = strIterator.next() orelse "";

        std.debug.print("command: {s}, var: {s}, val: {s}\n", .{ command, variable, value });

        if (std.mem.eql(u8, command, "SET")) {
            try userVariables.put(try allocator.dupe(u8, variable), try allocator.dupe(u8, value));
            try writer.print("Wrote {s} var with {s} val\n", .{ variable, value });
        } else if (std.mem.eql(u8, command, "GET")) {
            const val = userVariables.get(variable) orelse "unknown";
            try writer.print("Value: {s}\n", .{val});
        } else if (std.mem.eql(u8, command, "DEL")) {
            const result = userVariables.remove(variable);
            switch (result) {
                true => try writer.print("Variable {s} deleted\n", .{variable}),
                false => try writer.print("Variable {s} isn't deleted\n", .{variable}),
            }
        } else {
            _ = try writer.write("Unknown command\n");
        }
        try writer.flush();
    }
}
