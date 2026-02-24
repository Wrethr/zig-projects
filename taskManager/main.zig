const std = @import("std");

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

    var stdoutBuffer: [512]u8 = undefined;
    const stdoutFd = std.fs.File.stdout();
    var stdoutWriterContext = stdoutFd.writer(&stdoutBuffer);
    const stdoutWriter = &stdoutWriterContext.interface;

    const stdinBuffer = try allocator.alloc(u8, 64);
    defer allocator.free(stdinBuffer);

    const stdinFd = std.fs.File.stdin();
    var stdinReaderContext = stdinFd.reader(stdinBuffer);
    const stdinReader = &stdinReaderContext.interface;

    try handler(allocator, &tasks, &file, stdoutWriter, stdinReader);
}

fn handler(allocator: std.mem.Allocator, arrayList: *std.ArrayList(Task), file: *const std.fs.File, stdout: *std.Io.Writer, stdin: *std.Io.Reader) !void {
    while (true) {
        try printMenu(stdout);

        const userChoice = try getNumber(stdin, u8, 10);

        switch (userChoice) {
            1 => try createNewNote(allocator, arrayList, stdout, stdin),
            2 => try deleteNote(allocator, arrayList, stdout, stdin),
            3 => try rewriteNote(allocator, arrayList, stdout, stdin),
            4 => try viewNotes(arrayList, stdout),
            5 => {
                try exit(allocator, arrayList, file);
                try stdout.print("Bye!\n", .{});
                break;
            },

            else => {
                try stdout.print("It's wrong number. Please, write right number.\n", .{});
                try stdout.flush();
            }
        }
    }
}

const Task = struct {
    task: []u8
};
const NoteErrors = error {
    canNotDeleteNote,
    canNotRewriteNote
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
        try content.append(allocator, .{.task = taskText});
    }

    return content;
}

fn printMenu(writer: anytype) !void {
    try writer.print("================MENU================\n", .{});
    try writer.print("What do you want:\n", .{});
    try writer.print("1. Create new note\n", .{});
    try writer.print("2. Delete note[index]\n", .{});
    try writer.print("3. Rewrite note[index]\n", .{});
    try writer.print("4. View all notes\n", .{});
    try writer.print("5. Exit\n", .{});
    try writer.print("================MENU================\n\n", .{});

    try writer.print(">>> ", .{});
    try writer.flush();
}


fn getNumber(reader: anytype, T: type, base: u8) !T {
    const userChoiceString = try reader.takeDelimiterInclusive('\n');
    const trimmedUserChoiceString = std.mem.trim(u8, userChoiceString, "\r\n \t");

    return try std.fmt.parseInt(T, trimmedUserChoiceString, base);
}

fn getString(allocator: std.mem.Allocator, writer: anytype, reader: anytype) ![]u8 {
    try writer.print("Write new note: ", .{});
    try writer.flush();

    const userInput = try reader.takeDelimiterInclusive('\n');
    const trimmedInput = std.mem.trim(u8, userInput, "\r\n\t ");

    return try allocator.dupe(u8, trimmedInput);
}

fn viewNotes(arrayList: *std.ArrayList(Task), writer: anytype) !void {
    for (arrayList.items, 0..) |item, index| {
        try writer.print("{d} => Note[{s}]: {s}\n", .{index, item.task});
    }
    try writer.flush();
}


fn createNewNote(allocator: std.mem.Allocator, arrayList: *std.ArrayList(Task), writer: anytype, reader: anytype) !void {
    try arrayList.append(allocator, .{ .task = try getString(allocator, writer, reader) });
}

fn deleteNote(allocator: std.mem.Allocator, arrayList: *std.ArrayList(Task), writer: anytype, reader: anytype) !void {
    try writer.print("What is note do you want to delete: ", .{});
    try writer.flush();
    const index = try getNumber(reader, usize, 10);

    if (index < arrayList.items.len) {
        const item = arrayList.items[index];
        allocator.free(item.task);

        _ = arrayList.swapRemove(index);
        try writer.print("Note deleted\n", .{});
    } else {
        return NoteErrors.canNotDeleteNote;
    }
}

fn rewriteNote(allocator: std.mem.Allocator, arrayList: *std.ArrayList(Task), writer: anytype, reader: anytype) !void {
    try writer.print("What is note do you want to rewrite: ", .{});
    try writer.flush();

    const index = try getNumber(reader, usize, 10);

    if (index < arrayList.items.len) {
        var item = &arrayList.items[index];

        const newString = try getString(allocator, writer, reader);

        allocator.free(item.task);

        item.task = newString;
    } else {
        return NoteErrors.canNotRewriteNote;
    }
}

fn exit(allocator: std.mem.Allocator, arrayList: *std.ArrayList(Task), file: *const std.fs.File) !void {
    try file.setEndPos(0);
    try file.seekTo(0);

    const fileWriterBuffer = try allocator.alloc(u8, 4096);
    defer allocator.free(fileWriterBuffer);

    var fileWriterContext = file.writer(fileWriterBuffer);
    const fileWriter = &fileWriterContext.interface;

    for (arrayList.items) |item| {
        try fileWriter.print("{s}\n", .{item.task});
    }

    try fileWriter.flush();
}
