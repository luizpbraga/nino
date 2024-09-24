const std = @import("std");
const c = @cImport(@cInclude("regex.h"));
const REGEX_T_SIZEOF = 64;
const REGEX_T_ALIGNOF = 8;

const END = "\x1b[0m";
const RED = "\x1b[91m";
const GREEN = "\x1b[92m";
const AMARELO = "\x1b[93m";
const BLUE = "\x1b[94m";
const PURPLE = "\x1b[95m";
const GREY = "\x1b[2m";
const ORANGE = "\x1b[38;5;214m";

const Regex = @This();

slice: []align(REGEX_T_ALIGNOF) u8,
alloc: std.mem.Allocator,
regex: *c.regex_t,

pub fn init(alloc: std.mem.Allocator, pattern: []const u8) !Regex {
    const slice = try alloc.alignedAlloc(u8, REGEX_T_ALIGNOF, REGEX_T_SIZEOF);
    errdefer alloc.free(slice);
    const regex: *c.regex_t = @ptrCast(slice);
    if (c.regcomp(regex, pattern.ptr, c.REG_EXTENDED) != 0) {
        return error.CompilationFailed;
    }
    return .{ .slice = slice, .regex = regex, .alloc = alloc };
}

pub fn deinit(r: *Regex) void {
    c.regfree(r.regex);
    r.alloc.free(r.slice);
}

// const Config = struct {
//     name: []const u8 = "",
//     patter: []const u8,
//     color: []const u8,
//     off: usize = 0,
// };
//
// const patterns2 = b: {
//     var p: []const u8 = "";
//     for (zig_config) |conf| {
//         p = p ++ conf.patter ++ "|";
//     }
//     break :b p[0 .. p.len - 1];
// };
//
// const zig_config = [_]Config{
//     .{ .patter = "\\b(pub|pub fn|const|var|defer|try|return|catch|extern|struct|enum|packed|if|switch|for)\\b", .color = PURPLE },
//     .{ .patter = "\\b(undefined|null)\\b", .color = LARANHA },
//     .{ .patter = "\\b(type|void|usize|f64|f32|f8|i32|i64|i128|u8|u16|u32|u64|u128)\\b", .color = AMARELO },
//     .{ .name = "functions", .patter = "\\b(\\w+\\()", .color = AZUL, .off = 1 },
//     .{ .patter = "\\b([0-9]+(\\.[0-9]+)?)", .color = AMARELO },
//     .{ .patter = "(\"[^\"]*\")", .color = VERD },
// const op = "([&\\+\\-])";
// const comment = "(//.*$)";
// };

// const patterns = std.fmt.comptimePrint("{s}|{s}|{s}|{s}|{s}|{s}", .{
//     zig_config[0].patter,
//     zig_config[1].patter,
//     zig_config[2].patter,
//     zig_config[3].patter,
//     zig_config[4].patter,
//     zig_config[5].patter,
//     // op,
//     // comment,
// });

