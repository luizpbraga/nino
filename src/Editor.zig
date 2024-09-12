const std = @import("std");
const linux = std.os.linux;
const stdout = std.io.getStdOut();
const command = @import("mode/command.zig");
const visual = @import("mode/visual.zig");
const insert = @import("mode/insert.zig");
const normal = @import("mode/normal.zig");
const keys = @import("keys.zig");
const Key = keys.Key;
const KeyMap = keys.KeyMap;
const Row = @import("Row.zig");
const Status = @import("Status.zig");

pub const Mode = enum { normal, insert, visual, command };

const io = @import("io.zig");
const readKey = io.readKey;
const asKey = keys.asKey;
const controlKey = keys.controlKey;

/// deals with low-level terminal input and mapping
const Editor = @This();
const VERSION = "0.0.2";
const WELLCOME_STRING = "NINO editor -- version " ++ VERSION;

pub const CTRL_Z = controlKey('z');
pub const CTRL_L = controlKey('l');
pub const CTRL_H = controlKey('h');
pub const CTRL_S = controlKey('s');

// highlight
//https://pygments.org/
pub var LEFTSPACE: usize = 0;
pub var SETNUMBER = !true;
pub var TABSTOP: usize = 4;
pub var STATUSBAR: usize = 2;
pub var ALLOCNAME = false;
/// SORRY ABOUT THIS
pub var SETMOUSE = false;
pub var MOUSECOORD: Coordinate = .{};

/// 2d point Coordinate
const Coordinate = struct { x: usize = 0, y: usize = 0 };
const CursorCoordinate = struct { x: usize = 0, y: usize = 0, rx: usize = 0 };

/// cursor
cursor: CursorCoordinate = .{},
/// offset
offset: Coordinate = .{},
/// screen display
screen: Coordinate = .{},
/// status message
status: Status = .{},
/// this little guy will hold the initial state
orig_termios: linux.termios,
/// espace sequece + line buffer
buffer: std.ArrayList(u8),
/// allocator: common to rows and buffer
alloc: std.mem.Allocator,
/// file name
file_name: []const u8 = "",
/// rows
row: std.ArrayList(*Row),
/// file status
file_status: usize = 0,
/// mode
mode: Mode = .normal,
/// remapping
keyremap: KeyMap,

/// Read the current terminal attributes into raw
/// and save the terminal state
pub fn init(alloc: std.mem.Allocator) !Editor {
    var orig_termios: linux.termios = undefined;

    if (linux.tcgetattr(linux.STDIN_FILENO, &orig_termios) == -1) {
        return error.CannotReadTheCurrentTerminalAttributes;
    }

    var e: Editor = .{
        .alloc = alloc,
        .row = .init(alloc),
        .buffer = .init(alloc),
        .keyremap = .init(alloc),
        .orig_termios = orig_termios,
    };

    try e.getWindowSize();

    return e;
}

pub fn deinit(e: *Editor) void {
    for (e.row.items) |row| {
        row.render.deinit();
        row.chars.deinit();
        e.alloc.destroy(row);
    }
    e.row.deinit();
    e.buffer.deinit();
    e.keyremap.deinit();
    if (ALLOCNAME) e.alloc.free(e.file_name);
}

pub fn processKeyPressed(e: *Editor) !bool {
    return switch (e.mode) {
        .insert => try insert.actions(e),
        .normal => try normal.actions(e),
        .command => try command.actions(e),
        .visual => {
            try e.setStatusMsg("Visual mode not implemented", .{});
            e.mode = .normal;
            return false;
        },
    };
}

pub fn rowAt(e: *Editor, at: usize) *Row {
    return e.row.items[at];
}

pub fn numOfRows(e: *Editor) usize {
    return e.row.items.len;
}

pub fn setStatusMsg(e: *Editor, comptime fmt: []const u8, args: anytype) !void {
    if (fmt.len != 0) e.status = try Status.new(fmt, args);
}

pub fn toString(e: *Editor) ![]const u8 {
    var list = std.ArrayList(u8).init(e.alloc);
    errdefer list.deinit();
    for (e.row.items) |row| {
        try list.writer().print("{s}\n", .{row.chars.items});
        Editor.STATUSBAR += 1;
    }
    _ = list.popOrNull();
    return list.toOwnedSlice();
}

pub fn cux(e: *Editor) usize {
    return e.cursor.x;
}

pub fn cuy(e: *Editor) usize {
    return e.cursor.y;
}

/// covert char index to render index
/// not working, i think
pub fn cx2rx(e: *Editor) usize {
    const tab = TABSTOP - 1;
    const chars = e.row.items[e.cursor.y].chars.items;
    var rx: usize = 0;
    for (chars[0..e.cursor.x]) |c| {
        if (c == '\t') rx += tab - (rx % TABSTOP);
        rx += 1;
    }
    return rx;
}

