const std = @import("std");

const Status = @This();
msg: []const u8 = "",
time: i64 = 0,

pub fn new(msg: []const u8) Status {
    return .{ .msg = msg, .time = std.time.timestamp() };
}
