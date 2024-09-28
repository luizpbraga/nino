const std = @import("std");
const Terminal = @import("Terminal.zig");
const Editor = @import("Editor.zig");
const io = @import("io.zig");
const asKey = @import("keys.zig").asKey;

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
        try edi.setLight(file_name);
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
