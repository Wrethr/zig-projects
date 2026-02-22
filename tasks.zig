const std = @import("std");

const Task = struct {
    task: []u8,
    done: bool
};

fn getTasks(allocator: std.mem.Allocator, reader: anytype) !std.ArrayList(Task) {
    var content = try std.ArrayList(Task).initCapacity(allocator, 5);
    while (true) {
        const raw = reader.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err
        };
        const trimmed = std.mem.trim(u8, raw, "\r\n \t");

        const taskText = try allocator.dupe(u8, trimmed);
        try content.append(allocator, .{.task = taskText, .done = false});
    }

    return content;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const file = try std.fs.cwd().openFile("tasklist.txt", .{ .mode = .read_write });
    defer file.close();

    var read_buf: [4096]u8 = undefined;
    var readerWrapper = file.reader(&read_buf);
    const reader = &readerWrapper.interface;


    var tasks = try getTasks(allocator, reader);
    defer tasks.deinit(allocator);
    defer for (tasks.items) |item| {
        allocator.free(item.task);
    };

    for (tasks.items) |item| {
        std.debug.print("item: {s}, done: {}\n", .{item.task, item.done});
    }

    // TODO:
    // 1. Спросить пользователя, что он хочет сделать: Перезаписать фрагмент(конкретно какая заметка по счету), Добавить новую заметку, удалить старую заметку, показать заметки
    // 2. Создать функции: createNewNote, deleteNote, rewriteNote, viewNotes
}
