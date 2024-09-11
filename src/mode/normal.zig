const std = @import("std");
const Editor = @import("../Editor.zig");
const io = @import("../io.zig");
const keys = @import("../keys.zig");
const Key = keys.Key;
const asKey = keys.asKey;
const controlKey = keys.controlKey;

pub fn actions(e: *Editor) !bool {
    const key = try io.readKey();
    const key_tag: Key = @enumFromInt(key);

    switch (key_tag) {
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
        .ARROW_UP,
        .ARROW_DOWN,
        .ARROW_RIGHT,
        .ARROW_LEFT,
        asKey('h'),
        asKey('j'),
        asKey('k'),
        asKey('l'),
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

        asKey('i') => e.mode = .insert,

        asKey(':') => e.mode = .command,

        else => {},
    }

    return false;
}
