const std = @import("std");
const Row = @This();

/// rows data
chars: std.ArrayList(u8),
/// render nonprintable control character
render: std.ArrayList(u8),

pub fn asChars(r: *Row) []u8 {
    return r.chars.items;
}

pub fn asRender(r: *Row) []u8 {
    return r.render.items;
}

pub fn renderLen(r: *Row) usize {
    return r.render.items.len;
}

pub fn charsLen(r: *Row) usize {
    return r.chars.items.len;
}
