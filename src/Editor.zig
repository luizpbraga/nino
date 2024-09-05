const std = @import("std");
const linux = std.os.linux;
const ascii = std.ascii;
const stdin = std.io.getStdIn();
const stdout = std.io.getStdOut();

/// deals with low-level terminal input and mapping
const Editor = @This();
const VERSION = "0.0.1";
const WELLCOME_STRING = "NINO editor -- version " ++ VERSION;
const CTRL_Z = controlKey('z');
const TABSTOP = 8;

const Key = enum(usize) {
    ARROW_LEFT = 1000,
    ARROW_RIGHT,
    ARROW_UP,
    ARROW_DOWN,
    DEL,
    HOME,
    END,
    PAGE_UP,
    PAGE_DOWN,
};

/// 2d point Coordinate
const Coordinate = struct { x: usize = 0, y: usize = 0 };
const CursorCoordinate = struct { x: usize = 0, y: usize = 0, rx: usize = 0 };
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
/// rows data
rows: std.ArrayList([]u8),
/// render nonprintable control character
render: std.ArrayList([]u8),
/// allocator: common to rows and buffer
alloc: std.mem.Allocator,
/// Read the current terminal attributes into raw
/// and save the terminal state
pub fn init(alloc: std.mem.Allocator) !Editor {
    var orig_termios: linux.termios = undefined;

    if (linux.tcgetattr(linux.STDIN_FILENO, &orig_termios) == -1) {
        return error.CannotReadTheCurrentTerminalAttributes;
    }

    var edi: Editor = .{
        .alloc = alloc,
        .rows = .init(alloc),
        .render = .init(alloc),
        .buffer = .init(alloc),
        .orig_termios = orig_termios,
    };

    try edi.getWindowSize();
    return edi;
}

/// read the file rows
pub fn open(e: *Editor, file_name: []const u8) !void {
    var file = std.fs.cwd().openFile(file_name, .{}) catch return;
    defer file.close();

    while (true) {
        const line = try file.reader().readUntilDelimiterOrEofAlloc(e.alloc, '\n', 100000) orelse break;
        // editorAppendRow: add a new line
        try e.rows.append(line);
        try e.updateRow(line); // try e.render.appendSlice(line);
    }
}

pub fn deinit(e: *Editor) void {
    for (e.rows.items) |i| e.alloc.free(i);
    for (e.render.items) |i| e.alloc.free(i);
    e.rows.deinit();
    e.buffer.deinit();
    e.render.deinit();
}

/// handles the keypress
pub fn processKeyPressed(e: *Editor) !bool {
    const key = try Editor.readKey();

    switch (key) {
        CTRL_Z => {
            _ = try stdout.write("\x1b[2J");
            _ = try stdout.write("\x1b[H");
            return true;
        },
        // cursor movement keys
        @intFromEnum(Key.ARROW_UP),
        @intFromEnum(Key.ARROW_DOWN),
        @intFromEnum(Key.ARROW_RIGHT),
        @intFromEnum(Key.ARROW_LEFT),
        => e.moveCursor(key),
        @intFromEnum(Key.PAGE_UP), @intFromEnum(Key.PAGE_DOWN) => |c| {

            // positioning the cursor to the end/begin
            switch (c) {
                @intFromEnum(Key.PAGE_UP) => e.cursor.y = e.offset.y,
                @intFromEnum(Key.PAGE_DOWN) => {
                    e.cursor.y = e.offset.y + e.screen.y - 1;
                    if (e.cursor.y > e.rows.items.len) e.cursor.y = e.rows.items.len;
                },
                else => {},
            }

            const k: Key = if (key == @intFromEnum(Key.PAGE_UP)) .ARROW_UP else .ARROW_DOWN;
            var times = e.screen.y;
            while (times != 0) : (times -= 1) e.moveCursor(@intFromEnum(k));
        },
        @intFromEnum(Key.HOME) => e.cursor.x = 0,
        @intFromEnum(Key.END) => if (e.cursor.y < e.rows.items.len) {
            e.cursor.x = e.rows.items[e.cursor.y].len;
        },
        // @intFromEnum(Key.DEL) => edi.cursor.x -= 1,
        else => {},
    }

    return false;
}

