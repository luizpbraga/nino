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

    /// wait for one keypress, and return it.
    fn readKey() !u8 {
        var buff: [1]u8 = .{'0'};
        // while (0 != try stdin.read(&buff)) {}
        _ = try stdin.read(&buff);
        return buff[0];
    }
};

/// deals with low-level terminal input and mapping
const Editor = struct {
    const CTRL_Z = Editor.controlKey('z');

    screenrows: usize = 0,
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
    fn processKey(_: *const Editor) !bool {
        const char = try Terminal.readKey();
        switch (char) {
            CTRL_Z => {
                _ = try stdout.write("\x1b[2J");
                _ = try stdout.write("\x1b[H");
                return true;
            },
            else => {
                std.debug.print("{c}", .{char});
                return false;
            },
        }
    }

    fn controlKey(c: u8) u8 {
        return c & 0x1f;
    }

    // see ncurses library for terminal capabilities
    fn refreshScreen(edi: *Editor) !void {
        defer edi.buffer.clearAndFree();
        // 4 bytes
        // byte 1: \x1b Escape character (27 in decimal)
        // Escape sequence: \x1b[
        //  allow the terminal to do text formatting task (colour, moving, clearing)
        // https://vt100.net/docs/vt100-ug/chapter3.html#ED
        try edi.buffer.appendSlice("\x1b[2J");
        // reposition the cursor at the top-left corner
        // H command (Cursor Position)
        try edi.buffer.appendSlice("\x1b[H");

        // new line tildes
        try edi.getWindowSize();
        try edi.drawRows();

        try edi.buffer.appendSlice("\x1b[H");

        _ = try stdout.write(edi.buffer.items);
    }

    fn getWindowSize(edi: *Editor) !void {
        var ws: std.posix.winsize = undefined;
        const errno = linux.ioctl(STDIN_FILENO, linux.T.IOCGWINSZ, @intFromPtr(&ws));
        if (errno == -1 or ws.col == 0) return error.CannotFindWindowSize;
        edi.screenrows = ws.row;
        edi.screencols = ws.col;
    }

    /// draw a column of (~) on the left hand side at the beginning of any line til EOF
    fn drawRows(edi: *Editor) !void {
        for (0..edi.screenrows - 1) |_| {
            try edi.buffer.appendSlice("~\r\n");
        }
        _ = try edi.buffer.append('~');
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
        if (try edi.processKey()) break;
    }
}

test "simple test" {
    std.debug.print("FUCK PYTHON", .{});
}
