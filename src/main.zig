const std = @import("std");
const linux = std.os.linux;
const ascii = std.ascii;
const stdin = std.io.getStdIn();
const stdout = std.io.getStdOut();
const reader = stdin.reader();

const STDIN_FILENO = linux.STDIN_FILENO;
/// this control when to apply the terminal changes
const TCSAFLUSH = linux.TCSA.FLUSH;

const Terminal = struct {
    /// changes the terminal attribute
    fn initRawMode(edi: *const Editor) !void {
        // change the current config:
        var new_termios = edi.orig_termios;

        new_termios.lflag = .{
            // The ECHO causes each key to be printed (wee turn it of)
            .ECHO = false,
            // ICANON turn canonical off
            .ICANON = false,
            // dont terminete the process with ctrl-C (SEND SIGINT)
            // or dont suspend the process (SEND SIGTSTP)
            .ISIG = false,
            // Disable Ctrl-V
            .IEXTEN = false,
        };

        new_termios.iflag = .{
            // stops data from being transmitted ctrl-s until ctrl-q
            .IXON = false,
            // stops transforming \r into \n, also allow ctrl-M
            .ICRNL = false,
            // NAO SEI
            .INPCK = false,
            .BRKINT = false,
            .ISTRIP = false,
        };
        // \n = \r\n
        new_termios.oflag = .{ .OPOST = false };
        new_termios.cflag = .{ .CSIZE = .CS8 };

        // cc: control character
        // read will return sun as possible (0 bytes)
        new_termios.cc[@intFromEnum(linux.V.MIN)] = 0;
        // 1 millisecond: time before read returns
        new_termios.cc[@intFromEnum(linux.V.TIME)] = 1;

        //the write the new custom terminal attribute
        const errno = linux.tcsetattr(STDIN_FILENO, TCSAFLUSH, &new_termios);
        if (errno == -1) return error.CannotWriteTheNewTerminalAttributes;
    }

    fn deinitRawMode(edi: *const Editor) void {
        _ = linux.tcsetattr(STDIN_FILENO, TCSAFLUSH, &edi.orig_termios);
    }
};

/// deals with low-level terminal input and mapping
const Editor = struct {
    const VERSION = "0.0.1";
    const WELLCOME_STRING = "NINO editor -- version " ++ VERSION;
    const CTRL_Z = controlKey('z');

    const Key = enum(usize) {
        ARROW_LEFT = 1000,
        ARROW_RIGHT,
        ARROW_UP,
        ARROW_DOWN,
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
    buffer: std.ArrayList(u8),

    /// Read the current terminal attributes into raw
    /// and save the terminal state
    fn init(alloc: std.mem.Allocator) !Editor {
        var orig_termios: linux.termios = undefined;
        const errno = linux.tcgetattr(STDIN_FILENO, &orig_termios);
        if (errno == -1) return error.CannotReadTheCurrentTerminalAttributes;
        var edi: Editor = .{ .orig_termios = orig_termios, .buffer = .init(alloc) };
        try edi.getWindowSize();
        return edi;
    }

    fn deinit(edi: *Editor) void {
        edi.buffer.deinit();
    }

    /// handles the keypress
    fn processKeyPressed(edi: *Editor) !bool {
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
            => edi.moveCursor(key),
            @intFromEnum(Key.PAGE_UP), @intFromEnum(Key.PAGE_DOWN) => {
                var times = edi.screenrows;
                const k: Key = if (key == @intFromEnum(Key.PAGE_UP)) .ARROW_UP else .ARROW_DOWN;
                while (times != 0) : (times -= 1) edi.moveCursor(@intFromEnum(k));
            },
            @intFromEnum(Key.HOME) => edi.cx = 0,
            @intFromEnum(Key.END) => edi.cx = edi.screencols - 1,
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
    fn refreshScreen(edi: *Editor) !void {
        defer edi.buffer.clearAndFree();

        // hide the cursor
        try edi.buffer.appendSlice("\x1b[?25l");
        // clear all [2J:
        // try edi.buffer.appendSlice("\x1b[2J"); // let's use \x1b[K instead
        // reposition the cursor at the top-left corner; H command (Cursor Position)
        try edi.buffer.appendSlice("\x1b[H");

        // new line tildes (~)
        try edi.getWindowSize();
        try edi.drawRows();

        // cursor to the top-left try edi.buffer.appendSlice("\x1b[H");
        // move the cursor
        try edi.buffer.writer().print("\x1b[{};{}H", .{ edi.cy + 1, edi.cx + 1 });

        // show the cursor
        try edi.buffer.appendSlice("\x1b[?25h");
        _ = try stdout.write(edi.buffer.items);
    }

    /// TODO: Window size, the hard way
    fn getWindowSize(edi: *Editor) !void {
        var ws: std.posix.winsize = undefined;
        const errno = linux.ioctl(STDIN_FILENO, linux.T.IOCGWINSZ, @intFromPtr(&ws));
        if (errno == -1 or ws.col == 0) {
            return error.CannotFindWindowSize;
        }
        edi.screenrows = ws.row;
        edi.screencols = ws.col;
    }

    /// h: LEGT
    /// k: UP
    /// j: DOWN
    /// l: RIGHT
    fn moveCursor(edi: *Editor, key: usize) void {
        const currx = edi.cx;
        const curry = edi.cy;
        const maxx = edi.screencols;
        const maxy = edi.screenrows;

        switch (key) {
            @intFromEnum(Key.ARROW_LEFT) => if (currx != 0) {
                edi.cx -= 1;
            },

            @intFromEnum(Key.ARROW_UP) => if (curry != 0) {
                edi.cy -= 1;
            },

            @intFromEnum(Key.ARROW_DOWN) => if (curry != maxy - 1) {
                edi.cy += 1;
            },

            @intFromEnum(Key.ARROW_RIGHT) => if (currx != maxx - 1) {
                edi.cx += 1;
            },
            else => {},
        }
    }

    /// draw a column of (~) on the left hand side at the beginning of any line til EOF
    /// TODO: Clear lines one at a time
    fn drawRows(edi: *Editor) !void {
        for (0..edi.screenrows) |y| {
            // prints the WELLCOME_STRING
            if (y == edi.screenrows / 3) {
                // BUG: tiny terminals: will it fit?
                const welllen = WELLCOME_STRING.len;
                var pedding = (edi.screencols - welllen) / 2;

                if (pedding > 0) {
                    try edi.buffer.append('~');
                    pedding -= 1;
                }

                while (pedding != 0) : (pedding -= 1) {
                    try edi.buffer.append(' ');
                }

                try edi.buffer.appendSlice(WELLCOME_STRING);
            } else {
                try edi.buffer.append('~');
            }

            // clear each line as we redraw them
            try edi.buffer.appendSlice("\x1b[K");
            if (y < edi.screenrows - 1) {
                _ = try edi.buffer.appendSlice("\r\n");
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
};

// SOME default keymaps:
//canonical/cooked mode: char in read when BACKSPACE is pressed
//ctrl-C: kill the process
//ctrl-D: end of file
//ctrl-s:stop sending output
//ctrl-q:resume
pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const alloc = gpa.allocator();
    defer if (gpa.deinit() == .leak) @panic("LEAK");

    var edi: Editor = try .init(alloc);
    defer edi.deinit();

    // starts the editor layout
    try Terminal.initRawMode(&edi);
    defer Terminal.deinitRawMode(&edi);

    while (true) {
        try edi.refreshScreen();
        if (try edi.processKeyPressed()) break;
    }
}

test "simple test" {
    std.debug.print("FUCK PYTHON", .{});
}
