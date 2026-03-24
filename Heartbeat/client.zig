const std = @import("std");
const posix = std.posix;

pub fn main() !void {
    // Адрес сервера
    const server_addr = try std.net.Address.parseIp("127.0.0.1", 8080);

    // Создаем UDP сокет
    const sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, 0);
    defer posix.close(sock);

    const message = "PING";
    std.debug.print("Клиент запущен, шлем пакеты...\n", .{});

    while (true) {
        // Отправляем данные
        _ = posix.sendto(sock, message, 0, &server_addr.any, server_addr.getOsSockLen()) catch |err| {
            std.debug.print("Ошибка отправки: {}\n", .{err});
        };

        std.debug.print("Отправлено: {s}\n", .{message});

        // Спим секунду
        std.Thread.sleep(1 * std.time.ns_per_s);
    }
}
