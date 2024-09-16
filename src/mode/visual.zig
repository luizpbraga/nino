const std = @import("std");
const Editor = @import("../Editor.zig");
const io = @import("../io.zig");
const keys = @import("../keys.zig");
const Key = keys.Key;
const asKey = keys.asKey;

pub const Visual = struct {
    const INVERSE = "\x1b[7m";
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
        try e.row.items[e.cursor.y].chars.insertSlice(e.cursor.rx + 1, RESET);
        try e.row.items[e.cursor.y].chars.insertSlice(e.cursor.rx, INVERSE); // appenda em i, H vai p x + 1
        e.vb = .{
            .xi = e.cursor.x,
            .xf = e.cursor.x + SIZE + 1,
            .yi = e.cursor.y,
            .yf = e.cursor.y,
        };
        try e.setStatusMsg(">x:{},xi:{},xf:{}", .{ e.cursor.x, e.vb.xi, e.vb.xf });
        try Editor.updateRow(e.row.items[e.cursor.y]);
    }

    pub fn free(e: *Editor) !void {
        // for (0..SIZE) |_| _ = e.row.items[e.vb.yf].chars.orderedRemove(e.vb.xf);
        // for (0..SIZE) |_| _ = e.row.items[e.vb.yf].chars.orderedRemove(e.vb.xi);
        for (1..SIZE + 1) |i| {
            _ = e.row.items[e.vb.yf].chars.orderedRemove(e.vb.xi);
            _ = e.row.items[e.vb.yf].chars.orderedRemove(e.vb.xf - i);
        }
        try Editor.updateRow(e.row.items[e.vb.yf]);
        e.vb = .default;
    }

    pub fn move(e: *Editor, k: Key) !bool {
        if (e.vb.xf + 1 + SIZE > e.row.items[e.vb.yi].chars.items.len) return false;

        // TODO:; xi and xf bounds
        switch (k) {
            .ARROW_RIGHT => if (e.cursor.x >= e.vb.xi) {
                for (0..SIZE) |_| _ = e.row.items[e.vb.yi].chars.orderedRemove(e.vb.xf);
                e.vb.xf += 1;
                try e.row.items[e.vb.yi].chars.insertSlice(e.vb.xf, RESET);
                e.moveCursor(@intFromEnum(k));
            } else {
                for (0..SIZE) |_| _ = e.row.items[e.vb.yi].chars.orderedRemove(e.vb.xi);
                e.vb.xi += 1;
                try e.row.items[e.vb.yi].chars.insertSlice(e.vb.xi, INVERSE);
                e.moveCursor(@intFromEnum(k));
            },

            .ARROW_LEFT => if (e.cursor.x >= e.vb.xi) {
                for (0..SIZE) |_| _ = e.row.items[e.vb.yi].chars.orderedRemove(e.vb.xf);
                e.vb.xf -= 1;
                try e.row.items[e.vb.yi].chars.insertSlice(e.vb.xf, RESET);
                e.moveCursor(@intFromEnum(k));
            } else {
                for (0..SIZE) |_| _ = e.row.items[e.vb.yi].chars.orderedRemove(e.vb.xi);
                e.vb.xi -= 1;
                try e.row.items[e.vb.yi].chars.insertSlice(e.vb.xi, INVERSE);
                e.moveCursor(@intFromEnum(k));
            },
            else => {},
        }

        try e.setStatusMsg("x:{},xi:{},xf:{}", .{ e.cursor.x, e.vb.xi, e.vb.xf });
        try Editor.updateRow(e.row.items[e.vb.yi]);

        return true;
    }
};

pub fn actions(e: *Editor) !bool {
    const char = try io.readKey();
    const key_tag: Key = @enumFromInt(char);
    const keys_tag = e.keyremap.get(e.mode, key_tag) orelse &.{key_tag};

    for (keys_tag) |key| switch (key) {
        asKey('v'), .ESC => {
            e.mode = .normal;
            try Visual.free(e);
            Editor.INBLOCKMODE = false;
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
