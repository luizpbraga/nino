const std = @import("std");
const linux = std.os.linux;
const stdout = std.io.getStdOut();
const visual = @import("mode/visual.zig");
const insert = @import("mode/insert.zig");
const normal = @import("mode/normal.zig");
const command = @import("mode/command.zig");
const keys = @import("keys.zig");
const Key = keys.Key;
const KeyMap = keys.KeyMap;
const Row = @import("Row.zig");
const Prompt = @import("Prompt.zig");
const io = @import("io.zig");
const readKey = io.readKey;
const asKey = keys.asKey;
const Visual = visual.Visual;
const Highlight = @import("syntax.zig").HighLight;

/// deals with low-level terminal input and mapping
const Editor = @This();
const VERSION = "0.0.3";
const WELLCOME_STRING = "NINO editor -- version " ++ VERSION;

pub var LEFTSPACE: usize = 0;
pub var SETNUMBER = false;
pub var TABSTOP: usize = 4;
pub var STATUSBAR: usize = 2;
pub var DEFAULT_STATUS_SIZE: usize = 2;
pub var ALLOCNAME = false;
/// SORRY ABOUT THIS
pub var SETMOUSE = false;
pub var MOUSECOORD: Coordinate = .{};
pub var INBLOCKMODE = false;

const Config = struct {
    mouse: bool = false,
    numbers: struct { allow: bool = false, relative: bool = false } = .{},
    staturbar: struct { allow: bool = true, size: usize = 2 } = .{},
};

pub const Mode = enum { normal, insert, visual, command };
/// 2d point Coordinate
const Coordinate = struct { x: usize = 0, y: usize = 0 };
/// x, y: index into the chars in a row
/// rx: render field, same as x when no special character is available
const CursorCoordinate = struct { x: usize = 0, y: usize = 0, rx: usize = 0 };

/// visual block coord
vb: Visual = .{},
/// cursor
cursor: CursorCoordinate = .{},
/// offset
offset: Coordinate = .{},
/// screen display
screen: Coordinate = .{},
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
/// menssages and commands
prompt: Prompt,
///
hl: Highlight,
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
        .prompt = .init(alloc),
        .keyremap = .init(alloc),
        .orig_termios = orig_termios,
        .hl = try .init(alloc, Highlight.zig_ctx),
    };

    try e.getWindowSize();

    e.prompt.cursor.y = e.screen.y + 1;
    e.prompt.screen.x = e.screen.x;
    e.prompt.screen.y = e.screen.y;

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
    e.prompt.deinit();
    e.hl.deinit(e.alloc);
}

pub fn processKeyPressed(e: *Editor) !bool {
    return switch (e.mode) {
        .insert => try insert.actions(e),
        .normal => try normal.actions(e),
        .command => try command.actions(e),
        .visual => b: {
            if (!INBLOCKMODE) {
                try Visual.update(e);
                INBLOCKMODE = true;
                try e.refreshScreen();
            }
            break :b try visual.actions(e);
        },
    };
}

pub fn rowAt(e: *Editor, at: usize) *Row {
    return e.row.items[at];
}

pub fn numOfRows(e: *Editor) usize {
    return e.row.items.len;
}

