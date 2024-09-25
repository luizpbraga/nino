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

const Regex = @This();

slice: []align(REGEX_T_ALIGNOF) u8,
alloc: std.mem.Allocator,
regex: *c.regex_t,

// this function need to be generalized
pub const HighLight = struct {
    const types_pattern = "\\b(align|anytype|anyerror|type|void|usize|f64|f32|f8|i32|i64|i128|u8|u16|u32|u64|u128|\\b[A-Z]\\w*\\b)\\b";
    const funcs_pattern = "([a-zA-Z_0-9]+)\\(";
    const string_pattern = "(\"[^\"]*\"|\\\\[^\n]*|'.')";
    const number_pattern = "\\b([0-9]+(\\.[0-9]+)?)";
    const buildin_pattern = "(@[a-zA-Z]+)\\(";
    const comment_pattern = "//?/[^\n]*";
    const keywords_pattern = "\\b(else|errdefer|continue|break|test|inline|pub|fn|const|var|defer|try|return|catch|extern|struct|enum|packed|if|switch|while|for|\\sand\\s|\\sor\\s)\\b";
    const operators_pattern = "(\\+|\\-|\\*|\\*\\*|\\s/\\s|&|%|<|>|=|<=|>=|==|!=|!|\\?)";
    const keywords2_patterns = "\\b(undefined|null|[A-Z_]+)\\b";

    const Context = struct { Tag, []const u8 };

    pub const zig_ctx: []const Context = &.{
        .{ .keywords1, keywords_pattern },
        .{ .keywords2, keywords2_patterns },
        .{ .funcs, funcs_pattern },
        .{ .buildin, buildin_pattern },
        .{ .types, types_pattern },
        .{ .number, number_pattern },
        .{ .comment, comment_pattern },
        .{ .string, string_pattern },
        .{ .operators, operators_pattern },
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

    const RegexShitType = []align(REGEX_T_ALIGNOF) u8;

    slice: [Tag.LEN]RegexShitType,

    pub fn init(alloc: std.mem.Allocator, contexts: []const Context) !HighLight {
        if (contexts.len != Tag.LEN) return error.Invalid;

        var slice: [Tag.LEN]RegexShitType = undefined;

        for (contexts) |ctx| {
            const tag = @intFromEnum(ctx[0]);
            const pattern = ctx[1].ptr;
            const mem = try alloc.alignedAlloc(u8, REGEX_T_ALIGNOF, REGEX_T_SIZEOF);
            slice[tag] = mem;
            const regex: *c.regex_t = @ptrCast(mem);
            if (c.regcomp(regex, pattern, c.REG_EXTENDED) != 0) {
                return error.CompilationFailed;
            }
        }

        return .{ .slice = slice };
    }

    fn regexxx(r: *HighLight, tag: Tag) *c.regex_t {
        return @ptrCast(r.slice[@intFromEnum(tag)]);
    }

    pub fn deinit(r: *HighLight, alloc: std.mem.Allocator) void {
        for (r.slice) |mem| {
            c.regfree(@ptrCast(mem));
            alloc.free(mem);
        }
    }

    fn addColor(buff: *std.ArrayList(u8), text: []const u8, color: []const u8) !void {
        try buff.writer().print("{s}{s}{s}", .{ color, text, END });
    }

    pub fn illuminate(r: *HighLight, buffer: *std.ArrayList(u8), code: []const u8) !void {
        var matches: [2]c.regmatch_t = undefined;
        var start: usize = 0;
        while (start < code.len) {
            // KEYWORDS 1
            if (0 == c.regexec(r.regexxx(.keywords1), code[start..].ptr, 1, &matches, 0) and matches[0].rm_so == 0) {
                const info = matches[0];
                const sof: usize = @intCast(info.rm_so);
                const eof: usize = @intCast(info.rm_eo);
                const txt = code[start..][sof..eof];
                try addColor(buffer, txt, PURPLE);
                start += eof;
                continue;
            }

            // KEYWORDS 2
            if (0 == c.regexec(r.regexxx(.keywords2), code[start..].ptr, 1, &matches, 0) and matches[0].rm_so == 0) {
                const info = matches[0];
                const sof: usize = @intCast(info.rm_so);
                const eof: usize = @intCast(info.rm_eo);
                const txt = code[start..][sof..eof];
                try addColor(buffer, txt, ORANGE);
                start += eof;
                continue;
            }

            // BUILTIN
            if (0 == c.regexec(r.regexxx(.buildin), code[start..].ptr, 2, &matches, 0) and matches[0].rm_so == 0) {
                const info = matches[1];
                const sof: usize = @intCast(info.rm_so);
                const eof: usize = @intCast(info.rm_eo);
                const txt = code[start..][sof..eof];
                try addColor(buffer, txt, ORANGE);
                start += eof;
                continue;
            }

            // FUNC 1
            if (0 == c.regexec(r.regexxx(.funcs), code[start..].ptr, 2, &matches, 0) and matches[0].rm_so == 0) {
                const info = matches[1];
                const sof: usize = @intCast(info.rm_so);
                const eof: usize = @intCast(info.rm_eo);
                const txt = code[start..][sof..eof];
                try addColor(buffer, txt, BLUE);
                start += eof;
                continue;
            }

            // NUMBERS
            if (0 == c.regexec(r.regexxx(.number), code[start..].ptr, 1, &matches, 0) and matches[0].rm_so == 0) {
                const info = matches[0];
                const sof: usize = @intCast(info.rm_so);
                const eof: usize = @intCast(info.rm_eo);
                const txt = code[start..][sof..eof];
                try addColor(buffer, txt, RED);
                start += eof;
                continue;
            }

            // OPERATORS
            if (0 == c.regexec(r.regexxx(.operators), code[start..].ptr, 1, &matches, 0) and matches[0].rm_so == 0) {
                const info = matches[0];
                const sof: usize = @intCast(info.rm_so);
                const eof: usize = @intCast(info.rm_eo);
                const txt = code[start..][sof..eof];
                try addColor(buffer, txt, LIGHT_BLUE);
                start += eof;
                continue;
            }

            // TYPES
            if (0 == c.regexec(r.regexxx(.types), code[start..].ptr, 1, &matches, 0) and matches[0].rm_so == 0) {
                const info = matches[0];
                const sof: usize = @intCast(info.rm_so);
                const eof: usize = @intCast(info.rm_eo);
                const txt = code[start..][sof..eof];
                try addColor(buffer, txt, AMARELO);
                start += eof;
                continue;
            }

            // COMMENTS
            if (0 == c.regexec(r.regexxx(.comment), code[start..].ptr, 1, &matches, 0) and matches[0].rm_so == 0) {
                const info = matches[0];
                const sof: usize = @intCast(info.rm_so);
                const eof: usize = @intCast(info.rm_eo);
                const txt = code[start..][sof..eof];
                try addColor(buffer, txt, GREY);
                start += eof;
                continue;
            }

            // STRINGS
            if (0 == c.regexec(r.regexxx(.string), code[start..].ptr, 1, &matches, 0) and matches[0].rm_so == 0) {
                const info = matches[0];
                const sof: usize = @intCast(info.rm_so);
                const eof: usize = @intCast(info.rm_eo);
                const txt = code[start..][sof..eof];
                try addColor(buffer, txt, GREEN);
                start += eof;
                continue;
            }

            try buffer.append(code[start]);
            start += 1;
        }
    }
};

test {
    const alloc = std.testing.allocator;

    var highlight = try HighLight.init(alloc, HighLight.zig_ctx);
    defer highlight.deinit(alloc);

    var file = try std.fs.cwd().openFile("Editor.zig", .{ .mode = .read_only });
    defer file.close();

    var buf: [1000]u8 = undefined;
    while (true) {
        const line = try file.reader().readUntilDelimiterOrEof(&buf, '\n') orelse break;
        try highlight.illuminate(alloc, line);
    }
}
