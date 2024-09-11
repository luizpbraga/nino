const std = @import("std");
const Terminal = @import("Terminal.zig");
const Editor = @import("Editor.zig");
const io = @import("io.zig");

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
