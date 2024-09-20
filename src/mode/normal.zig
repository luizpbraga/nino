const std = @import("std");
const Editor = @import("../Editor.zig");
const io = @import("../io.zig");
const keys = @import("../keys.zig");
const Key = keys.Key;
const asKey = keys.asKey;
const controlKey = keys.controlKey;

fn isNumber(nk: Key) bool {
    return switch (nk) {
        .@"0", .@"1", .@"2", .@"3", .@"4", .@"5", .@"6", .@"7", .@"8", .@"9" => true,
        else => false,
    };
}

fn toInt(num: anytype) !usize {
    return if (num.len == 0) 1 else try std.fmt.parseInt(usize, num.slice(), 10);
}

pub fn actions(e: *Editor) !bool {
    const char = try io.readKey();
    const key_tag: Key = @enumFromInt(char);
    const keys_tag = e.keyremap.get(e.mode, key_tag) orelse &.{key_tag};
    var number = try std.BoundedArray(u8, 10).init(0);

    for (keys_tag) |key| {
        var kkk = key;
        l: switch (kkk) {
            .ENTER => try e.insertNewLine(),

            Editor.CTRL_Z => {
                try io.exit();
                return true;
            },

            // .MOUSE => {
            //     if (!SETMOUSE) return false;
            //     // broken
            //     if (e.row.items.len == 0) return false;
            //
            //     const mx = MOUSECOORD.x;
            //     const my = MOUSECOORD.y;
            //
            //     e.cursor.y = if (my == 0) 0 else if (my > e.numOfRows()) e.numOfRows() - 1 else my + e.offset.y - 1;
            //
            //     const row = e.rowAt(e.cursor.y);
            //     if (row.charsLen() == 0 or mx == 0) {
            //         e.cursor.x = e.offset.x;
            //     } else {
            //         e.cursor.x = if (mx > row.charsLen()) row.charsLen() else mx + e.offset.x - 1;
            //     }
            // },

            // cursor movement keys
            .ARROW_UP, .ARROW_DOWN, .ARROW_RIGHT, .ARROW_LEFT, asKey('h'), asKey('j'), asKey('k'), asKey('l') => {
                for (try toInt(number)) |_| e.moveCursor(@intFromEnum(kkk));
            },

            .PAGE_UP, .PAGE_DOWN => |c| {
                // positioning the cursor to the end/begin
                const k: Key = switch (c) {
                    .PAGE_UP => b: {
                        e.cursor.y = e.offset.y;
                        break :b .ARROW_UP;
                    },

                    .PAGE_DOWN => b: {
                        e.cursor.y = e.offset.y + e.screen.y - 1;
                        if (e.cursor.y > e.numOfRows()) e.cursor.y = e.numOfRows();
                        break :b .ARROW_DOWN;
                    },

                    else => unreachable,
                };

                var times = e.screen.y;
                while (times != 0) : (times -= 1) e.moveCursor(@intFromEnum(k));
            },

            .HOME => e.cursor.x = 0,

            .END => if (e.cursor.y < e.numOfRows()) {
                const chars = e.row.items[e.cursor.y].chars.items;
                e.cursor.x = chars.len;
            },

            asKey('i') => e.mode = .insert,

            asKey('v') => e.mode = .visual,

            asKey(':') => e.mode = .command,

            asKey('C'), asKey('S'), asKey('D') => |c| {
                // TODO
                while (e.cursor.x != e.rowAt(e.cursor.y).charsLen()) {
                    e.moveCursor(@intFromEnum(Key.ARROW_RIGHT));
                    try e.deleteChar();
                }
                if (c == asKey('C') or c == asKey('S')) e.mode = .insert;
            },

            .@"0", .@"1", .@"2", .@"3", .@"4", .@"5", .@"6", .@"7", .@"8", .@"9" => |c| {
                if (number.len != 10) {
                    try number.appendSlice(@tagName(c));
                    try e.prompt.setStatusMsg("{s}", .{number.slice()});
                    try e.refreshScreen(); // todo: update refresPrompt
                }
                kkk = @enumFromInt(try io.readKey());
                continue :l kkk;
            },

            // controlKey('-'), controlKey('+') => {
            //     try e.getWindowSize();
            //     try e.refreshScreen();
            // },

            else => {},
        }
    }

    return false;
}
