const std = @import("std");
const linux = std.os.linux;
const Editor = @import("Editor.zig");
const TCSAFLUSH = linux.TCSA.FLUSH;

pub const Terminal = @This();

/// changes the terminal attribute
pub fn initRawMode(edi: *const Editor) !void {
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
    const errno = linux.tcsetattr(linux.STDIN_FILENO, TCSAFLUSH, &new_termios);
    if (errno == -1) return error.CannotWriteTheNewTerminalAttributes;
}

pub fn deinitRawMode(edi: *const Editor) void {
    _ = linux.tcsetattr(linux.STDIN_FILENO, TCSAFLUSH, &edi.orig_termios);
}