pub fn toString(e: *Editor) ![]const u8 {
    var list = std.ArrayList(u8).init(e.alloc);
    errdefer list.deinit();
    for (e.row.items) |row| {
        try list.writer().print("{s}\n", .{row.chars.items});
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
            if (char == '\t') {
                // handles \t
                row.render.items[idx] = ' ';
                idx += 1;
                while (idx % TABSTOP != 0) : (idx += 1) {
                    row.render.items[idx] = ' ';
                }
                continue;
            }

            row.render.items[idx] = row.chars.items[j];
            idx += 1;
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
    // TODO: put this in another way
    if (SETNUMBER) LEFTSPACE = std.fmt.count(" {} ", .{e.editorSize() + e.offset.y});
    try e.drawRows();
    try e.drawStatusBar();
    try e.prompt.draw();
    try e.buffer.writer().print("\x1b[{};{}H", .{
        e.cursor.y - e.offset.y + 1,
        LEFTSPACE + e.cursor.rx - e.offset.x + 1,
    });

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
}

fn editorSize(e: *Editor) usize {
    return e.screen.y - STATUSBAR;
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

pub fn drawStatusBar(e: *Editor) !void {
    // switch colors
    try e.buffer.appendSlice("\x1b[7m");

    // ugly peace of shit!!!
    const page_percent = b: {
        const yf: f64 = @floatFromInt(e.cursor.y);
        const nr: f64 = @floatFromInt(e.numOfRows());
        break :b if (nr == 0) 0 else 100 * yf / nr;
    };

    var lstatus: [80]u8 = undefined;
    const llen = b: {
        const modified = if (e.file_status == 0) "" else "[+]";
        const file_name = if (e.file_name.len == 0) "[NO NAME]" else x: {
            const idx = std.mem.lastIndexOf(u8, e.file_name, "/") orelse break :x e.file_name;
            break :x e.file_name[idx + 1 ..];
        };
        const buf = try std.fmt.bufPrint(&lstatus, " \x1b[1m{s}>>\x1b[22m {s} {s}", .{ @tagName(e.mode), file_name, modified });
        break :b if (buf.len > e.screen.x) e.screen.x else buf.len;
    };

    var rstatus: [80]u8 = undefined;
    const rlen = b: {
        const buf = try std.fmt.bufPrint(&rstatus, "\x1b[1m<< {d:.0}% {d}:{d} \x1b[22m", .{ page_percent, e.cursor.x, e.cursor.y });
        break :b buf.len;
    };

    // 18 = sizes of \x1b[...
    const spaces = e.screen.x + 18 - llen - rlen;
    try e.buffer.appendSlice(lstatus[0..llen]);
    try e.buffer.appendNTimes(' ', spaces);
    try e.buffer.appendSlice(rstatus[0..rlen]);

    // reswitch colors
    try e.buffer.appendSlice("\x1b[0m");
}

/// draw a column of (~) on the left hand side at the beginning of any line til EOF
/// using the characters within the render display
/// TODO: Clear lines one at a time
pub fn drawRows(e: *Editor) !void {
    try e.buffer.appendSlice("\x1b[H");
    const b1 = e.buffer.items.len;
    _ = b1; // autofix
    const screenY = e.editorSize();
    for (0..screenY) |y| {
        const file_row = y + e.offset.y;

        if (file_row >= e.numOfRows()) {
            // prints the WELLCOME_STRING if where is no input file
            if (e.numOfRows() == 0 and y == screenY / 3) {
                try e.drawWellcomeScreen();
            } else {
                try e.buffer.append('~');
            }
        } else {
            const renders = e.row.items[file_row].render.items;
            var len = std.math.sub(usize, renders.len, e.offset.x) catch 0;
            if (len > e.screen.x - LEFTSPACE) len = e.screen.x - LEFTSPACE;

            // TODO: relative numbers
            if (SETNUMBER) {
                var size = e.buffer.items.len;
                try e.buffer.writer().print(" \x1b[90m{}\x1b[0m ", .{file_row});
                const escape_size = 9;
                size = e.buffer.items.len - size - escape_size;
                if (size < LEFTSPACE) try e.buffer.appendNTimes(' ', LEFTSPACE - size);
            }

            // I KNOW I CAN DO BETTER, OK?!
            if (e.mode == .visual) {
                const x = e.screen.x - LEFTSPACE + 8;
                var i: usize = 0;
                while (i < x) : (i += 1) {
                    if (e.offset.x + i == renders.len) {
                        break;
                    }
                    try e.buffer.append(renders[e.offset.x + i]);
                }
            } else {
                var list = try e.alloc.allocSentinel(u8, len, 0);
                defer e.alloc.free(list);
                for (0..len) |i| list[i] = renders[e.offset.x + i];
                // for (0..len) |i| try e.buffer.append(renders[e.offset.x + i]);
                try e.hl.illuminate(&e.buffer, list);
                // try e.buffer.appendSlice(list);
            }
        }

        // clear each line as we redraw them
        try e.buffer.appendSlice("\x1b[K\r\n");
    }
}

pub fn scroll(e: *Editor) void {
    e.cursor.rx = if (e.cursor.y < e.numOfRows()) e.cx2rx() else 0;
    // checks if the cursor is above the visible window; if so, scrool up
    if (e.cursor.y < e.offset.y) e.offset.y = e.cursor.y;
    // checks if the cursor is above the bottom of the visible windows
    const screenY = e.editorSize();
    if (e.cursor.y >= e.offset.y + screenY) e.offset.y = e.cursor.y - screenY + 1;
    // same shit to x
    if (e.cursor.rx < e.offset.x) e.offset.x = e.cursor.rx;
    if (e.cursor.rx + LEFTSPACE >= e.offset.x + e.screen.x) e.offset.x = LEFTSPACE + e.cursor.rx - e.screen.x + 1;
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
        asKey('j'), .ARROW_DOWN => if (e.cursor.y + 1 < e.numOfRows()) {
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
