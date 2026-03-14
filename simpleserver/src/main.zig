const std = @import("std");

pub fn main() !void {
    const address = std.net.Address.parseIp("0.0.0.0", 8080) catch unreachable;

    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    const connection = try server.accept();
    const stream = connection.stream;

    var buffer: [1024]u8 = undefined;
    const readed = try stream.read(&buffer);

    std.debug.print("Пользователь отправил: {s}({d} байт)\n", .{ buffer[0..readed], readed });
    _ = try stream.write("Привет от сервера\n");
}