/// renders a render (line)
/// TODO: precisa mesmo do row???
pub fn updateRow(row: *Row) !void {
    // renders tabs as multiple space characters.
    var tabs: usize = 0;
    for (row.chars.items) |char| if (char == '\t') {
        tabs += 1;
    };

    row.render.clearAndFree();
    try row.render.resize(row.chars.items.len + tabs * (TABSTOP - 1));
    {
        var idx: usize = 0;
        for (row.chars.items, 0..) |char, j| {
            if (char != '\t') {
                row.render.items[idx] = row.chars.items[j];
                idx += 1;
                continue;
            }
            // handles \t
            row.render.items[idx] = ' ';
            idx += 1;
            while (idx % TABSTOP != 0) : (idx += 1) {
                row.render.items[idx] = ' ';
            }
        }
        try row.render.resize(idx);
    }
}

/// see ncurses library for terminal capabilities
/// Escape sequence (1byte): \x1b[ allow the terminal to do text formatting task (colour, moving, clearing)
/// https://vt100.net/docs/vt100-ug/chapter3.html#ED
pub fn refreshScreen(e: *Editor) !void {
    defer e.buffer.clearAndFree();

    e.scroll();

    // hide the cursor
    try e.buffer.appendSlice("\x1b[?25l");
    // clear all [2J:
    // try edi.buffer.appendSlice("\x1b[2J"); // let's use \x1b[K instead
    // reposition the cursor at the top-left corner; H command (Cursor Position)
    try e.buffer.appendSlice("\x1b[H");

    // try e.getWindowSize();
    try e.drawRows();
    try e.drawStatusBar();
    try e.drawMsgBar();

    // cursor to the top-left try edi.buffer.appendSlice("\x1b[H");
    // move the cursor
    // e.cursor.y now referees to the position of the cursor within file
    try e.buffer.writer().print("\x1b[{};{}H", .{
        e.cursor.y - e.offset.y + 1,
        LEFTSPACE + e.cursor.rx - e.offset.x + 1,
    });

    // show the cursor
    try e.buffer.appendSlice("\x1b[?25h");
    try stdout.writeAll(e.buffer.items);
}

pub fn refreshPrompt(e: *Editor) !void {
    defer e.buffer.clearAndFree();

    try e.buffer.appendSlice("\x1b[?25l\x1b[H");

    // try e.getWindowSize();
    try e.drawRows();
    try e.drawStatusBar();
    try e.drawMsgBar();

    try e.buffer.writer().print("\x1b[{};{}H\x1b[?25h", .{
        e.screen.y + TABSTOP,
        e.cursor.x + 1,
    });

    // show the cursor
    try e.buffer.appendSlice("");
    try stdout.writeAll(e.buffer.items);
}

/// TODO: Window size, the hard way
pub fn getWindowSize(e: *Editor) !void {
    var ws: std.posix.winsize = undefined;
    const errno = linux.ioctl(linux.STDIN_FILENO, linux.T.IOCGWINSZ, @intFromPtr(&ws));
    if (errno == -1 or ws.col == 0) {
        return error.CannotFindWindowSize;
    }
    e.screen.y = ws.row;
    e.screen.x = ws.col;
    // drawRows() will not try to draw in the last line in the screen
    e.screen.y -= STATUSBAR;
}

pub fn drawWellcomeScreen(e: *Editor) !void {
    const welllen = WELLCOME_STRING.len;
    var pedding = (e.screen.x - welllen) / 2;

    if (pedding > 0) {
        try e.buffer.append('~');
        pedding -= 1;
    }

    while (pedding != 0) : (pedding -= 1) {
        try e.buffer.append(' ');
    }

    try e.buffer.appendSlice(WELLCOME_STRING);
}

pub fn drawMsgBar(e: *Editor) !void {
    // clear the bar
    try e.buffer.appendSlice("\x1b[K");
    const msg = e.status.msg;
    if (msg.len == 0) return;

    if (std.time.timestamp() - e.status.time < 5) {
        try e.buffer.appendSlice(&msg);
        Editor.STATUSBAR += std.mem.count(u8, &msg, "\n");
    } else {
        Editor.STATUSBAR = 2;
    }

    // const len = if (msg.len > e.screen.x) e.screen.x else msg.len;
    // if (std.time.timestamp() - e.status.time < 5) {
    //     try e.buffer.appendSlice(msg[0..len]);
    // }
}

