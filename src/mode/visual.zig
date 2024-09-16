const std = @import("std");
const Editor = @import("../Editor.zig");
const io = @import("../io.zig");
const keys = @import("../keys.zig");
const Key = keys.Key;
const asKey = keys.asKey;

pub const Visual = struct {
    const INVERSE = "\x1b[9m";
    const RESET = "\x1b[0m";
    const SIZE = 4;
    const mode = enum { line, block, standard };
    const default: Visual = .{};

    xi: usize = 0,
    yi: usize = 0,
    xf: usize = 0,
    yf: usize = 0,

    // BUG: corners, offset rows
    pub fn update(e: *Editor) !void {
        try e.row.items[e.cursor.y].chars.insertSlice(e.cursor.x + 1, RESET);
        try e.row.items[e.cursor.y].chars.insertSlice(e.cursor.x, INVERSE); // appenda em i, H vai p x + 1
        e.vb = .{
            .xi = e.cursor.x,
            .xf = e.cursor.x + SIZE + 1,
            .yi = e.cursor.y,
            .yf = e.cursor.y,
        };
        try Editor.updateRow(e.row.items[e.cursor.y]);
    }

    pub fn free(e: *Editor) !void {
        for (1..SIZE + 1) |i| {
            _ = e.row.items[e.vb.yf].chars.orderedRemove(e.vb.xi);
            _ = e.row.items[e.vb.yf].chars.orderedRemove(e.vb.xf - i);
        }
        try Editor.updateRow(e.row.items[e.vb.yf]);
        e.mode = .normal;
        Editor.INBLOCKMODE = false;
        e.vb = .default;
    }

    pub fn move(e: *Editor, k: Key) !bool {
        const chars = e.row.items[e.vb.yi].chars.items;

        switch (k) {
            .ARROW_RIGHT => {
                // WHAT THE FUCK?!?!?!?!
                if (e.cursor.x + 2 * SIZE + 1 >= chars.len) return false;

                if (e.cursor.x + SIZE + 1 == e.vb.xf) {
                    for (0..SIZE) |_| _ = e.row.items[e.vb.yi].chars.orderedRemove(e.vb.xf);
                    e.vb.xf += 1;
                    try e.row.items[e.vb.yi].chars.insertSlice(e.vb.xf, RESET);
                } else {
                    for (0..SIZE) |_| _ = e.row.items[e.vb.yi].chars.orderedRemove(e.vb.xi);
                    e.vb.xi += 1;
                    try e.row.items[e.vb.yi].chars.insertSlice(e.vb.xi, INVERSE);
                }
                try e.setStatusMsg("x:{},xi:{},xf:{},len:{},c:{c}", .{ e.cursor.x, e.vb.xi, e.vb.xf, chars.len, chars[e.cursor.x + SIZE] });

                e.moveCursor(@intFromEnum(k));
            },

            .ARROW_LEFT => {
                if (e.cursor.x == 0) return false;

                if (e.vb.xi == e.cursor.x) {
                    for (0..SIZE) |_| _ = e.row.items[e.vb.yi].chars.orderedRemove(e.vb.xi);
                    e.vb.xi -= 1;
                    try e.row.items[e.vb.yi].chars.insertSlice(e.vb.xi, INVERSE);
                } else {
                    for (0..SIZE) |_| _ = e.row.items[e.vb.yi].chars.orderedRemove(e.vb.xf);
                    e.vb.xf -= 1;
                    try e.row.items[e.vb.yi].chars.insertSlice(e.vb.xf, RESET);
                }
                e.moveCursor(@intFromEnum(k));
            },
            else => {},
        }

        try Editor.updateRow(e.row.items[e.vb.yi]);
        return true;
    }
};

pub fn actions(e: *Editor) !bool {
    const char = try io.readKey();
    const key_tag: Key = @enumFromInt(char);
    const keys_tag = e.keyremap.get(e.mode, key_tag) orelse &.{key_tag};

    for (keys_tag) |key| switch (key) {
        asKey('c') => {
            const xi = e.vb.xi;
            const xf = e.vb.xf;
            e.cursor.x = xi;
            try Visual.free(e);

            // WORKED LIKE DARK MAGIC
            for (xf - xi - 4) |_| {
                _ = e.row.items[e.vb.yf].chars.orderedRemove(xi);
            }

            try Editor.updateRow(e.row.items[e.vb.yi]);
        },

        asKey('v'), .ESC => {
            try Visual.free(e);
        },

        // cursor movement keys
        // .ARROW_UP,
        // .ARROW_DOWN,
        .ARROW_RIGHT,
        .ARROW_LEFT,
        => |c| {
            _ = try Visual.move(e, c);
        },

        else => {},
    };

    return false;
}
