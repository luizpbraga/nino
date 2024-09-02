const std = @import("std");
const linux = std.os.linux;
const ascii = std.ascii;
const stdin = std.io.getStdIn();

const RawMode = struct {
    /// do not modify this field
    orig_termios: linux.termios,

    const STDIN_FILENO = linux.STDIN_FILENO;
    // this control when to apply the terminal changes
    const TCSAFLUSH = linux.TCSA.FLUSH;

    /// changes the terminal attribute
    fn init() RawMode {
        var orig_termios: linux.termios = undefined;
        // this will read the current terminal attributes into raw
        _ = linux.tcgetattr(STDIN_FILENO, &orig_termios);
        // change the current config:
        orig_termios.lflag = .{
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
        orig_termios.iflag = .{
            // stops data from being transmitted ctrl-s until ctrl-q
            .IXON = false,
            // stops transformin \r into \n, also allow ctrl-M
            .ICRNL = false,
            // NAO SEI
            .INPCK = false,
            .BRKINT = false,
            .ISTRIP = false,
        };
        // \n = \r\n
        orig_termios.oflag = .{ .OPOST = false };
        orig_termios.cflag = .{ .CSIZE = .CS8 };

        // cc: control character
        // read will return sun as possible (0 bytes)
        orig_termios.cc[@intFromEnum(linux.V.MIN)] = 0;
        // 1 millisecond: time before read returns
        orig_termios.cc[@intFromEnum(linux.V.TIME)] = 1;

        //the write the new custom terminal attribute
        _ = linux.tcsetattr(STDIN_FILENO, TCSAFLUSH, &orig_termios);

        return .{ .orig_termios = orig_termios };
    }

    fn deinit(self: *RawMode) void {
        self.orig_termios.lflag = .{ .ECHO = !false };
        _ = linux.tcsetattr(STDIN_FILENO, TCSAFLUSH, &self.orig_termios);
    }
};

fn controlKey(c: u8) u8 {
    return c & 0x1f;
}

//canonical/cooked mode: char in read when BACKSPACE is pressed
//ctrl-C: kill the process
//ctrl-D: end of file
//ctrl-s:stop sending output
//ctrl-q:resume
pub fn main() !void {
    var raw_mode: RawMode = .init();
    defer raw_mode.deinit();

    var buff: [1]u8 = .{'0'};
    while (true) {
        _ = try stdin.read(&buff);

        const byte = buff[0];

        // if (ascii.isPrint(byte))
        std.debug.print("({d},{c})\r\n", .{ byte, byte });

        if (byte == controlKey('z')) break; // without this line, with fuck ourselves in RawModeA
    }
}

test "simple test" {
    std.debug.print("FUCK PYTHON", .{});
}
