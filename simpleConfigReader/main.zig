const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <filename>\n", .{args[0]});
        return;
    }

    const filename = args[1];
    var config = try getConfig(allocator, filename);
    defer config.deinit(allocator);

    std.debug.print("username: {s}\nport: {d}\nmode: {s}\n", .{
        config.username.?,
        config.port.?,
        config.mode.?,
    });
}

const Config = struct {
    username: ?[]u8 = null,
    port: ?u16 = 0,
    mode: ?[]u8 = null,

    fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.username) |ptr| allocator.free(ptr);
        if (self.mode) |ptr| allocator.free(ptr);
    }
};

fn getConfig(allocator: std.mem.Allocator, filename: []const u8) !Config {
    try lastNENdscapeSeqCheck(filename);

    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buffer: [1024]u8 = undefined;

    var readerContext = file.reader(&buffer);
    const reader = &readerContext.interface;

    var config = Config{};

    while (true) {
        const line = reader.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

        const trimmed = std.mem.trim(u8, line, " \n\t");

        if (std.mem.indexOf(u8, trimmed, "=")) |index| {
            const key = std.mem.trim(u8, trimmed[0..index], " \t\r");
            const value = std.mem.trim(u8, trimmed[index + 1 ..], " \t\r");

            if (std.mem.eql(u8, key, "username")) {
                config.username = try allocator.dupe(u8, value);
            } else if (std.mem.eql(u8, key, "port")) {
                config.port = try std.fmt.parseInt(u16, value, 0);
            } else if (std.mem.eql(u8, key, "mode")) {
                config.mode = try allocator.dupe(u8, value);
            }
        }
    }

    return config;
}

fn lastNENdscapeSeqCheck(filename: []const u8) !void {
    const filewr = try std.fs.cwd().openFile(filename, .{ .mode = .read_write });
    defer filewr.close();

    const size = try filewr.getEndPos();
    if (size == 0) return;

    try filewr.seekTo(size - 1);

    var bytebuf: [1]u8 = undefined;
    const sz = try filewr.read(&bytebuf);

    if (sz > 0 and bytebuf[0] != '\n') {
        try filewr.seekFromEnd(0);
        try filewr.writeAll("\n");
    }
}