pub fn drawStatusBar(e: *Editor) !void {
    // switch colors
    try e.buffer.appendSlice("\x1b[7m");

    var lstatus: [80]u8 = undefined;
    var llen = b: {
        const modified = if (e.file_status == 0) "" else "[+]";
        const file_name = if (e.file_name.len == 0) "[NO NAME]" else e.file_name;
        const buf = try std.fmt.bufPrint(&lstatus, "{s}> {s} {s}", .{ @tagName(e.mode), file_name, modified });
        break :b if (buf.len > e.screen.x) e.screen.x else buf.len;
    };

    try e.buffer.appendSlice(lstatus[0..llen]);

    var rstatus: [80]u8 = undefined;
    const rlen = b: {
        const buf = try std.fmt.bufPrint(&rstatus, "<{d}:{d} ", .{ e.cursor.y, e.cursor.x });
        break :b buf.len;
    };

    while (llen < e.screen.x) : (llen += 1) {
        if (e.screen.x - llen == rlen) {
            try e.buffer.appendSlice(rstatus[0..rlen]);
            break;
        }
        try e.buffer.append(' ');
    }
    // reswitch colors
    try e.buffer.appendSlice("\x1b[0m\r\n");
}

/// draw a column of (~) on the left hand side at the beginning of any line til EOF
/// using the characters within the render display
/// TODO: Clear lines one at a time
pub fn drawRows(e: *Editor) !void {
    for (0..e.screen.y) |y| {
        const file_row = y + e.offset.y;

        if (file_row >= e.numOfRows()) {
            // prints the WELLCOME_STRING if where is no input file
            if (e.numOfRows() == 0 and y == e.screen.y / 3) {
                try e.drawWellcomeScreen();
            } else {
                try e.buffer.append('~');
            }
        } else {
            const renders = e.row.items[file_row].render.items;
            var len = std.math.sub(usize, renders.len, e.offset.x) catch 0;
            if (len > e.screen.x) len = e.screen.x;
            if (SETNUMBER) {
                const size = e.buffer.items.len;
                try e.buffer.writer().print(" {d} ", .{file_row});
                LEFTSPACE = e.buffer.items.len - size;
                // try e.buffer.appendNTimes(' ', LEFTSPACE);
            }
            for (0..len) |i| try e.buffer.append(renders[e.offset.x + i]);
        }
        // clear each line as we redraw them
        try e.buffer.appendSlice("\x1b[K");
        _ = try e.buffer.appendSlice("\r\n");
    }
}

pub fn scroll(e: *Editor) void {
    e.cursor.rx = if (e.cursor.y < e.numOfRows()) e.cx2rx() else 0;
    // checks if the cursor is above the visible window; if so, scrool up
    if (e.cursor.y < e.offset.y) e.offset.y = e.cursor.y;
    // checks if the cursor is above the bottom of the visible windows
    if (e.cursor.y >= e.offset.y + e.screen.y) e.offset.y = e.cursor.y - e.screen.y + 1;
    // same shit to x
    if (e.cursor.x < e.offset.x) e.offset.x = e.cursor.rx;
    if (e.cursor.x >= e.offset.x + e.screen.x) e.offset.x = e.cursor.rx - e.screen.x + 1;
}

pub fn moveCursor(e: *Editor, key: usize) void {
    // var maybe_cur_row = if (e.cursor.y >= e.numOfRows()) null else e.rows.items[e.cursor.y];
    var maybe_cur_row = if (e.cursor.y >= e.numOfRows()) null else e.row.items[e.cursor.y].chars.items;
    const key_tag: Key = @enumFromInt(key);

    switch (key_tag) {
        asKey('h'), .ARROW_LEFT => if (e.cursor.x != 0) {
            e.cursor.x -= 1;
        },

        // bound the cursor to the actual string size
        asKey('l'), .ARROW_RIGHT => if (maybe_cur_row) |cur_row| {
            if (e.cursor.x < cur_row.len) e.cursor.x += 1;
        },

        asKey('k'), .ARROW_UP => if (e.cursor.y != 0) {
            e.cursor.y -= 1;
        },

        // scroll logic
        asKey('j'), .ARROW_DOWN => if (e.cursor.y < e.numOfRows()) {
            e.cursor.y += 1;
        },

        else => unreachable,
    }

    // snap cursor to end of line (move to end)
    maybe_cur_row = if (e.cursor.y >= e.numOfRows()) null else e.row.items[e.cursor.y].chars.items;
    // maybe_cur_row = if (e.cursor.y >= e.numOfRows()) null else e.rows.items[e.cursor.y];
    const row_len = if (maybe_cur_row) |row| row.len else 0;
    if (e.cursor.x > row_len) e.cursor.x = row_len;
}

/// create and collect a new row
pub fn createRow(e: *Editor, at: usize) !*Row {
    var row = try e.alloc.create(Row);
    row.chars = .init(e.alloc);
    row.render = .init(e.alloc);
    try e.row.insert(at, row);
    return row;
}