fn controlKey(c: usize) usize {
    return c & 0x1f;
}

/// covert char index to render index
/// not working, i think
fn cx2rx(e: *Editor) usize {
    var rx: usize = 0;
    for (e.rows.items[e.cursor.y][0..e.cursor.x]) |c| {
        if (c == '\t') rx += (TABSTOP - 1) - (rx & TABSTOP);
        rx += 1;
    }
    return rx;
}

/// renders a row (line)
fn updateRow(e: *Editor, row: []u8) !void {
    // renders tabs as multiple space characters.
    const tabs = b: {
        var t: usize = 0;
        for (row) |char| if (char == '\t') {
            t += 1;
        };
        break :b t;
    };

    const render = try e.alloc.alloc(u8, row.len + tabs * (TABSTOP - 1) + 1);
    {
        var i: usize = 0;
        for (row, 0..) |char, j| {
            if (char != '\t') {
                render[i] = row[j];
                i += 1;
                continue;
            }
            // handles \t
            render[i] = ' ';
            i += 1;
            while (i % 8 != 0) : (i += 1) {
                render[i] = ' ';
            }
        }
    }

    try e.render.append(render);
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

    // cursor to the top-left try edi.buffer.appendSlice("\x1b[H");
    // move the cursor
    // e.cursor.y now referees to the position of the cursor within file
    try e.buffer.writer().print("\x1b[{};{}H", .{
        e.cursor.y - e.offset.y + 1,
        e.cursor.rx - e.offset.x + 1,
    });

    // show the cursor
    try e.buffer.appendSlice("\x1b[?25h");
    _ = try stdout.write(e.buffer.items);
}

/// TODO: Window size, the hard way
fn getWindowSize(e: *Editor) !void {
    var ws: std.posix.winsize = undefined;
    const errno = linux.ioctl(linux.STDIN_FILENO, linux.T.IOCGWINSZ, @intFromPtr(&ws));
    if (errno == -1 or ws.col == 0) {
        return error.CannotFindWindowSize;
    }
    e.screen.y = ws.row;
    e.screen.x = ws.col;
}