// fn highlightKeys(r: *Regex, list: *std.ArrayList(u8)) !void {
//     errdefer list.deinit();
//     try list.append(0);
//
//     const keywords = "\\b(pub|fn|const|var|defer|try|return|catch|extern|struct|enum|packed|if|switch|for)\\b";
//     const keywords2 = "\\b(undefined|null)\\b";
//     const types = "\\b(type|void|usize|f64|f32|f8|i32|i64|i128|u8|u16|u32|u64|u128)\\b";
//     const funcs = "\\b(\\w+\\()";
//     // const number = "\\b([0-9]+(\\.[0-9]+)?)";
//     // const string1 = "(\"[^\"]*\")";
//     // const op = "([&\\+\\-])";
//     //
//
//     const patterns = std.fmt.comptimePrint("{s}|{s}|{s}|{s}|{s}|{s}", .{
//         keywords,
//         keywords2,
//         types,
//         funcs,
//         // number,
//         // string1,
//         // op,
//     });
//     if (c.regcomp(r.regex, patterns, c.REG_EXTENDED) != 0) {
//         std.debug.print("invalid regular expression", .{});
//         return error.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
//     }
//     defer c.regfree(r.regex);
//     var matches: [1]c.regmatch_t = undefined;
//     var start: usize = 0;
//
//     while (0 == c.regexec(r.regex, list.items[start..].ptr, matches.len, &matches, 0)) {
//         const math_info = matches[0];
//         // if (math_info.rm_so == -1) break;
//         const sof: usize = @intCast(math_info.rm_so);
//         const eof: usize = @intCast(math_info.rm_eo);
//
//         // const color = if (matches[1].rm_so != -1)
//         //     PURPLE
//         // else if (matches[2].rm_so != -1)
//         //     LARANHA
//         // else if (matches[3].rm_so != -1)
//         //     AMARELO
//         // else if (matches[4].rm_so != -1) b: {
//         //     eof -= 1;
//         //     break :b AZUL;
//         // } else if (matches[5].rm_so != -1)
//         //     LARANHA
//         // else if (matches[6].rm_so != -1)
//         //     VERD
//         // else
//         //     VERD;
//
//         const color = CINZA;
//         try list.insertSlice(start + eof, END);
//         try list.insertSlice(start + sof, color);
//         // std.debug.print("{s}\n", .{list.items[sof..eof]});
//         start += eof + END.len + color.len;
//     }
// }

// fn highlightCommnets(r: *Regex, list: *std.ArrayList(u8)) !?usize {
//     const comment_pattern = "//?/[^\n]*";
//     if (c.regcomp(r.regex, comment_pattern, c.REG_EXTENDED) != 0) {
//         std.debug.print("invalid regular expression", .{});
//         return error.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
//     }
//     defer c.regfree(r.regex);
//
//     var matches: [1]c.regmatch_t = undefined;
//     var start: usize = 0;
//     var begin: ?usize = null;
//     while (0 == c.regexec(r.regex, list.items[start..].ptr, 1, &matches, 0)) {
//         const math_info = matches[0];
//         if (math_info.rm_so == -1) break;
//         const sof: usize = @intCast(math_info.rm_so);
//         const eof: usize = @intCast(math_info.rm_eo);
//         const color = GREY;
//         try list.insertSlice(start + eof, END);
//         try list.insertSlice(start + sof, color);
//         begin = start + sof;
//         start += eof + END.len + color.len;
//     }
//
//     return begin;
// }

// fn highlightStrings(r: *Regex, list: *std.ArrayList(u8)) !void {
//     const string_pattern = "(\"[^\"]*\"|\\\\[^\n]*)";
//     if (c.regcomp(r.regex, string_pattern, c.REG_EXTENDED) != 0) {
//         std.debug.print("invalid regular expression", .{});
//         return error.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
//     }
//     defer c.regfree(r.regex);
//
//     var matches: [1]c.regmatch_t = undefined;
//     var start: usize = 0;
//     while (0 == c.regexec(r.regex, list.items[start..].ptr, 1, &matches, 0)) {
//         const math_info = matches[0];
//         if (math_info.rm_so == -1) break;
//         const sof: usize = @intCast(math_info.rm_so);
//         const eof: usize = @intCast(math_info.rm_eo);
//         const color = GREEN;
//         try list.insertSlice(start + eof, END);
//         try list.insertSlice(start + sof, color);
//         start += eof + END.len + color.len;
//     }
// }

