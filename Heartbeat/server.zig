const std = @import("std");
const posix = std.posix;

const Connection = struct {
    address: std.net.Address,
    lastSeen: i64,
};

const Server = struct {
    fd: posix.socket_t,
    addr: std.net.Address,

    mutex: std.Thread.Mutex = .{},
    conns: std.ArrayList(Connection),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, ip: []const u8, port: u16) !Self {
        const addr = try std.net.Address.parseIp(ip, port);

        const sock = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, 0);
        errdefer posix.close(sock);

        try posix.bind(sock, &addr.any, addr.getOsSockLen());

        return .{
            .fd = sock,
            .addr = addr,
            .conns = try std.ArrayList(Connection).initCapacity(allocator, 4),
        };
    }
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.conns.deinit(allocator);
        posix.close(self.fd);
    }

    pub fn run(self: *Self, allocator: std.mem.Allocator) void {
        var buf: [1024]u8 = undefined;

        std.debug.print("Сервер запущен.\n", .{});

        while (true) {
            var newAddr: std.net.Address = undefined;
            var newAddrLen: posix.socklen_t = @sizeOf(std.net.Address);

            const len = posix.recvfrom(self.fd, &buf, 0, &newAddr.any, &newAddrLen) catch |err| {
                std.debug.print("Ошибка recvfrom: {}\n", .{err});
                continue;
            };

            const data = buf[0..len];
            if (std.mem.eql(u8, data, "PING")) {
                self.handlePing(allocator, newAddr) catch |err| {
                    std.debug.print("Не удалось обработать пинг: {}\n", .{err});
                    continue;
                };
            }
        }
    }

    pub fn timeoutWorker(self: *Self, wg: *std.Thread.WaitGroup) void {
        defer wg.finish();

        while (true) {
            std.Thread.sleep(1 * std.time.ns_per_s);

            self.mutex.lock();
            defer self.mutex.unlock();

            const now = std.time.milliTimestamp();
            const timeout: i64 = 5000;

            var i: usize = self.conns.items.len;
            while (i > 0) {
                i -= 1;
                const conn = &self.conns.items[i];

                if (now - conn.lastSeen > timeout) {
                    std.debug.print("Клиент {} умер(timeout)\n", .{i});
                    _ = self.conns.swapRemove(i);
                }
            }
        }
    }
    fn handlePing(self: *Self, allocator: std.mem.Allocator, addr: std.net.Address) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        for (self.conns.items, 0..) |*conn, i| {
            if (conn.address.eql(addr)) {
                conn.lastSeen = std.time.milliTimestamp();
                std.debug.print("Клиент обновлен по индексу {}\n", .{i});

                return;
            }
        }

        try self.conns.append(allocator, .{
            .address = addr,
            .lastSeen = std.time.milliTimestamp(),
        });
    }
};
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = try Server.init(allocator, "0.0.0.0", 8080);
    defer server.deinit(allocator);

    var wg = std.Thread.WaitGroup{};

    wg.start();
    const thread = try std.Thread.spawn(.{}, Server.timeoutWorker, .{ &server, &wg });
    thread.detach();

    server.run(allocator);
    wg.wait();
}
