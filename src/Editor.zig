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

/// cursor coordinate x (horizontal)
cx: usize = 0,
/// cursor coordinate y (vertical)
cy: usize = 0,
/// screen rows
screenrows: usize = 0,
/// screen columns
screencols: usize = 0,
/// this little guy will hold the initial state
orig_termios: linux.termios,
/// espace sequece buffer
buffer: std.ArrayList(u8),
/// numbers of activated rows
numrows: usize = 0,
/// rows data
rows: std.ArrayList([]u8),
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
        const lines = try file.reader().readUntilDelimiterOrEofAlloc(e.alloc, '\n', 100000) orelse break;
        try e.rows.append(lines);
        e.numrows += 1;
    }
}

pub fn deinit(e: *Editor) void {
    for (e.rows.items) |i| e.alloc.free(i);
    e.rows.deinit();
    e.buffer.deinit();
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
        @intFromEnum(Key.PAGE_UP), @intFromEnum(Key.PAGE_DOWN) => {
            var times = e.screenrows;
            const k: Key = if (key == @intFromEnum(Key.PAGE_UP)) .ARROW_UP else .ARROW_DOWN;
            while (times != 0) : (times -= 1) e.moveCursor(@intFromEnum(k));
        },
        @intFromEnum(Key.HOME) => e.cx = 0,
        @intFromEnum(Key.END) => e.cx = e.screencols - 1,
        // @intFromEnum(Key.DEL) => edi.cx -= 1,
        else => {},
    }

    return false;
}

fn controlKey(c: usize) usize {
    return c & 0x1f;
}

/// see ncurses library for terminal capabilities
/// Escape sequence (1byte): \x1b[ allow the terminal to do text formatting task (colour, moving, clearing)
/// https://vt100.net/docs/vt100-ug/chapter3.html#ED
pub fn refreshScreen(e: *Editor) !void {
    defer e.buffer.clearAndFree();

    // hide the cursor
    try e.buffer.appendSlice("\x1b[?25l");
    // clear all [2J:
    // try edi.buffer.appendSlice("\x1b[2J"); // let's use \x1b[K instead
    // reposition the cursor at the top-left corner; H command (Cursor Position)
    try e.buffer.appendSlice("\x1b[H");

    // new line tildes (~)
    try e.getWindowSize();
    try e.drawRows();

    // cursor to the top-left try edi.buffer.appendSlice("\x1b[H");
    // move the cursor
    try e.buffer.writer().print("\x1b[{};{}H", .{ e.cy + 1, e.cx + 1 });

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
    e.screenrows = ws.row;
    e.screencols = ws.col;
}

/// h: LEGT
/// k: UP
/// j: DOWN
/// l: RIGHT
fn moveCursor(e: *Editor, key: usize) void {
    const currx = e.cx;
    const curry = e.cy;
    const maxx = e.screencols;
    const maxy = e.screenrows;

    switch (key) {
        @intFromEnum(Key.ARROW_LEFT) => if (currx != 0) {
            e.cx -= 1;
        },

        @intFromEnum(Key.ARROW_UP) => if (curry != 0) {
            e.cy -= 1;
        },

        @intFromEnum(Key.ARROW_DOWN) => if (curry != maxy - 1) {
            e.cy += 1;
        },

        @intFromEnum(Key.ARROW_RIGHT) => if (currx != maxx - 1) {
            e.cx += 1;
        },
        else => {},
    }
}

fn drawTheWellComeScreen(e: *Editor) !void {
    // BUG: tiny terminals: will it fit?
    const welllen = WELLCOME_STRING.len;
    var pedding = (e.screencols - welllen) / 2;

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
/// TODO: Clear lines one at a time
fn drawRows(e: *Editor) !void {
    for (0..e.screenrows) |y| {
        if (y >= e.numrows) {
            // prints the WELLCOME_STRING if where is no input file
            if (e.numrows == 0 and y == e.screenrows / 3) {
                try e.drawTheWellComeScreen();
            } else {
                try e.buffer.append('~');
            }
        } else {
            // BUG: the size must respect the terminal limits
            const chars = e.rows.items[y];
            var len = chars.len;
            if (chars.len > e.screencols) len = e.screencols;
            try e.buffer.appendSlice(chars);
        }

        // clear each line as we redraw them
        try e.buffer.appendSlice("\x1b[K");
        if (y < e.screenrows - 1) {
            _ = try e.buffer.appendSlice("\r\n");
        }
    }
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
