const std = @import("std");
const Editor = @import("../Editor.zig");
const io = @import("../io.zig");

const keys = @import("../keys.zig");
const Key = keys.Key;

/// handles the keypress
pub fn actions(e: *Editor) !bool {
    const key = try io.readKey();
    const key_tag: Key = @enumFromInt(key);

    switch (key_tag) {
        .ENTER => try e.insertNewLine(),

        .ESC => e.mode = .normal,

        .BACKSPACE, Editor.CTRL_H => try e.deleteChar(),

        .DEL => {
            e.moveCursor(@intFromEnum(Key.ARROW_RIGHT));
            try e.deleteChar();
        },

        // cursor movement keys
        .ARROW_UP,
        .ARROW_DOWN,
        .ARROW_RIGHT,
        .ARROW_LEFT,
        => e.moveCursor(key),

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

        else => if (key < 128) try e.insertChar(@intCast(key)),
    }

    return false;
}
