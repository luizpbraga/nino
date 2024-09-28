const std = @import("std");
const c = @cImport(@cInclude("regex.h"));
const REGEX_T_SIZEOF = 64;
const REGEX_T_ALIGNOF = 8;

const END = "\x1b[0m";
const RED = "\x1b[91m";
const GREEN = "\x1b[92m";
const AMARELO = "\x1b[93m";
const LIGHT_BLUE = "\x1b[1;36m";
const BLUE = "\x1b[94m";
const PURPLE = "\x1b[95m";
const GREY = "\x1b[2m";
const ORANGE = "\x1b[38;5;214m";

pub const HighLight = @This();

slice: [Tag.LEN]RegexShitType,
filetype: FileType = .non,

const FileType = enum(u8) { zig, c, py, non };

const RegexShitType = []align(REGEX_T_ALIGNOF) u8;

const SyntaxInfo = struct {
    group: usize = 0,
    color: []const u8 = PURPLE,
    pattern: []const u8,
};

const Tag = enum(u8) {
    keywords1 = 0,
    keywords2,
    buildin,
    funcs,
    types,
    operators,
    number,
    comment,
    string,

    const LEN = std.meta.fields(Tag).len;
};

const FileSyntaxInfo = std.EnumMap(Tag, SyntaxInfo);

pub fn init(alloc: std.mem.Allocator, file_ext: ?[]const u8) !?HighLight {
    const ext = file_ext orelse return null;

    const info, const filetype: FileType = if (std.mem.endsWith(u8, ext, ".zig")) b: {
        break :b .{ ZIG_SYNTAX_INFO, .zig };
    } else if (std.mem.endsWith(u8, ext, ".c")) b: {
        break :b .{ C_SYNTAX_INFO, .c };
    } else if (std.mem.endsWith(u8, ext, ".py")) b: {
        break :b .{ PYTHON_SYNTAX_INFO, .py };
    } else return null;

    var slice: [Tag.LEN]RegexShitType = undefined;
    for (std.meta.tags(Tag)) |tag| {
        const ctx = info.get(tag) orelse continue;
        const pattern = ctx.pattern;

        const mem = try alloc.alignedAlloc(u8, REGEX_T_ALIGNOF, REGEX_T_SIZEOF);
        errdefer alloc.free(mem);
        slice[@intFromEnum(tag)] = mem;

        const regex: *c.regex_t = @ptrCast(mem);
        if (c.regcomp(regex, pattern.ptr, c.REG_EXTENDED) != 0) {
            std.debug.print("patter: {s}", .{pattern});
            return error.CompilationFailed;
        }
    }

    return .{ .slice = slice, .filetype = filetype };
}

pub fn deinit(r: *HighLight, alloc: std.mem.Allocator) void {
    const f = r.getSyntaxInfo();
    for (std.meta.tags(Tag)) |tag| {
        const mem = r.slice[@intFromEnum(tag)];
        if (f.contains(tag)) {
            c.regfree(@ptrCast(mem));
            alloc.free(mem);
        }
    }
}

fn regexxx(r: *HighLight, tag: Tag) *c.regex_t {
    return @ptrCast(r.slice[@intFromEnum(tag)]);
}

fn addColor(buff: *std.ArrayList(u8), text: []const u8, color: []const u8) !void {
    try buff.writer().print("{s}{s}{s}", .{ color, text, END });
}

fn getSyntaxInfo(r: *HighLight) FileSyntaxInfo {
    return switch (r.filetype) {
        .zig => ZIG_SYNTAX_INFO,
        .c => C_SYNTAX_INFO,
        .py => PYTHON_SYNTAX_INFO,
        .non => FileSyntaxInfo.init(.{}),
    };
}

