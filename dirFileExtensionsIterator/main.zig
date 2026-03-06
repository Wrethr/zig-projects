const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cwd = std.fs.cwd();
    var workerDir = try createDir(cwd, "my_project");
    defer cwd.deleteTree("my_project") catch unreachable;
    defer workerDir.close();

    // file examples
    _ = try workerDir.createFile("main.zig", .{});
    _ = try workerDir.createFile("utils.zig", .{});
    _ = try workerDir.createFile("index.html", .{});
    _ = try workerDir.createFile("style.css", .{});
    _ = try workerDir.createFile("data.json", .{});
    _ = try workerDir.createFile("readme.md", .{});

    var files = std.StringHashMap(usize).init(allocator);
    defer {
        var keyIter = files.iterator();
        while (keyIter.next()) |file| {
            allocator.free(file.key_ptr.*);
        }
        files.deinit();
    }
    var workerDirIterator = workerDir.iterate();
    while (try workerDirIterator.next()) |file| {
        const filename = file.name;
        var filenameBackIterator = std.mem.splitBackwardsScalar(u8, filename, '.');
        const extension = filenameBackIterator.next().?;

        const entry = try files.getOrPut(extension);
        if (entry.found_existing) {
            entry.value_ptr.* += 1;
        } else {
            entry.key_ptr.* = try allocator.dupe(u8, extension);
            entry.value_ptr.* = 1;
        }
    }

    var fileExtensionsIterator = files.iterator();
    while (fileExtensionsIterator.next()) |entry| {
        std.debug.print("{s} => {d}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
    }
}

fn createDir(cwd: std.fs.Dir, path: []const u8) !std.fs.Dir {
    try cwd.makeDir(path);
    return cwd.openDir(path, .{ .iterate = true });
}