/// adds a new row and render
pub fn insertRow(e: *Editor, at: usize, chars: []u8) !void {
    defer e.file_status += 1;
    if (at > e.numOfRows()) return;
    var row = try e.createRow(at);
    try row.chars.appendSlice(chars);
    try updateRow(row);
}

pub fn insertNewLine(e: *Editor) !void {
    defer {
        e.cursor.y += 1;
        e.cursor.x = 0;
    }

    if (e.cursor.x == 0) {
        try e.insertRow(e.cursor.y, "");
        return;
    }

    var row = e.row.items[e.cursor.y];
    const chars = row.chars.items;
    try e.insertRow(e.cursor.y + 1, chars[e.cursor.x..]);
    row = e.row.items[e.cursor.y];
    try row.chars.resize(e.cursor.x);
    try updateRow(row);
}

///inserts a single character into an row, at the current (x, y) cursor
/// position.
pub fn rowInsertChar(e: *Editor, row: *Row, at: usize, char: u8) !void {
    defer e.file_status += 1;
    const len = row.charsLen();
    const cx = if (e.cursor.x > len) len else at;
    try row.chars.insert(cx, char);
    try updateRow(row);
}

pub fn insertChar(e: *Editor, key: u8) !void {
    defer e.cursor.x += 1;
    if (e.cursor.y == e.numOfRows()) {
        try e.insertRow(e.numOfRows(), "");
    }
    const row = e.rowAt(e.cursor.y);
    try e.rowInsertChar(row, e.cursor.x, key);
}

///deletes a single character into an row, at the current (x, y) cursor
/// position.
pub fn rowDeleteChar(e: *Editor, row: *Row, at: usize) !void {
    if (at >= row.charsLen()) return;
    _ = row.chars.orderedRemove(at);
    try updateRow(row);
    e.file_status += 1;
}

pub fn freeRow(e: *Editor, row: *Row) void {
    row.chars.deinit();
    row.render.deinit();
    _ = e.row.orderedRemove(e.cursor.y);
}

pub fn deleteRow(e: *Editor, at: usize) void {
    if (at >= e.numOfRows()) return;
    const row = e.rowAt(at);
    defer e.alloc.destroy(row);
    e.freeRow(row);
    e.file_status += 1;
}

pub fn deleteChar(e: *Editor) !void {
    if (e.cursor.y == e.numOfRows()) return;
    if (e.cursor.y == 0 and e.cursor.x == 0) return;

    const row = e.rowAt(e.cursor.y);
    if (e.cursor.x > 0) {
        try e.rowDeleteChar(row, e.cursor.x - 1);
        e.cursor.x -= 1;
        return;
    }

    // handle appending to the prev. line
    const last_row = e.rowAt(e.cursor.y - 1);
    e.cursor.x = last_row.charsLen();
    try e.rowAppendString(last_row, row.chars.items);
    e.deleteRow(e.cursor.y);
    e.cursor.y -= 1;
}

pub fn rowAppendString(e: *Editor, row: *Row, string: []const u8) !void {
    defer e.file_status += 1;
    try row.chars.appendSlice(string);
    try updateRow(row);
}

/// displays a prompt in the status bar & and lets the user input a line
/// after the prompt
/// callow own the memory
/// TODO: make prompt and command diff things
pub fn prompt(e: *Editor, comptime prompt_fmt: []const u8) !?[]const u8 {
    var input: std.ArrayList(u8) = .init(e.alloc);
    defer input.deinit();
    const prev_cursor = e.cursor;
    defer {
        e.cursor.x = prev_cursor.x;
        e.cursor.y = prev_cursor.y;
        e.cursor.rx = prev_cursor.rx;
    }

    e.cursor.rx = 0;
    e.cursor.x = 1;

    while (true) {
        try e.setStatusMsg(prompt_fmt, .{input.items});
        try e.refreshPrompt();

        switch (try readKey()) {
            '\x1b' => {
                try e.setStatusMsg("", .{});
                return null;
            },

            127 => {
                if (input.items.len != 0) {
                    _ = input.pop();
                    e.cursor.x -= 1;
                }
            },

            '\r' => if (input.items.len != 0) {
                try e.setStatusMsg("", .{});
                return try input.toOwnedSlice();
            },

            @intFromEnum(Key.ARROW_LEFT) => if (e.cursor.x != 1) {
                e.cursor.x -= 1;
            },

            @intFromEnum(Key.ARROW_RIGHT) => if (e.cursor.x <= input.items.len) {
                e.cursor.x += 1;
            },

            else => |c| if (c >= 0 and c < 128) {
                try input.append(@intCast(c));
                e.cursor.x += 1;
            },
        }
    }
}