// fn highlightOperators(r: *Regex, list: *std.ArrayList(u8)) !void {
//     // const numbers_and_operators_pattern = "[+-*/%=<>!&|^]";
//     const numbers_and_operators_pattern = "(\\+|\\-|\\*|\\*\\*|&|%|<|>|=|<=|>=|==|!=|!|\\?)";
//     if (c.regcomp(r.regex, numbers_and_operators_pattern, c.REG_EXTENDED) != 0) {
//         std.debug.print("invalid regular expression", .{});
//         return error.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
//     }
//     defer c.regfree(r.regex);
//
//     var matches: [1]c.regmatch_t = undefined;
//     var start: usize = 0;
//     while (0 == c.regexec(r.regex, list.items[start..].ptr, 1, &matches, 0)) {
//         const math_info = matches[0];
//         if (math_info.rm_so == -1) break;
//         const sof: usize = @intCast(math_info.rm_so);
//         const eof: usize = @intCast(math_info.rm_eo);
//         const color = LARANHA;
//         try list.insertSlice(start + eof, END);
//         try list.insertSlice(start + sof, color);
//         start += eof + END.len + color.len;
//     }
// }

// const Protect = struct {
//     start: usize = 0,
//     end: usize = 0,
// };
//
// fn highlightCommentLine(r: *Regex, buffer: *std.ArrayList(u8)) void {
//     const comment_pattern = "(//?/[^\n]*)";
//     if (c.regcomp(r.regex, comment_pattern, c.REG_EXTENDED) != 0) {
//         return error.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
//     }
//     defer c.regfree(r.regex);
//
//     var end_comment: usize = 0;
//     var matches: [1]c.regmatch_t = undefined;
//     if (0 == c.regexec(r.regex, buffer.items.ptr, 1, &matches, 0)) {
//         const math_info = matches[0];
//         const sof: usize = @intCast(math_info.rm_so);
//         const eof: usize = @intCast(math_info.rm_eo);
//         const color = GREY;
//         try buffer.insertSlice(eof, END);
//         try buffer.insertSlice(sof, color);
//         if (sof == 0) return;
//         end_comment = sof;
//     }
// }

// fn highlight(r: *Regex, line: []const u8) !void {
//     var buffer = std.ArrayList(u8).init(r.alloc);
//     defer buffer.deinit();
//     try buffer.appendSlice(line);
//     try buffer.append(0);
//     // indice na buffer de onde comeca o comentario
//     var end_comment: usize = 0;
//
//     // comments
//     {
//         const comment_pattern = "(//?/[^\n]*)";
//         if (c.regcomp(r.regex, comment_pattern, c.REG_EXTENDED) != 0) {
//             return error.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
//         }
//         defer c.regfree(r.regex);
//
//         var matches: [1]c.regmatch_t = undefined;
//         if (0 == c.regexec(r.regex, line.ptr, 1, &matches, 0)) {
//             const math_info = matches[0];
//             const sof: usize = @intCast(math_info.rm_so);
//             const eof: usize = @intCast(math_info.rm_eo);
//             const color = GRAY;
//             try buffer.insertSlice(eof, END);
//             try buffer.insertSlice(sof, color);
//             if (sof == 0) return;
//             end_comment = sof;
//         }
//     }
//
//     var start: usize = 0;
//     {
//         const string_pattern = "(\"[^\"]*\"|\\\\[^\n]*)";
//         if (c.regcomp(r.regex, string_pattern, c.REG_EXTENDED) != 0) {
//             std.debug.print("invalid regular expression", .{});
//             return error.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
//         }
//         defer c.regfree(r.regex);
//
//         var matches: [1]c.regmatch_t = undefined;
//         start = 0;
//         var start_string: usize = 0;
//         var end_string: usize = 0;
//         while (0 == c.regexec(r.regex, buffer.items[start..].ptr, 1, &matches, 0)) {
//             const math_info = matches[0];
//             const eof: usize = @intCast(math_info.rm_eo);
//             const sof: usize = @intCast(math_info.rm_so);
//             if (start + sof >= end_comment) break;
//             const color = GREEN;
//             try buffer.insertSlice(start + eof, END);
//             try buffer.insertSlice(start + sof, color);
//             start_string = start + sof;
//             end_string = start + eof;
//             start += eof + END.len + color.len;
//             end_comment += END.len + color.len;
//         }
//     }
//
//     // operators
//     {
//         const numbers_and_operators_pattern = "(\\+|\\-|\\*|\\*\\*|\\s/\\s|&|%|<|>|=|<=|>=|==|!=|!|\\?)";
//         if (c.regcomp(r.regex, numbers_and_operators_pattern, c.REG_EXTENDED) != 0) {
//             return error.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
//         }
//         defer c.regfree(r.regex);
//
//         start = 0;
//         var matches: [1]c.regmatch_t = undefined;
//         while (0 == c.regexec(r.regex, buffer.items[start..].ptr, 1, &matches, 0)) {
//             const math_info = matches[0];
//             const eof: usize = @intCast(math_info.rm_eo);
//             const sof: usize = @intCast(math_info.rm_so);
//             if (start + sof >= end_comment) break;
//             // const color = if (start + sof < end) ORANGE else GRAY;
//             const color = ORANGE;
//             try buffer.insertSlice(start + eof, END);
//             try buffer.insertSlice(start + sof, color);
//             start += eof + END.len + color.len;
//             end_comment += END.len + color.len;
//         }
//     }
//
//     std.debug.print("{s}", .{buffer.items});
// }

