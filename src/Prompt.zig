const std = @import("std");
const stdout = std.io.getStdOut();
const keys = @import("keys.zig");
const Key = keys.Key;
const Editor = @import("Editor.zig");
const io = @import("io.zig");
const readKey = io.readKey;

const Prompt = @This();

const Status = struct {
    msg: [1024]u8 = undefined,
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
screen: struct { x: usize = 0, y: usize = 0 } = .{},
alloc: std.mem.Allocator,
msg_buffer: std.ArrayList(u8),
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
    if (fmt.len != 0) {
        DRAW = true;
        p.status = try Status.new(fmt, args);
        const x = std.mem.count(u8, &p.status.msg, "\n");
        if (x == 0 or x < Editor.STATUSBAR) return;
        Editor.STATUSBAR += x;
    }
}

fn screenY(p: *Prompt) usize {
    return p.screen.y - Editor.STATUSBAR + 2;
}

var DRAW = true;
/// TODO: REFECTOR
pub fn draw(p: *Prompt) !void {
    if (DRAW) {
        const msg = p.status.msg;
        try stdout.writer().print("\x1b[{};0H\x1b[J{s}", .{ p.screenY(), msg });
        DRAW = false;
        return;
    }

    if (std.time.timestamp() - p.status.time > 4 and !DRAW) {
        Editor.STATUSBAR = Editor.DEFAULT_STATUS_SIZE;
        try stdout.writer().print("\x1b[{};0H\x1b[2J", .{p.screenY()});
    }
}

pub fn setStatusMsgWithConfirmation(p: *Prompt, comptime fmt: []const u8, args: anytype) !void {
    if (fmt.len != 0) p.status = try Status.new(fmt, args);
    p.msg_buffer.clearAndFree();
    const msg = p.status.msg;
    try p.msg_buffer.writer().print("\x1b[{};{}H\x1b[K", .{ p.cursor.y, p.cursor.x + 1 });
    try p.msg_buffer.writer().print("{s}\n\r\nPRESS ENTER TO CONTINUE", .{msg});
    try stdout.writeAll(p.msg_buffer.items);
    while (try readKey() != '\r') {}
    try stdout.writeAll("\x1b[2K");
}

/// displays a prompt and lets the user input a line
/// this is not the best way to do this... Unfortunately, i have no idea how to solve
/// the bug related to use a single buffer pattern (to long command lines make the screen go crazy)
pub fn capture(p: *Prompt) !?[]const u8 {
    var input: std.ArrayList(u8) = .init(p.alloc);
    errdefer input.deinit();

    const cur = p.cursor;
    defer p.cursor = cur;

    var idx: usize = 0;
    // try stdout.writer().print("\x1b[{};{}H\x1b[2K:", .{ p.screen.y, cur.x });
    try stdout.writer().print("\x1b[{};{}H\x1b[J:", .{ p.screen.y - Editor.STATUSBAR + 2, cur.x });
    while (true) switch (try readKey()) {
        else => |c| if (c >= 0 and c < 128) {
            try input.insert(p.cursor.x, @intCast(c));
            p.cursor.x += 1;
            idx += 1;
            try stdout.writer().print("{c}", .{@as(u8, @intCast(c))});
        },
        // ESC
        '\x1b' => {
            input.deinit();
            try stdout.writeAll("\x1b[J");
            return null;
        },

        127 => {
            if (input.items.len > 0 and idx > 0) {
                _ = input.orderedRemove(idx - 1);
                p.cursor.x -= 1;
                idx -= 1;
                try stdout.writeAll("\r\x1b[J:");
                try stdout.writeAll(input.items);
            }
        },

        '\r' => if (input.items.len > 0) {
            const cmd = try input.toOwnedSlice();
            try p.cmds.append(cmd);
            try stdout.writeAll("\x1b[J");
            return cmd;
        },

        @intFromEnum(Key.ARROW_LEFT) => if (p.cursor.x != 0 and idx > 0) {
            p.cursor.x -= 1;
            try stdout.writeAll("\x1b[D");
            idx -= 1;
        },

        @intFromEnum(Key.ARROW_RIGHT) => if (p.cursor.x < input.items.len) {
            p.cursor.x += 1;
            try stdout.writeAll("\x1b[C");
            idx += 1;
        },
    };
}
