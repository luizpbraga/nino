const std = @import("std");
const Terminal = @import("Terminal.zig");
const Editor = @import("Editor.zig");
const io = @import("io.zig");
const asKey = @import("keys.zig").asKey;

// SOME default keymaps:
//canonical/cooked mode: char in read when BACKSPACE is pressed
//ctrl-C: kill the process
//ctrl-D: end of file
//ctrl-s:stop sending output
//ctrl-q:resume
pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var edi: Editor = try .init(alloc);
    defer edi.deinit();

    // open the user file, if exist
    var arg = std.process.args();
    _ = arg.skip();
    if (arg.next()) |file_name| {
        try io.open(&edi, file_name);
    }

    // vim map ex
    try edi.keyremap.map(.normal, asKey('o'), &.{ .END, .ENTER, asKey('i') });

    // starts the editor layout
    try Terminal.initRawMode(&edi);
    defer Terminal.deinitRawMode(&edi);

    while (true) {
        try edi.refreshScreen();
        if (try edi.processKeyPressed()) break;
    }
}

test "simple test" {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try bw.flush();
    //const alloc = std.testing.allocator;
    //var edi: Editor = try .init(alloc);
    //defer edi.deinit();
    //try Terminal.initRawMode(&edi);
    //defer Terminal.deinitRawMode(&edi);
    // try edi.getWindowSize();
    try stdout.writeAll("\x1b[K");
    try bw.flush();
    // try writer.print("\x1b[{[x]},{[y]}H", edi.screen);
    // try writer.print("\x1b[K", .{});
}
