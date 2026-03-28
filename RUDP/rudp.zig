const std = @import("std");

pub const PacketType = enum(u8) {
    data, // простые данные
    ack, // информация, что клиент подключился
    ping, // проверка связи, от клиента к серверу
    pong, // подтверждение: проверка связи, от сервера к клиенту
};
pub const Flag = packed struct(u8) {
    reliable: bool,
    compressed: bool,
    encrypted: bool,
    reserved: u6,
};

pub const Header = packed struct {
    type: PacketType,
    flag: Flag,
    packetId: u16,

    const Self = @This();

    var lastId: u16 = 0;
    fn updateLastId() u16 {
        lastId += 1;
        return lastId - 1;
    }

    pub fn init(typ: PacketType, flag: Flag) Self {
        return .{
            .type = typ,
            .flag = flag,
            .packetId = updateLastId(),
        };
    }
};
pub const Packet = struct {
    header: Header,
    data: []u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, header: Header, data: []u8) !Self {
        return .{
            .header = header,
            .data = try allocator.dupe(u8, data),
        };
    }
    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        allocator.free(self.data);
    }
};

pub fn serializePacketAlloc(allocator: std.mem.Allocator, packet: Packet) ![]const u8 {
    const buffer: []u8 = try allocator.alloc(u8, packet.data.len + @sizeOf(Header));
    _ = serializePacketToBuffer(buffer, packet);

    return buffer;
}
pub fn serializePacketToBuffer(buffer: []u8, packet: Packet) usize {
    @memcpy(buffer[0..@sizeOf(Header)], std.mem.asBytes(&packet.header));
    @memcpy(buffer[@sizeOf(Header)..], packet.data);

    return @sizeOf(Header) + packet.data.len;
}

pub fn deserializeFromBuffer(allocator: std.mem.Allocator, buffer: []const u8) !Packet {
    if (buffer.len < @sizeOf(Header)) return error.InvalidPacket;

    const header = std.mem.bytesAsValue(Header, buffer[0..@sizeOf(Header)]).*;
    const data = buffer[@sizeOf(Header)..];

    return try .init(allocator, header, data);
}

pub fn recvFromPacket(fd: std.posix.socket_t, address: *std.net.Address, addressLen: *std.posix.socklen_t, buffer: []u8) !usize {
    return try std.posix.recvfrom(fd, buffer, 0, &address.any, addressLen);
}

pub fn sendToPacket(allocator: std.mem.Allocator, fd: std.posix.socket_t, address: *std.net.Address, packet: Packet) !void {
    const sendBuf = try serializePacketAlloc(allocator, packet);
    defer allocator.free(sendBuf);

    _ = try std.posix.sendto(fd, sendBuf, 0, &address.any, @sizeOf(std.net.Address));

    var ackBuf: [1024]u8 = undefined;
    var ackAddr: std.net.Address = undefined;
    var ackAddrLen: std.posix.socklen_t = @sizeOf(std.net.Address);

    while (true) {
        const len = try recvFromPacket(fd, &ackAddr, &ackAddrLen, &ackBuf);
        const recvPacket = try deserializeFromBuffer(allocator, ackBuf[0..len]);
        defer recvPacket.deinit(allocator);

        if (recvPacket.header.type == .ack and recvPacket.header.packetId == packet.header.packetId) {
            return;
        }
    }
}

pub fn sendTo(allocator: std.mem.Allocator, fd: std.posix.socket_t, address: *std.net.Address, bytes: []const u8) !void {
    const header = Header.init(.data, .{ .reliable = true });
    const packet = try Packet.init(allocator, header, bytes);
    defer packet.deinit(allocator);

    try sendToPacket(allocator, fd, address, packet);
}

pub fn recvFrom(allocator: std.mem.Allocator, fd: std.posix.socket_t, address: *std.net.Address, buffer: []u8) !usize {
    var tempBuf: [1024]u8 = undefined;
    var addrLen: std.posix.socklen_t = @sizeOf(std.net.Address);

    const len = try recvFromPacket(fd, address, &addrLen, &tempBuf);
    const packet = try deserializeFromBuffer(allocator, tempBuf[0..len]);
    defer packet.deinit(allocator);

    if (packet.header.flag.reliable) {
        var ackHeader = Header.init(.ack, .{});
        ackHeader.packetId = packet.header.packetId;
        const ackPacket = try Packet.init(allocator, ackHeader, &.{});
        defer ackPacket.deinit(allocator);

        const ackBuf = try serializePacketAlloc(allocator, ackPacket);
        defer allocator.free(ackBuf);

        _ = try std.posix.sendto(fd, ackBuf, 0, &address.any, addrLen);
    }

    @memcpy(buffer[0..packet.data.len], packet.data);
    return packet.data.len;
}
