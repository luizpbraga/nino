const std = @import("std");
const stdout = std.io.getStdOut();
const keys = @import("keys.zig");
const Key = keys.Key;
const Editor = @import("Editor.zig");
const io = @import("io.zig");
const readKey = io.readKey;

const Prompt = @This();

const Status = struct {
    msg: [1000]u8 = undefined,
    time: i64 = 0,

    pub fn new(comptime fmt: []const u8, args: anytype) !Status {
        var s: Status = .{};
        _ = try std.fmt.bufPrint(&s.msg, fmt, args);
        s.time = std.time.timestamp();
        return s;
    }
};

ccouter: usize = 0,
cursor: struct { x: usize = 0, y: usize = 0 } = .{},
alloc: std.mem.Allocator,
msg_buffer: std.ArrayList(u8),
// cmd_buffer: std.ArrayList(u8),
cmds: std.ArrayList([]const u8),
status: Status = .{},

pub fn init(alloc: std.mem.Allocator) @This() {
    return .{
        .alloc = alloc,
        .cmds = .init(alloc),
        .msg_buffer = .init(alloc),
        // .cmd_buffer = .init(alloc),
    };
}

pub fn deinit(p: *Prompt) void {
    p.msg_buffer.deinit();
    // p.cmd_buffer.deinit();
    for (p.cmds.items) |cmd| p.alloc.free(cmd);
    p.cmds.deinit();
}

pub fn setStatusMsg(p: *Prompt, comptime fmt: []const u8, args: anytype) !void {
    if (fmt.len != 0) p.status = try Status.new(fmt, args);
    p.msg_buffer.clearAndFree();
    const msg = p.status.msg;

    try p.msg_buffer.writer().print("\x1b[{};{}H\x1b[K", .{ p.cursor.y, p.cursor.x + 1 });

    if (std.time.timestamp() - p.status.time < 4) {
        try p.msg_buffer.appendSlice(&msg);
        Editor.STATUSBAR += std.mem.count(u8, &msg, "\n");
    } else {
        Editor.STATUSBAR = 2;
    }

    try stdout.writeAll(p.msg_buffer.items);
}

pub fn drawCommandLine(p: *Prompt, cmd: []const u8) !void {
    p.msg_buffer.clearAndFree();
    // try p.msg_buffer.writer().print("\x1b[{};{}H{s} {}\x1b[K", .{ p.cursor.y, p.cursor.x + 1, cmd, p.cursor.x });
    try p.msg_buffer.writer().print("{s}\x1b[{};{}H", .{ cmd, p.cursor.y, p.cursor.x + 1 });
    try stdout.writeAll(p.msg_buffer.items);
}

/// displays a prompt and lets the user input a line
pub fn capture(p: *Prompt) !?[]const u8 {
    var input: std.ArrayList(u8) = .init(p.alloc);
    errdefer input.deinit();

    try input.writer().print("\x1b[{};{}H:\x1b[K", .{ p.cursor.y, p.cursor.x + 1 });
    const start = input.items.len;

    const cur = p.cursor;
    defer p.cursor = cur;
    // jump ":"
    p.cursor.x += 1;

    while (true) {
        try p.drawCommandLine(input.items);

        switch (try readKey()) {
            // ESC
            '\x1b' => {
                input.deinit();
                try stdout.writeAll("\x1b[2K");
                return null;
            },

            127 => {
                if (input.items.len > start) {
                    _ = input.pop();
                    p.cursor.x -= 1;
                }
            },

            '\r' => if (input.items.len > start) {
                const cmd = try input.toOwnedSlice();
                try p.cmds.append(cmd);
                return cmd[start..];
            },

            @intFromEnum(Key.ARROW_LEFT) => if (p.cursor.x != 1) {
                p.cursor.x -= 1;
            },

            @intFromEnum(Key.ARROW_UP) => {
                if (p.cmds.items.len != 0) {
                    if (input.items.len > start) {
                        input.clearAndFree();
                        try input.writer().print("\x1b[{};{}H:\x1b[K", .{ cur.y, cur.x + 1 });
                    }
                    const cmd = p.cmds.items[p.ccouter];
                    try input.appendSlice(cmd[start..]);
                    p.ccouter += 1;
                    if (p.ccouter == p.cmds.items.len) p.ccouter = 0;
                    p.cursor.x = input.items.len - start + 1;
                }
            },

            @intFromEnum(Key.ARROW_RIGHT) => if (p.cursor.x + start <= input.items.len) {
                p.cursor.x += 1;
            },

            else => |c| if (c >= 0 and c < 128) {
                try input.insert(start + p.cursor.x - 1, @intCast(c));
                p.cursor.x += 1;
            },
        }
    }
}
