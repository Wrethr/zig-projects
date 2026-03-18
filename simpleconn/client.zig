const std = @import("std");
const libconn = @import("libsimpleconn.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdinBuffer: [1024]u8 = undefined;
    var stdinContext = std.fs.File.stdin().reader(&stdinBuffer);
    const stdinReader = &stdinContext.interface;

    const serverAddress = try std.net.Address.parseIp("127.0.0.1", 8080);
    var client = try std.net.tcpConnectToAddress(serverAddress);
    defer client.close();

    var wg = std.Thread.WaitGroup{};

    var readerBuffer: [1024]u8 = undefined;
    var writerBuffer: [1024]u8 = undefined;

    var readerContext = client.reader(&readerBuffer);
    var writerContext = client.writer(&writerBuffer);

    const reader = readerContext.interface();
    const writer = &writerContext.interface;

    wg.start();
    var recvReader = try std.Thread.spawn(.{}, reciever, .{ allocator, &wg, reader });
    recvReader.detach();

    std.debug.print("> ", .{});
    while (true) {
        const message = stdinReader.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => {
                std.debug.print("Подключение закрыто\n", .{});
                return;
            },
            else => {
                std.debug.print("Ошибка получения строки: {}\n", .{err});
                return;
            },
        };
        const trim = std.mem.trim(u8, message, "\n \r\t");
        if (trim.len == 0) continue;

        try libconn.send(writer, trim);
        std.debug.print("> ", .{});
    }

    wg.wait();
}

pub fn reciever(allocator: std.mem.Allocator, wg: *std.Thread.WaitGroup, reader: *std.Io.Reader) void {
    defer wg.finish();

    while (true) {
        const message = libconn.recv(allocator, reader) catch |err| {
            std.debug.print("Ошибка получения данных: {}\n", .{err});
            return;
        };

        std.debug.print("\r{s}\n> ", .{message});

        allocator.free(message);
    }
}
