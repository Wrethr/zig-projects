const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cwd = try openCurrentDirWithIterablePerm();

    var extensions = std.StringHashMap(usize).init(allocator);
    defer {
        var extNameIterator = extensions.iterator();
        while (extNameIterator.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }

        extensions.deinit();
    }

    var dirIterator = cwd.iterate();
    while (try dirIterator.next()) |entry| {
        const ext = std.fs.path.extension(entry.name);
        if (std.mem.eql(u8, ext, "")) continue;

        const hashItem = try extensions.getOrPut(ext[1..]);
        if (hashItem.found_existing) {
            hashItem.value_ptr.* += 1;
        } else {
            hashItem.key_ptr.* = try allocator.dupe(u8, ext[1..]);
            hashItem.value_ptr.* = 1;
        }
    }

    var hashMapIterator = extensions.iterator();
    while (hashMapIterator.next()) |entry| {
        std.debug.print("{s} => {d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}

// на Линукс .BADF: Не разрешает итерировать текущую папку
fn openCurrentDirWithIterablePerm() !std.fs.Dir {
    const cwd = std.fs.cwd();
    return cwd.openDir(".", .{ .iterate = true });
}
