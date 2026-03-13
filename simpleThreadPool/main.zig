const std = @import("std");

const Work = *const fn () void;
const ThreadPool = struct {
    workerPool: std.ArrayList(std.Thread),
    workPool: std.ArrayList(Work),
    mtx: std.Thread.Mutex,
    cond: std.Thread.Condition,
    isRunning: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return .{
            .workerPool = try .initCapacity(allocator, 4),
            .workPool = try .initCapacity(allocator, 4),
            .mtx = .{},
            .cond = .{},
            .isRunning = false,
        };
    }
    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        self.mtx.lock();
        self.isRunning = false;
        self.mtx.unlock();

        self.cond.broadcast();

        for (self.workerPool.items) |*item| {
            item.join();
        }

        self.workPool.deinit(allocator);
        self.workerPool.deinit(allocator);
    }

    fn worker(self: *Self) void {
        while (true) {
            self.mtx.lock();
            while (self.isRunning and self.workPool.items.len == 0) self.cond.wait(&self.mtx);

            if (!self.isRunning) {
                self.mtx.unlock();
                break;
            }

            const work = self.workPool.orderedRemove(0);
            self.mtx.unlock();

            work();
        }
    }

    pub fn start(self: *Self, allocator: std.mem.Allocator, count: usize) !void {
        self.isRunning = true;

        var i: usize = 0;
        while (i < count) : (i += 1) {
            const thread = try std.Thread.spawn(.{}, worker, .{self});
            try self.workerPool.append(allocator, thread);
        }
    }

    pub fn submit(self: *Self, allocator: std.mem.Allocator, work: Work) !void {
        self.mtx.lock();
        try self.workPool.append(allocator, work);
        self.mtx.unlock();

        self.cond.signal();
    }
};

// Всевышний написал
fn myJob() void {
    std.debug.print("Job done by thread {}\n", .{std.Thread.getCurrentId()});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var pool = try ThreadPool.init(allocator);
    defer pool.deinit(allocator);

    try pool.start(allocator, 4);

    var i: usize = 0;
    while (i < 5) : (i += 1) {
        try pool.submit(allocator, myJob);
    }

    std.Thread.sleep(1 * std.time.ns_per_s);
}
