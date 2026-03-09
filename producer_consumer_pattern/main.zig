const std = @import("std");

pub fn main() !void {
    var buffer: [1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    var list = try std.ArrayList(u16).initCapacity(allocator, 1);
    defer list.deinit(allocator);

    var wg = std.Thread.WaitGroup{};
    var mtx = std.Thread.Mutex{};
    var cond = std.Thread.Condition{};

    var finish = false;

    wg.start();
    var threadWriter = try std.Thread.spawn(.{}, writer, .{ allocator, &wg, &mtx, &cond, &list, &finish });
    threadWriter.detach();

    wg.start();
    var threadReader = try std.Thread.spawn(.{}, reader, .{ &wg, &mtx, &cond, &list, &finish });
    threadReader.detach();

    wg.wait();
    std.debug.print("End of program\n", .{});
}

fn writer(allocator: std.mem.Allocator, wg: *std.Thread.WaitGroup, mtx: *std.Thread.Mutex, cond: *std.Thread.Condition, list: *std.ArrayList(u16), finish: *bool) void {
    defer wg.finish();

    var i: usize = 0;
    while (i < 20) : (i += 1) {
        mtx.lock();
        list.append(allocator, @as(u16, @intCast(i)) * 10) catch return;
        mtx.unlock();

        cond.signal();
    }

    mtx.lock();
    finish.* = true;
    mtx.unlock();
    cond.signal();
}

fn reader(wg: *std.Thread.WaitGroup, mtx: *std.Thread.Mutex, cond: *std.Thread.Condition, list: *std.ArrayList(u16), finish: *bool) void {
    defer wg.finish();

    var currentPosition: usize = 0;

    while (true) {
        mtx.lock();
        defer mtx.unlock();
        while (list.items.len - currentPosition < 5 and !finish.*) {
            cond.wait(mtx);
        }

        if (finish.* and currentPosition == list.items.len) {
            break;
        }

        std.debug.print("five of portion: ", .{});
        var j: usize = 0;
        while (j < 5) : (j += 1) {
            std.debug.print("{d} => {d}\n", .{ currentPosition, list.items[currentPosition] });
            currentPosition += 1;
        }
    }
}
