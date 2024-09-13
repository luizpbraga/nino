const std = @import("std");
const Editor = @import("Editor.zig");
const Mode = Editor.Mode;

pub const Key = enum(usize) {
    ENTER = '\r',
    ESC = '\x1b',
    BACKSPACE = 127,
    ARROW_LEFT = 1000,
    ARROW_RIGHT,
    ARROW_UP,
    ARROW_DOWN,
    DEL,
    HOME,
    END,
    PAGE_UP,
    PAGE_DOWN,
    MOUSE,
    ZOONIN,
    ZOONOUT,
    _,
};

pub const KeyMap = struct {
    const Hash = std.AutoHashMap(struct { Mode, Key }, []const Key);
    hash: Hash,

    pub fn init(alloc: std.mem.Allocator) KeyMap {
        const hash: Hash = .init(alloc);
        return .{ .hash = hash };
    }

    pub fn deinit(m: *KeyMap) void {
        m.hash.deinit();
    }

    pub fn get(m: *KeyMap, mode: Mode, key: Key) ?[]const Key {
        return m.hash.get(.{ mode, key });
    }

    pub fn map(m: *KeyMap, mode: Mode, key: Key, keys: []const Key) !void {
        if (keys.len == 0) return;
        try m.hash.put(.{ mode, key }, keys);
    }
};

pub fn controlKey(c: usize) Key {
    if (c == '-') return .ZOONIN;
    if (c == '+') return .ZOONOUT;
    return @enumFromInt(c & 0x1f);
}

pub fn asKey(c: usize) Key {
    return @enumFromInt(c);
}
