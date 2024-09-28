const std = @import("std");
const Editor = @import("Editor.zig");
const c = @cImport(@cInclude("regex.h"));
const REGEX_T_SIZEOF = 64;
const REGEX_T_ALIGNOF = 8;

const END = "\x1b[0m";
const INV = "\x1b[7m";
const RED = "\x1b[91m";
const VERD = "\x1b[92m";
const AMARELO = "\x1b[93m";
const AZUL = "\x1b[94m";
const PURPLE = "\x1b[95m";
const CINZA = "\x1b[2m";
const LARANHA = "\x1b[38;5;214m";

const Regex = @This();

const Meta = struct {
    start: usize,
    end: usize,
    line: usize,
    counter: usize,
};

slice: []align(REGEX_T_ALIGNOF) u8,
alloc: std.mem.Allocator,
regex: ?*c.regex_t,
patterns: ?[]const u8 = null,
meta: ?[]Meta = null,
cursor: usize = 0,

pub fn init(alloc: std.mem.Allocator) !Regex {
    const slice = try alloc.alignedAlloc(u8, REGEX_T_ALIGNOF, REGEX_T_SIZEOF);
    const regex: *c.regex_t = @ptrCast(slice);
    return .{ .slice = slice, .regex = regex, .alloc = alloc };
}

pub fn compile(re: *Regex, patterns: []const u8) !void {
    const patter = try re.alloc.dupeZ(u8, patterns);
    defer re.alloc.free(patter);
    if (c.regcomp(re.regex, patter.ptr, c.REG_EXTENDED) != 0) {
        return error.SomeShitIsNotOk;
    }
    re.patterns = patterns;
}

pub fn free(re: *Regex) void {
    re.patterns = null;
    c.regfree(re.regex);
}

pub fn deinit(re: *Regex) void {
    if (re.meta) |meta| re.alloc.free(meta);
    re.alloc.free(re.slice);
}

pub fn applySearch(re: *Regex, code: *std.ArrayList(u8)) !void {
    if (re.patterns == null) return;

    if (code.items.len == 0) return;

    // const len = code.items.len;
    try code.append(0);

    var matches: [1]c.regmatch_t = undefined;
    var start: usize = 0;
    while (0 == c.regexec(re.regex, code.items[start..].ptr, matches.len, &matches, 0)) {
        const math_info = matches[0];
        const eof: usize = @intCast(math_info.rm_eo);
        const sof: usize = @intCast(math_info.rm_so);
        try code.insertSlice(start + eof, END);
        try code.insertSlice(start + sof, INV);
        start += eof + END.len + INV.len;
    }

    _ = code.pop();

    // if (len == code.items.len and len != 0) {
    //     re.patterns = null;
    //     return error.NoMatch;
    // }
}

pub fn applySearchRows(re: *Regex, rows: anytype, patterns: []const u8) !usize {
    re.undo(rows);

    const patter = try re.alloc.dupeZ(u8, patterns);
    defer re.alloc.free(patter);
    if (c.regcomp(re.regex, patter.ptr, c.REG_EXTENDED) != 0) {
        return error.SomeShitIsNotOk;
    }
    defer c.regfree(re.regex);

    var meta = std.ArrayList(Meta).init(re.alloc);
    defer meta.deinit();

    var counter: usize = 0;
    for (rows.items, 0..) |row, line| {
        try row.render.append(0);
        var matches: [1]c.regmatch_t = undefined;
        var start: usize = 0;
        while (0 == c.regexec(re.regex, row.render.items[start..].ptr, matches.len, &matches, 0)) {
            const math_info = matches[0];
            const eof: usize = @intCast(math_info.rm_eo);
            const sof: usize = @intCast(math_info.rm_so);
            try row.render.insertSlice(start + eof, END);
            try row.render.insertSlice(start + sof, INV);
            try meta.append(.{
                .start = start + sof,
                .end = start + eof,
                .line = line,
                .counter = counter,
            });
            start += eof + END.len + INV.len;
            counter += 1;
        }
        _ = row.render.pop();
    }

    if (meta.items.len != 0) {
        re.meta = try meta.toOwnedSlice();
    }

    return counter;
}

pub fn highlight(re: *Regex, buff: anytype) !void {
    try buff.append(0);
    defer _ = buff.pop();

    var size: usize = 0;
    var start: usize = 0;
    var matches: [1]c.regmatch_t = undefined;
    while (0 == c.regexec(re.regex, buff.items[start..].ptr, matches.len, &matches, 0)) {
        const math_info = matches[0];
        const eof: usize = @intCast(math_info.rm_eo);
        const sof: usize = @intCast(math_info.rm_so);
        try buff.insertSlice(start + eof, END);
        try buff.insertSlice(start + sof, INV);
        start += eof + END.len + INV.len;
        size += END.len + INV.len;
    }
}

pub fn undo(re: *Regex, rows: anytype) void {
    re.free();
    const meta = re.meta orelse return;
    defer re.alloc.free(meta);

    std.mem.reverse(Meta, meta);
    for (meta) |m| {
        for (END.len) |_| _ = rows.items[m.line].render.orderedRemove(m.end + END.len);
        for (INV.len) |_| _ = rows.items[m.line].render.orderedRemove(m.start);
    }

    re.meta = null;
}

// test {
//     const alloc = std.testing.allocator;
//     var r = try Regex.init(alloc);
//     defer r.deinit();
//
//     r.patterns = "const";
//     var list = std.ArrayList(u8).init(r.alloc);
//     defer list.deinit();
//     try list.appendSlice(@embedFile("Editor.zig"));
//     try r.applySearch(&list);
//     std.debug.print("{s}", .{list.items});
// }
