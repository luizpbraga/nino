const std = @import("std");
const io = @import("../io.zig");
const Editor = @import("../Editor.zig");

const mem = std.mem;
const eql = mem.eql;
const startsWith = mem.startsWith;
const trim = mem.trim;

/// tag union??? a big if ????
const Commands = union(enum(u8)) {
    read,
    write,
    number,
    quit,
    _,
};

// [RANGE][COMMAND][ARGS] [OPTS]
const command_map = std.StaticStringMap(Commands).initComptime(
    .{ "r", .read },
    .{ "read", .read },
    .{ "w", .write },
    .{ "write", .write },
    .{ "q", .quit },
    .{ "quit", .quit },
    .{ "m", .move },
    .{ "move", .move },
);

pub fn actions(e: *Editor) !bool {
    defer e.mode = .normal;

    const command = try e.prompt(":{s}") orelse {
        return false;
    };
    defer e.alloc.free(command);

    const cmd = trim(u8, command, " \t");

    if (eql(u8, cmd, "help")) {
        try e.setStatusMsg("help not available KKKKKKKK", .{});
        return false;
    }

    if (eql(u8, cmd, "poem")) {
        try e.setStatusMsg("Poeminho do Contra\n\roi\n\rtchau", .{});
        return false;
    }

    if (eql(u8, cmd, "num")) {
        Editor.SETNUMBER = !Editor.SETNUMBER;
        Editor.LEFTSPACE = 0;
        try e.setStatusMsg("setnumbers = {}", .{Editor.SETNUMBER});
        try e.refreshScreen();
        return false;
    }

    if (startsWith(u8, cmd, "r ")) {
        const file = cmd[2..];
        io.read(e, file) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied => try e.setStatusMsg("Warn: read not implemented", .{}),
            else => return err,
        };
        try e.setStatusMsg("\"{s}\" [noeol] <TODO>L, <TODO>B", .{file});
        return false;
    }

    if (eql(u8, cmd, "q") or eql(u8, cmd, "quit")) {
        if (e.file_status == 0) {
            try io.exit();
            return true;
        }
        try e.setStatusMsg("Warn: unsaved changes. Use ':q!' to force quit", .{});
        return false;
    }

    if (eql(u8, cmd, "q!") or eql(u8, cmd, "quit!")) {
        try io.exit();
        return true;
    }

    if (eql(u8, cmd, "w") or eql(u8, cmd, "write")) {
        if (e.file_name.len == 0) {
            try e.setStatusMsg("Error: Cannot write IF YOU DONT PROVIDE A FILE NAME!", .{});
            return false;
        }

        if (e.file_status == 0) {
            try e.setStatusMsg("Warn: Nothing to write", .{});
            return false;
        }

        try io.save(e);
        return false;
    }

    if (eql(u8, cmd, "wq")) {
        if (e.file_name.len == 0) {
            try e.setStatusMsg("Error: Cannot write IF YOU DONT PROVIDE A FILE NAME!", .{});
            return false;
        }
        try io.save(e);
        try io.exit();
        return true;
    }

    if (startsWith(u8, cmd, "w ")) {
        if (Editor.ALLOCNAME) {
            e.alloc.free(e.file_name);
            Editor.ALLOCNAME = false;
        }

        const name = cmd[2..];

        if (io.fileExists(name) and !eql(u8, name, e.file_name)) {
            try e.setStatusMsg("Error: File exists", .{});
            return false;
        }

        if (!eql(u8, name, e.file_name)) {
            e.file_status = 0;
        }

        const newname = try e.alloc.alloc(u8, name.len);
        @memcpy(newname, name);
        e.file_name = newname;
        Editor.ALLOCNAME = true;

        try io.save(e);
        return false;
    }

    if (eql(u8, cmd, "statusbar")) {
        try e.setStatusMsg("statusbar = {} ", .{Editor.STATUSBAR});
        return false;
    }

    if (startsWith(u8, cmd, "stat")) {
        if (startsWith(u8, cmd[4..], "+")) {
            Editor.STATUSBAR += 1;
            e.screen.y -= 1;
        }

        if (startsWith(u8, cmd[4..], "-")) {
            Editor.STATUSBAR -= 1;
            e.screen.y += 1;
        }

        try e.setStatusMsg("statusbar = {} ", .{Editor.STATUSBAR});
        return false;
    }

    if (eql(u8, cmd, "maps")) {
        var list = std.ArrayList(u8).init(e.alloc);
        defer list.deinit();
        var iter = e.keyremap.hash.iterator();
        while (iter.next()) |entry| {
            const mode, const key = entry.key_ptr.*;
            const keys = entry.value_ptr.*;
            try list.writer().print("{} {} {any}\n", .{ mode, key, keys });
        }
        _ = list.pop();
        try e.setStatusMsg("{s}", .{list.items});
        return false;
    }

    const n = std.fmt.parseUnsigned(isize, cmd, 10) catch -1;
    if (n != -1) {
        e.cursor.y = if (n < e.numOfRows()) @intCast(n) else b: {
            break :b if (e.numOfRows() != 0) e.numOfRows() - 1 else 0;
        };
        e.cursor.x = if (e.cursor.x < e.rowAt(e.cursor.x).charsLen()) e.cursor.x else 0;
        return false;
    }

    try e.setStatusMsg("Not an editor command: {s}", .{cmd});
    return false;
}
