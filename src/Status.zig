const std = @import("std");

const Status = @This();
msg: [80]u8 = undefined,
time: i64 = 0,

pub fn new(comptime fmt: []const u8, args: anytype) !Status {
    var s: Status = .{};
    _ = try std.fmt.bufPrint(&s.msg, fmt, args);
    s.time = std.time.timestamp();
    return s;
}
