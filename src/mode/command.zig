const std = @import("std");
const io = @import("../io.zig");
const Editor = @import("../Editor.zig");
const Regex = @import("../Regex.zig");

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

    const command = try e.prompt.capture() orelse {
        return false;
    };
    const cmd = trim(u8, command, " \t\r\n");

    if (startsWith(u8, cmd, "/")) {
        const patterns = cmd[1..];

        try e.search.compile(patterns);

        // const counter = try e.search.applySearchRows(e.row, patterns);
        // const counter = ;
        // if (counter == 0) {
        //     try e.prompt.setStatusMsg("\x1b[31mError: Pattern not found: {s}\x1b[0m", .{patterns});
        // } else {
        //     try e.prompt.setStatusMsg(":/{s} [{}]", .{ patterns, counter });
        // }
        return false;
    }

    if (eql(u8, cmd, "nos")) {
        // e.search.free();
        e.search.undo(e.row);
        return false;
    }

    if (eql(u8, cmd, "n")) {
        try e.prompt.setStatusMsg("nrows:{}", .{e.numOfRows()});
        return false;
    }

    if (eql(u8, cmd, "help")) {
        try e.prompt.setStatusMsg("help not available KKKKKKKK", .{});
        return false;
    }

    if (eql(u8, cmd, "poem")) {
        try e.prompt.setStatusMsg("Poeminho do Contra\n\roi\n\rtchau", .{});
        return false;
    }

    if (eql(u8, cmd, "num")) {
        Editor.SETNUMBER = !Editor.SETNUMBER;
        Editor.LEFTSPACE = 0;
        try e.prompt.setStatusMsg("setnumbers = {}", .{Editor.SETNUMBER});
        try e.refreshScreen();
        return false;
    }

    if (startsWith(u8, cmd, "r ")) {
        const file = cmd[2..];
        io.read(e, file) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied => try e.prompt.setStatusMsg("Warn: read not implemented", .{}),
            else => return err,
        };
        try e.prompt.setStatusMsg("\"{s}\" [noeol] <TODO>L, <TODO>B", .{file});
        return false;
    }

    if (eql(u8, cmd, "q") or eql(u8, cmd, "quit")) {
        if (e.file_status == 0) {
            try io.exit();
            return true;
        }
        try e.prompt.setStatusMsg("Warning: unsaved changes. Use ':q!' to force quit", .{});
        return false;
    }

    if (eql(u8, cmd, "q!") or eql(u8, cmd, "quit!")) {
        try io.exit();
        return true;
    }

    if (eql(u8, cmd, "w") or eql(u8, cmd, "write")) {
        if (e.file_name.len == 0) {
            try e.prompt.setStatusMsg("\x1b[31mError: Cannot write IF YOU DONT PROVIDE A FILE NAME!\x1b[0m", .{});
            return false;
        }

        if (e.file_status == 0) {
            try e.prompt.setStatusMsg("Warning: Nothing to write", .{});
            return false;
        }

        try io.save(e);
        return false;
    }

    if (eql(u8, cmd, "wq")) {
        if (e.file_name.len == 0) {
            try e.prompt.setStatusMsg("\x1b[31mError: Cannot write IF YOU DONT PROVIDE A FILE NAME!\x1b[0m", .{});
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
            try e.prompt.setStatusMsg("\x1b[31mError: File exists\x1b[0m", .{});
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

    if (startsWith(u8, cmd, "s")) {
        if (startsWith(u8, cmd[1..], "+")) {
            Editor.DEFAULT_STATUS_SIZE += 1;
            // e.screen.y -= 1;
        }

        if (startsWith(u8, cmd[1..], "-")) {
            Editor.DEFAULT_STATUS_SIZE -= 1;
            // e.screen.y += 1;
        }

        Editor.STATUSBAR = Editor.DEFAULT_STATUS_SIZE;

        try e.prompt.setStatusMsg("statusbar:{},screen:{}", .{ Editor.DEFAULT_STATUS_SIZE, e.screen.y });
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
        try e.prompt.setStatusMsg("{s}", .{list.items});
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

    try e.prompt.setStatusMsg("\x1b[31mNot an editor command: {s}\x1b[0m", .{cmd});
    return false;
}
