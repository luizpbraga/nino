const std = @import("std");
const stdin = std.io.getStdIn();
const stdout = std.io.getStdOut();
const Editor = @import("Editor.zig");
const keys = @import("keys.zig");
const Key = keys.Key;

/// wait for one keypress, and return it.
pub fn readKey() !usize {
    var buff: [1]u8 = .{'0'};

    while (try stdin.read(&buff) != 1) {}

    if (buff[0] != '\x1b') return buff[0];

    // escape sequence buffer
    var seq: [5]u8 = undefined;
    @memset(&seq, 0);

    if (try stdin.read(seq[0..1]) != 1) return '\x1b';
    if (try stdin.read(seq[1..2]) != 1) return '\x1b';

    // NOT PAGE_{UP, DOWN} or ARROW_{UP, DOWN, ...}, MOUSE
    if (seq[0] == '[') {
        // PAGE_UP AND DOWN
        // page Up is sent as <esc>[5~ and Page Down is sent as <esc>[6~.
        if (seq[1] >= '0' and seq[1] <= '9') {
            if (try stdin.read(seq[2..3]) != 1) return '\x1b';
            if (seq[2] == '~') switch (seq[1]) {
                '1', '7' => return @intFromEnum(Key.HOME),
                '4', '8' => return @intFromEnum(Key.END),
                '3' => return @intFromEnum(Key.DEL),
                '5' => return @intFromEnum(Key.PAGE_UP),
                '6' => return @intFromEnum(Key.PAGE_DOWN),
                else => {},
            };
        }

        // ARROW KEYS
        // '\x1b' + '[' + ('A', 'B', 'C', or 'D')
        switch (seq[1]) {
            '1', '7' => return @intFromEnum(Key.HOME),
            '4', '8' => return @intFromEnum(Key.END),
            'A' => return @intFromEnum(Key.ARROW_UP),
            'B' => return @intFromEnum(Key.ARROW_DOWN),
            'C' => return @intFromEnum(Key.ARROW_RIGHT),
            'D' => return @intFromEnum(Key.ARROW_LEFT),
            'H' => return @intFromEnum(Key.HOME),
            'F' => return @intFromEnum(Key.END),
            // MOUSE
            'M' => {
                if (!Editor.SETMOUSE) return '\x1b';

                if (try stdin.read(seq[2..3]) != 1) return '\x1b';

                const button = seq[2] - 32;
                // scrool up
                if (button == 64) return @intFromEnum(Key.ARROW_UP);
                // scrool down
                if (button == 65) return @intFromEnum(Key.ARROW_DOWN);
                // mouse Coordinates
                if (try stdin.read(seq[3..4]) != 1) return '\x1b';
                if (try stdin.read(seq[4..5]) != 1) return '\x1b';
                // left button
                if (button == 0) {
                    const x = seq[3] - 32;
                    const y = seq[4] - 32;
                    // TODO: use unions
                    Editor.MOUSECOORD = .{ .x = x, .y = y };
                    return @intFromEnum(Key.MOUSE);
                }

                return '\x1b';
            },
            else => {},
        }
    }

    if (seq[0] == '0') switch (seq[1]) {
        'H' => return @intFromEnum(Key.HOME),
        'F' => return @intFromEnum(Key.END),
        else => {},
    };

    return '\x1b';
}

/// read the file rows
pub fn open(e: *Editor, file_name: []const u8) !void {
    const cwd = std.fs.cwd();
    var file = cwd.openFile(file_name, .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => try cwd.createFile(file_name, .{}),
        else => return err,
    };
    defer file.close();

    // BUG:
    var buf: [1024]u8 = undefined;
    while (true) {
        // TODO: fix this issue
        // const line = try e.flog.?.reader().readUntilDelimiterOrEofAlloc(e.alloc, '\n', 100000) orelse break;
        const line = try file.reader().readUntilDelimiterOrEof(&buf, '\n') orelse break;
        try e.insertRow(e.numOfRows(), line);
    }

    e.file_name = file_name;
    e.file_status = 0;
}

pub fn save(e: *Editor) !void {
    defer e.mode = .insert;

    const cwd = std.fs.cwd();
    cwd.deleteFile(e.file_name) catch {};
    var file = cwd.createFile(e.file_name, .{}) catch |err| switch (err) {
        error.FileNotFound,
        error.PathAlreadyExists,
        => try cwd.openFile(e.file_name, .{ .mode = .write_only }),
        else => return err,
    };
    defer file.close();

    const rows = try e.toString();
    defer e.alloc.free(rows);

    try file.writeAll(rows);

    e.file_status = 0;

    try e.setStatusMsg("\"{s}\" {}L, {}B written", .{ e.file_name, e.numOfRows(), rows.len });
}

pub fn exit() !void {
    try stdout.writeAll("\x1b[2J\x1b[H");
}

pub fn fileExists(name: []const u8) bool {
    _ = std.fs.cwd().statFile(name) catch {
        return false;
    };
    return true;
}

pub fn enableMouse() !void {
    try stdout.writeAll("\x1b[?1003h");
}

pub fn disableMouse() !void {
    try stdout.writeAll("\x1b[?1003l");
}
