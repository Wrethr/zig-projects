const std = @import("std");
const libconn = @import("libsimpleconn.zig");

const MultiThreadingContext = struct {
    wg: std.Thread.WaitGroup,
    mtx: std.Thread.Mutex,

    const Self = @This();

    pub fn init() Self {
        return .{
            .wg = .{},
            .mtx = .{},
        };
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var clientList = try std.ArrayList(libconn.Client).initCapacity(allocator, 4);
    defer clientList.deinit(allocator);

    const address = try std.net.Address.parseIp("0.0.0.0", 8080);

    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    var ctx: MultiThreadingContext = .init();

    var id: usize = 0;
    while (true) : (id += 1) {
        const conn = try server.accept();

        ctx.wg.start();
        var thread = try std.Thread.spawn(.{}, clientWorker, .{ allocator, &ctx, conn, id, &clientList });
        thread.detach();
    }
}

fn clientWorker(allocator: std.mem.Allocator, ctx: *MultiThreadingContext, conn: std.net.Server.Connection, id: usize, clientList: *std.ArrayList(libconn.Client)) void {
    const clientName = std.fmt.allocPrint(allocator, "Client {d}", .{id}) catch |err| {
        std.debug.print("Ошибка аллокации имени: {}\n", .{err});
        return;
    };

    ctx.mtx.lock();

    const connection = libconn.Client.createClient(allocator, clientName, conn) catch |err| {
        std.debug.print("Ошибка создания клиента: {}\n", .{err});
        allocator.free(clientName);
        ctx.mtx.unlock();
        return;
    };
    allocator.free(clientName);

    clientList.append(allocator, connection) catch |err| {
        std.debug.print("Ошибка добавления клиента в лист: {}\n", .{err});
        ctx.mtx.unlock();
        return;
    };
    ctx.mtx.unlock();

    defer {
        ctx.mtx.lock();
        for (clientList.items, 0..) |*client, i| {
            if (client.conn.stream.handle == conn.stream.handle) {
                client.deinit(allocator);
                _ = clientList.swapRemove(i);
                break;
            }
        }
        ctx.mtx.unlock();

        ctx.wg.finish();
    }

    var readerBuffer: [1024]u8 = undefined;

    var readerContext = conn.stream.reader(&readerBuffer);

    const reader = readerContext.interface();

    var senderName: []const u8 = undefined;
    for (clientList.items) |c| {
        if (c.conn.stream.handle == conn.stream.handle) {
            senderName = c.name;
            break;
        }
    }

    while (true) {
        const recvMessage = libconn.recv(allocator, reader) catch |err| {
            std.debug.print("Ошибка получения строки: {}\n", .{err});
            return;
        };
        defer allocator.free(recvMessage);

        ctx.mtx.lock();
        defer ctx.mtx.unlock();
        for (clientList.items) |client| {
            if (client.conn.stream.handle == conn.stream.handle) continue;

            const sendMessage = std.fmt.allocPrint(allocator, "{s}: {s}", .{ senderName, recvMessage }) catch |err| {
                std.debug.print("Ошибка формирования sendMessage: {}\n", .{err});
                return;
            };
            defer allocator.free(sendMessage);
            libconn.sendRaw(client, sendMessage) catch |err| {
                std.debug.print("Ошибка отправления данных клиенту {s}: {}\n", .{ senderName, err });
                continue;
            };
        }
    }
}