fn addColor(buff: *std.ArrayList(u8), text: []const u8, color: []const u8) !void {
    try buff.writer().print("{s}{s}{s}", .{ color, text, END });
}

fn highlight(alloc: anytype, code: []const u8) !void {
    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();

    const keywords2_patterns = "\\b(undefined|null|[A-Z_]+)\\b";
    const types_pattern = "\\b(anytype|anyerror|type|void|usize|f64|f32|f8|i32|i64|i128|u8|u16|u32|u64|u128|[A-Z]\\w+)\\b";
    const funcs_pattern = "\\b(\\w+\\()";
    const buildin_pattern = "\\b(@\\w+\\()";
    const number_pattern = "\\b([0-9]+(\\.[0-9]+)?)";
    const comment_pattern = "//?/[^\n]*";
    const string_pattern = "(\"[^\"]*\"|\\\\[^\n]*)";
    const operators_pattern = "(\\+|\\-|\\*|\\*\\*|\\s/\\s|&|%|<|>|=|<=|>=|==|!=|!|\\?)";
    const keywords_pattern = "\\b(errdefer|continue|break|test|inline|pub|fn|const|var|defer|try|return|catch|extern|struct|enum|packed|if|switch|while|for|and|or)\\b";

    var re_ty = try Regex.init(alloc, types_pattern);
    defer re_ty.deinit();
    var re_key = try Regex.init(alloc, keywords_pattern);
    defer re_key.deinit();
    var re_key2 = try Regex.init(alloc, keywords2_patterns);
    defer re_key2.deinit();
    var re_com = try Regex.init(alloc, comment_pattern);
    defer re_com.deinit();
    var re_str = try Regex.init(alloc, string_pattern);
    defer re_str.deinit();
    var re_op = try Regex.init(alloc, operators_pattern);
    defer re_op.deinit();
    var re_num = try Regex.init(alloc, number_pattern);
    defer re_num.deinit();
    var re_fun = try Regex.init(alloc, funcs_pattern);
    defer re_fun.deinit();
    var re_bui = try Regex.init(alloc, buildin_pattern);
    defer re_bui.deinit();

    var matches: [1]c.regmatch_t = undefined;
    var start: usize = 0;
    while (start < code.len) {
        // KEYWORDS 1
        if (0 == c.regexec(re_key.regex, code[start..].ptr, 1, &matches, 0) and matches[0].rm_so == 0) {
            const math_info = matches[0];
            const sof: usize = @intCast(math_info.rm_so);
            const eof: usize = @intCast(math_info.rm_eo);
            const match_str = code[start..][sof..eof];
            try addColor(&buffer, match_str, PURPLE);
            start += eof;
            continue;
        }

        // KEYWORDS 2
        if (0 == c.regexec(re_key2.regex, code[start..].ptr, 1, &matches, 0) and matches[0].rm_so == 0) {
            const math_info = matches[0];
            const sof: usize = @intCast(math_info.rm_so);
            const eof: usize = @intCast(math_info.rm_eo);
            const match_str = code[start..][sof..eof];
            try addColor(&buffer, match_str, ORANGE);
            start += eof;
            continue;
        }

        // BUILTIN
        if (0 == c.regexec(re_bui.regex, code[start..].ptr, 1, &matches, 0) and matches[0].rm_so == 0) {
            const math_info = matches[0];
            const sof: usize = @intCast(math_info.rm_so);
            const eof: usize = @intCast(math_info.rm_eo);
            const match_str = code[start..][sof .. eof - 1];
            try addColor(&buffer, match_str, PURPLE);
            start += eof;
            continue;
        }

        // FUNC 1
        if (0 == c.regexec(re_fun.regex, code[start..].ptr, 1, &matches, 0) and matches[0].rm_so == 0) {
            const math_info = matches[0];
            const sof: usize = @intCast(math_info.rm_so);
            const eof: usize = @intCast(math_info.rm_eo);
            const match_str = code[start..][sof..eof];
            try addColor(&buffer, match_str, BLUE);
            start += eof;
            continue;
        }

        // NUMBERS
        if (0 == c.regexec(re_num.regex, code[start..].ptr, 1, &matches, 0) and matches[0].rm_so == 0) {
            const math_info = matches[0];
            const sof: usize = @intCast(math_info.rm_so);
            const eof: usize = @intCast(math_info.rm_eo);
            const match_str = code[start..][sof..eof];
            try addColor(&buffer, match_str, ORANGE);
            start += eof;
            continue;
        }

        // OPERATORS
        if (0 == c.regexec(re_op.regex, code[start..].ptr, 1, &matches, 0) and matches[0].rm_so == 0) {
            const math_info = matches[0];
            const sof: usize = @intCast(math_info.rm_so);
            const eof: usize = @intCast(math_info.rm_eo);
            const match_str = code[start..][sof..eof];
            try addColor(&buffer, match_str, ORANGE);
            start += eof;
            continue;
        }

        // TYPES
        if (0 == c.regexec(re_ty.regex, code[start..].ptr, 1, &matches, 0) and matches[0].rm_so == 0) {
            const math_info = matches[0];
            const sof: usize = @intCast(math_info.rm_so);
            const eof: usize = @intCast(math_info.rm_eo);
            const match_str = code[start..][sof..eof];
            try addColor(&buffer, match_str, AMARELO);
            start += eof;
            continue;
        }

        // COMMENTS
        if (0 == c.regexec(re_com.regex, code[start..].ptr, 1, &matches, 0) and matches[0].rm_so == 0) {
            // const match_str = code[start..];
            // try addColor(&buffer, match_str, GREY);
            // break;
            const math_info = matches[0];
            const sof: usize = @intCast(math_info.rm_so);
            const eof: usize = @intCast(math_info.rm_eo);
            const match_str = code[start..][sof..eof];
            try addColor(&buffer, match_str, GREY);
            start += eof;
            continue;
        }

        // STRINGS
        if (0 == c.regexec(re_str.regex, code[start..].ptr, 1, &matches, 0) and matches[0].rm_so == 0) {
            const math_info = matches[0];
            const sof: usize = @intCast(math_info.rm_so);
            const eof: usize = @intCast(math_info.rm_eo);
            const match_str = code[start..][sof..eof];
            try addColor(&buffer, match_str, GREEN);
            start += eof;
            continue;
        }

        try buffer.append(code[start]);
        start += 1;
    }

    std.debug.print("{s}\n", .{buffer.items});
}

test {
    const alloc = std.testing.allocator;
    const line = @embedFile("regex.zig");
    try highlight(alloc, line);
}