fn drawTheWellcomeScreen(e: *Editor) !void {
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

/// draw a column of (~) on the left hand side at the beginning of any line til EOF
/// using the characters within the render display
/// TODO: Clear lines one at a time
fn drawRows(e: *Editor) !void {
    for (0..e.screen.y) |y| {
        const file_row = y + e.offset.y;

        if (file_row >= e.rows.items.len) {
            // prints the WELLCOME_STRING if where is no input file
            if (e.rows.items.len == 0 and y == e.screen.y / 3) {
                try e.drawTheWellcomeScreen();
            } else {
                try e.buffer.append('~');
            }
        } else {
            const chars = e.render.items[file_row];
            var len = std.math.sub(usize, chars.len, e.offset.x) catch 0;
            if (len > e.screen.x) len = e.screen.x;
            for (0..len) |i| try e.buffer.append(chars[e.offset.x + i]);
        }

        // clear each line as we redraw them
        try e.buffer.appendSlice("\x1b[K");
        if (y < e.screen.y - 1) {
            _ = try e.buffer.appendSlice("\r\n");
        }
    }
}

fn scroll(e: *Editor) void {
    e.cursor.rx = if (e.cursor.y < e.rows.items.len) e.cx2rx() else 0;
    // checks if the cursor is above the visible window; if so, scrool up
    if (e.cursor.y < e.offset.y) e.offset.y = e.cursor.y;
    // checks if the cursor is above the bottom of the visible windows
    if (e.cursor.y >= e.offset.y + e.screen.y) e.offset.y = e.cursor.y - e.screen.y + 1;
    // same shit to x
    if (e.cursor.x < e.offset.x) e.offset.x = e.cursor.rx;
    if (e.cursor.x >= e.offset.x + e.screen.x) e.offset.x = e.cursor.rx - e.screen.x + 1;
}

fn moveCursor(e: *Editor, key: usize) void {
    var maybe_cur_row = if (e.cursor.y >= e.rows.items.len) null else e.rows.items[e.cursor.y];

    switch (key) {
        @intFromEnum(Key.ARROW_LEFT) => if (e.cursor.x != 0) {
            e.cursor.x -= 1;
        },

        // bound the cursor to the actual string size
        @intFromEnum(Key.ARROW_RIGHT) => if (maybe_cur_row) |cur_row| {
            if (e.cursor.x < cur_row.len) e.cursor.x += 1;
        },

        @intFromEnum(Key.ARROW_UP) => if (e.cursor.y != 0) {
            e.cursor.y -= 1;
        },

        // scroll logic
        @intFromEnum(Key.ARROW_DOWN) => if (e.cursor.y < e.rows.items.len) {
            e.cursor.y += 1;
        },

        else => {},
    }

    // snap cursor to end of line (move to end)
    maybe_cur_row = if (e.cursor.y >= e.rows.items.len) null else e.rows.items[e.cursor.y];
    const row_len = if (maybe_cur_row) |row| row.len else 0;
    if (e.cursor.x > row_len) e.cursor.x = row_len;
}

/// wait for one keypress, and return it.
fn readKey() !usize {
    var buff: [1]u8 = .{'0'};
    _ = try stdin.read(&buff);
    const key = buff[0];

    if (key != '\x1b') {
        return key;
    }

    // handle escape sequence
    var seq: [3]u8 = blk: {
        var s0: [1]u8 = .{0};
        if (try stdin.read(&s0) != 1) return '\x1b';

        var s1: [1]u8 = .{0};
        if (try stdin.read(&s1) != 1) return '\x1b';

        break :blk .{ s0[0], s1[0], 0 };
    };

    // NOT PAGE_{UP, DOWN} or ARROW_{UP, DOWN, ...}
    if (seq[0] == '[') {
        // PAGE_UP AND DOWN
        // page Up is sent as <esc>[5~ and Page Down is sent as <esc>[6~.
        if (seq[1] >= '0' and seq[1] <= '9') {
            seq[2] = blk: {
                var s2: [1]u8 = .{0};
                if (try stdin.read(&s2) != 1) return '\x1b';
                break :blk s2[0];
            };

            if (seq[2] == '~') switch (seq[1]) {
                '1', '7' => return @intFromEnum(Key.HOME),
                '4', '8' => return @intFromEnum(Key.END),
                '3' => return @intFromEnum(Key.DEL),
                '5' => return @intFromEnum(Key.PAGE_UP),
                '6' => return @intFromEnum(Key.PAGE_DOWN),
                else => {},
            };
        }

        // ARROW KEYS
        // '\x1b' + '[' + ('A', 'B', 'C', or 'D')
        switch (seq[1]) {
            '1', '7' => return @intFromEnum(Key.HOME),
            '4', '8' => return @intFromEnum(Key.END),
            'A' => return @intFromEnum(Key.ARROW_UP),
            'B' => return @intFromEnum(Key.ARROW_DOWN),
            'C' => return @intFromEnum(Key.ARROW_RIGHT),
            'D' => return @intFromEnum(Key.ARROW_LEFT),
            'H' => return @intFromEnum(Key.HOME),
            'F' => return @intFromEnum(Key.END),
            else => {},
        }
    }

    if (seq[0] == '0') switch (seq[1]) {
        'H' => return @intFromEnum(Key.HOME),
        'F' => return @intFromEnum(Key.END),
        else => {},
    };

    return '\x1b';
}
