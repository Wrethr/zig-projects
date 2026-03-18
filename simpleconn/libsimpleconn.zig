const std = @import("std");

pub const Client = struct {
    name: []const u8,
    conn: std.net.Server.Connection,

    const Self = @This();

    pub fn createClient(allocator: std.mem.Allocator, name: []const u8, conn: std.net.Server.Connection) !Self {
        return .{
            .name = try allocator.dupe(u8, name),
            .conn = conn,
        };
    }
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.conn.stream.close();
    }
};

pub const Message = struct {
    message: []const u8,
    writed: usize,

    const Self = @This();

    pub fn create(message: []const u8, writed: usize) Self {
        return .{ .message = message, .writed = writed };
    }
};

pub fn send(writer: *std.Io.Writer, message: []const u8) !void {
    try writer.writeInt(u32, @as(u32, @intCast(message.len)), .big);

    _ = try writer.writeAll(message);
    try writer.flush();
}

pub fn sendRaw(conn: Client, message: []const u8) !void {
    const stream = conn.conn.stream;

    var lenBuf: [4]u8 = undefined;
    std.mem.writeInt(u32, &lenBuf, @as(u32, @intCast(message.len)), .big);
    try stream.writeAll(&lenBuf);
    try stream.writeAll(message);
}

pub fn recv(allocator: std.mem.Allocator, reader: *std.Io.Reader) ![]u8 {
    const size = try reader.takeInt(u32, .big);
    if (size > 1024) return error.PackageTooBig;

    return try allocator.dupe(u8, try reader.take(size));
}