pub fn illuminate(r: *HighLight, buffer: *std.ArrayList(u8), code: []const u8) !void {
    var matches: [2]c.regmatch_t = undefined;
    var start: usize = 0;
    const sinfo = r.getSyntaxInfo();
    loop: while (start < code.len) {
        for (std.meta.tags(Tag)) |tag| {
            const i = sinfo.get(tag) orelse continue;
            if (0 == c.regexec(r.regexxx(tag), code[start..].ptr, i.group + 1, &matches, 0) and matches[0].rm_so == 0) {
                const info = matches[i.group];
                const sof: usize = @intCast(info.rm_so);
                const eof: usize = @intCast(info.rm_eo);
                if (start > code.len) break;
                const txt = code[start..][sof..eof];
                try addColor(buffer, txt, i.color);
                start += eof;
                continue :loop;
            }
        }

        try buffer.append(code[start]);
        start += 1;
    }
}

pub fn illuminateAll(r: *HighLight, buffer: *std.ArrayList(u8)) !void {
    var matches: [2]c.regmatch_t = undefined;
    var start: usize = 0;
    const sinfo = r.getSyntaxInfo();

    const code = try buffer.allocator.dupeZ(u8, buffer.items);
    defer buffer.allocator.free(code);

    loop: while (start < code.len) {
        for (std.meta.tags(Tag)) |tag| {
            const i = sinfo.get(tag) orelse continue;
            if (0 == c.regexec(r.regexxx(tag), code[start..].ptr, i.group + 1, &matches, 0) and matches[0].rm_so == 0) {
                const info = matches[i.group];
                const sof: usize = @intCast(info.rm_so);
                const eof: usize = @intCast(info.rm_eo);
                const txt = code[start..][sof..eof];
                try addColor(buffer, txt, i.color);
                start += eof;
                continue :loop;
            }
        }
        try buffer.append(code[start]);
        start += 1;
    }
}

const ZIG_SYNTAX_INFO: FileSyntaxInfo = blk: {
    const types_pattern = "\\b(align|anytype|anyerror|type|void|usize|f64|f32|f8|i32|i64|i128|u8|u16|u32|u64|u128|\\b[A-Z]\\w*\\b)\\b";
    const funcs_pattern = "([a-zA-Z_0-9]+)\\(";
    const string_pattern = "(\"[^\"]*\"|\\\\[^\n]*|'.')";
    const number_pattern = "\\b([0-9]+(\\.[0-9]+)?)";
    const buildin_pattern = "(@[a-zA-Z]+)\\(";
    const comment_pattern = "//?/[^\n]*";
    const keywords_pattern = "\\b(else|orelse|errdefer|continue|break|test|inline|pub|fn|const|var|defer|try|return|catch|extern|struct|enum|packed|if|switch|while|for|\\sand\\s|\\sor\\s)\\b";
    const operators_pattern = "(\\+|\\-|\\*|\\*\\*|\\s/\\s|&|%|<|>|=|<=|>=|==|!=|!|\\?)";
    const keywords2_patterns = "\\b(undefined|null|[A-Z_]+)\\b";
    break :blk .init(.{
        .keywords1 = .{ .pattern = keywords_pattern },
        .keywords2 = .{ .pattern = keywords2_patterns, .color = ORANGE },
        .buildin = .{ .pattern = buildin_pattern, .group = 1 },
        .funcs = .{ .pattern = funcs_pattern, .group = 1, .color = BLUE },
        .types = .{ .pattern = types_pattern, .color = AMARELO },
        .operators = .{ .pattern = operators_pattern, .color = LIGHT_BLUE },
        .number = .{ .pattern = number_pattern, .color = RED },
        .comment = .{ .pattern = comment_pattern, .color = GREY },
        .string = .{ .pattern = string_pattern, .color = GREEN },
    });
};

