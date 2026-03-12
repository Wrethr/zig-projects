const std = @import("std");

const ThreadSafeFlag = struct {
    atomic: std.atomic.Value(bool),

    const Self = @This();

    pub fn init() Self {
        return .{ .atomic = std.atomic.Value(bool).init(false) };
    }

    pub fn set(self: *Self, boolean: bool) void {
        self.atomic.store(boolean, .seq_cst);
    }
    pub fn isSet(self: *const Self) bool {
        return self.atomic.load(.seq_cst);
    }
    pub fn isSetRaw(self: Self) std.atomic.Value(bool) {
        return self.atomic;
    }
    pub fn reset(self: *Self) void {
        self.atomic.store(false, .seq_cst);
    }
};

const SpinLock = struct {
    locked: std.atomic.Value(bool),

    const Self = @This();

    pub fn init() Self {
        return .{
            .locked = std.atomic.Value(bool).init(false),
        };
    }
    pub fn lock(self: *Self) void {
        while (self.locked.swap(true, .seq_cst) == true) {}
    }
    pub fn unlock(self: *Self) void {
        self.locked.store(false, .seq_cst);
    }
};

pub fn main() !void {
    var spinLock = SpinLock.init();
    var counter: usize = 0;
    var flag = ThreadSafeFlag.init();
    var wg = std.Thread.WaitGroup{};

    wg.start();
    var thread1 = try std.Thread.spawn(.{}, worker2, .{ &flag, &wg });
    thread1.detach();

    wg.start();
    var thread2 = try std.Thread.spawn(.{}, worker1, .{ &flag, &wg });
    thread2.detach();

    std.debug.print("End main: THread safe flag\n", .{});

    wg.start();
    var thread3 = try std.Thread.spawn(.{}, workerinc, .{ &spinLock, &wg, &counter });
    thread3.detach();

    wg.start();
    var thread4 = try std.Thread.spawn(.{}, workerinc, .{ &spinLock, &wg, &counter });
    thread4.detach();

    wg.wait();

    std.debug.print("counter: {}\n", .{counter});
    std.debug.print("end of main\n", .{});
}

fn workerinc(spinlock: *SpinLock, wg: *std.Thread.WaitGroup, counter: *usize) void {
    defer wg.finish();

    var i: usize = 0;
    while (i < 100_000) : (i += 1) {
        spinlock.lock();
        counter.* += 1;
        spinlock.unlock();
    }
}

fn worker1(flag: *ThreadSafeFlag, wg: *std.Thread.WaitGroup) void {
    defer wg.finish();

    var i: usize = 0;
    while (true) : (i += 1) {
        std.Thread.sleep(500 * std.time.ms_per_s);

        if (!flag.isSet()) {
            break;
        }
        std.debug.print("iteration {d}\n", .{i});
    }
}

fn worker2(flag: *ThreadSafeFlag, wg: *std.Thread.WaitGroup) void {
    defer wg.finish();

    flag.set(true);
    std.Thread.sleep(2000 * std.time.ms_per_s);
    flag.set(false);
}
