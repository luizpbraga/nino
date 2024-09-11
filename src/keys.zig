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
    _,
};

pub fn controlKey(c: usize) Key {
    return @enumFromInt(c & 0x1f);
}

pub fn asKey(c: usize) Key {
    return @enumFromInt(c);
}