const PYTHON_SYNTAX_INFO: FileSyntaxInfo = blk: {
    // Padrões para diferentes tokens de Python
    const keyword_pattern = "\\b(def|return|if|else|elif|for|while|class|import|from|as|pass|break|continue|and|or|not|in|is|with|try|except|raise|finally|lambda|global|nonlocal|assert|yield|del)\\b";
    const identifier_pattern = "\\b[a-zA-Z_][a-zA-Z0-9_]*\\b";
    _ = identifier_pattern; // autofix
    const string_pattern = "(\"\"\"([^\"\\\\]*(\\\\.[^\"\\\\]*)*)\"\"\"|\'\'\'([^\'\\\\]*(\\\\.[^\'\\\\]*)*)\'\'\'|\"([^\"\\\\]*(\\\\.[^\"\\\\]*)*)\"|\'([^\'\\\\]*(\\\\.[^\'\\\\]*)*)\')";
    const comment_pattern = "#[^\n]*";
    const number_pattern = "\\b[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?\\b";
    const operator_pattern = "(\\+|-|\\*|\\/|%|=|==|!=|<=|>=|<|>|and|or|not|is|in)";
    const punctuation_pattern = "[,\\(\\)\\[\\]\\{\\}\\.:]";
    break :blk .init(.{
        .keywords1 = .{ .pattern = keyword_pattern },
        .keywords2 = .{ .pattern = punctuation_pattern, .color = ORANGE },
        // .buildin = .{ .pattern = identifier_pattern, .group = 1 },
        // .funcs = .{ .pattern = identifier_pattern, .group = 1, .color = BLUE },
        // .types = .{ .pattern = types_pattern, .color = AMARELO },
        .operators = .{ .pattern = operator_pattern, .color = LIGHT_BLUE },
        .number = .{ .pattern = number_pattern, .color = RED },
        .comment = .{ .pattern = comment_pattern, .color = GREY },
        .string = .{ .pattern = string_pattern, .color = GREEN },
    });
};

const C_SYNTAX_INFO: FileSyntaxInfo = blk: {
    const keyword_pattern = "\\b(include|enum|struct|return|if|else|while|for|break|continue|switch|const)\\b";
    const types_pattern = "\\b(int|void|float|long|shot|char)\\b";
    // const identifier_pattern = "\\b[a-zA-Z_][a-zA-Z0-9_]*\\b";
    // const string_pattern = "\"([^\"\\\\]*(\\\\.[^\"\\\\]*)*)\"";
    const comment_pattern = "//?/[^\n]*";
    // const comment_pattern = "/\\*[^*]*\\*+([^/*][^*]*\\*+)*/|//.*";
    const number_pattern = "\\b[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?\\b";
    // const operator_pattern = "(\\+|-|\\*|\\/|=|==|!=|<=|>=|<|>)";
    const operators_pattern = "(\\+|\\-|\\*|\\*\\*|\\s/\\s|&|%|<|>|=|<=|>=|==|!=|!|\\?)";
    const punctuation_pattern = "[;\\{\\}\\(\\)]";
    const funcs_pattern = "([a-zA-Z_0-9]+)\\(";
    const string_pattern = "(\"[^\"]*\"|\\\\[^\n]*|'.')";
    break :blk .init(.{
        .keywords1 = .{ .pattern = keyword_pattern },
        .keywords2 = .{ .pattern = punctuation_pattern, .color = LIGHT_BLUE },
        .buildin = .{ .pattern = funcs_pattern, .group = 1, .color = BLUE },
        .funcs = .{ .pattern = funcs_pattern, .group = 1, .color = BLUE },
        .types = .{ .pattern = types_pattern, .color = AMARELO },
        .operators = .{ .pattern = operators_pattern, .color = LIGHT_BLUE },
        .number = .{ .pattern = number_pattern, .color = RED },
        .comment = .{ .pattern = comment_pattern, .color = GREY },
        .string = .{ .pattern = string_pattern, .color = GREEN },
    });
};

// test {
//     const alloc = std.testing.allocator;
//
//     var highlight = try HighLight.init(alloc, HighLight.zig_ctx);
//     defer highlight.deinit(alloc);
//
//     var file = try std.fs.cwd().openFile("Editor.zig", .{ .mode = .read_only });
//     defer file.close();
//
//     var buf: [1000]u8 = undefined;
//     while (true) {
//         const line = try file.reader().readUntilDelimiterOrEof(&buf, '\n') orelse break;
//         try highlight.illuminate(alloc, line);
//     }
// }
