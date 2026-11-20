//! `cesium1` reads a unit's files one after another on standard input and
//! counts lines from the start of that input. `join` makes the input, and
//! `locate` maps a line and column of it back to a file and an LSP
//! position (0-based, the column in UTF-16 code units).

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Joined = struct {
    input: []u8,
    /// The input line (0-based) at which each file begins
    starts: []usize,

    pub fn deinit(j: Joined, a: Allocator) void {
        a.free(j.input);
        a.free(j.starts);
    }
};

/// The files' texts one after another. A text that does not end in a line
/// break gets one, so that every file begins on a line of its own.
pub fn join(a: Allocator, texts: []const []const u8) Allocator.Error!Joined {
    var input: std.ArrayList(u8) = .empty;
    errdefer input.deinit(a);
    const starts = try a.alloc(usize, texts.len);
    errdefer a.free(starts);
    var line: usize = 0;
    for (texts, starts) |text, *start| {
        start.* = line;
        try input.appendSlice(a, text);
        line += std.mem.countScalar(u8, text, '\n');
        if (text.len > 0 and text[text.len - 1] != '\n') {
            try input.append(a, '\n');
            line += 1;
        }
    }
    return .{ .input = try input.toOwnedSlice(a), .starts = starts };
}

pub const Place = struct {
    /// The index of the file in `texts`
    file: usize,
    line: usize,
    character: usize,
    /// the end of the word or character there, for the range of a
    /// diagnostic
    end: usize,
};

/// The file and position of the 1-based `line` and byte column `col` of the
/// joined input. A line past the end of the input (an error at the end of
/// the last file) is placed at the end of the last file that has text.
pub fn locate(texts: []const []const u8, starts: []const usize, line: usize, col: usize) Place {
    std.debug.assert(texts.len == starts.len and texts.len > 0);
    const line0 = line -| 1;
    var file: usize = 0;
    for (texts, starts, 0..) |text, start, i| {
        if (text.len > 0 and start <= line0) file = i;
    }
    return position(file, texts[file], line0 - @min(line0, starts[file]), col -| 1);
}

/// The position of the 0-based `line0` and byte column `col0` in `text`,
/// clamped to the text
pub fn position(file: usize, text: []const u8, line0: usize, col0: usize) Place {
    const last = std.mem.countScalar(u8, text, '\n');
    const l = @min(line0, last);
    var begin: usize = 0;
    for (0..l) |_| begin = std.mem.findScalarPos(u8, text, begin, '\n').? + 1;
    const end = std.mem.findScalarPos(u8, text, begin, '\n') orelse text.len;
    const content = std.mem.trimEnd(u8, text[begin..end], "\r");
    const from = @min(col0, content.len);
    const start = utf16Len(content[0..from]);
    return .{ .file = file, .line = l, .character = start, .end = start + utf16Len(content[from..wordEnd(content, from)]) };
}

/// The end of the name or number at `i`, or of the one character there
fn wordEnd(s: []const u8, i: usize) usize {
    if (i >= s.len or std.ascii.isWhitespace(s[i])) return i;
    if (!isWordByte(s[i])) return @min(s.len, i + (std.unicode.utf8ByteSequenceLength(s[i]) catch 1));
    var j = i;
    while (j < s.len and isWordByte(s[j])) j += 1;
    return j;
}

fn isWordByte(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

/// The length of `s` in UTF-16 code units; invalid UTF-8 counts a unit a
/// byte
pub fn utf16Len(s: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len) {
        const len = std.unicode.utf8ByteSequenceLength(s[i]) catch 1;
        if (i + len > s.len) return n + (s.len - i);
        const cp = std.unicode.utf8Decode(s[i .. i + len]) catch {
            n += 1;
            i += 1;
            continue;
        };
        n += if (cp >= 0x10000) 2 else 1;
        i += len;
    }
    return n;
}

const testing = std.testing;

test join {
    const a = testing.allocator;
    const j = try join(a, &.{ "a\nb\n", "", "c", "d\r\ne\r\n" });
    defer j.deinit(a);
    try testing.expectEqualStrings("a\nb\nc\nd\r\ne\r\n", j.input);
    try testing.expectEqualSlices(usize, &.{ 0, 2, 2, 3 }, j.starts);
}

test locate {
    const a = testing.allocator;
    const texts = [_][]const u8{ "i32 = main() {\n  return 0;\n}\n", "", "i32 = f() {\n  return x;\n}\n" };
    const j = try join(a, &texts);
    defer j.deinit(a);
    // "5:10: error: unknown name 'x'"
    try testing.expectEqual(Place{ .file = 2, .line = 1, .character = 9, .end = 10 }, locate(&texts, j.starts, 5, 10));
    try testing.expectEqual(Place{ .file = 0, .line = 0, .character = 0, .end = 3 }, locate(&texts, j.starts, 1, 1));
    // the end of the input: past the last line of the last file
    try testing.expectEqual(Place{ .file = 2, .line = 3, .character = 0, .end = 0 }, locate(&texts, j.starts, 7, 1));
    try testing.expectEqual(Place{ .file = 2, .line = 3, .character = 0, .end = 0 }, locate(&texts, j.starts, 9, 4));
}

test "locate: a file without a final line break" {
    const a = testing.allocator;
    const texts = [_][]const u8{ "x;", "y;\n" };
    const j = try join(a, &texts);
    defer j.deinit(a);
    try testing.expectEqual(Place{ .file = 0, .line = 0, .character = 2, .end = 2 }, locate(&texts, j.starts, 1, 3));
    try testing.expectEqual(Place{ .file = 1, .line = 0, .character = 1, .end = 2 }, locate(&texts, j.starts, 2, 2));
}

test "position: columns in UTF-16 code units, clamped" {
    // "é" is 2 bytes and 1 unit, "😀" 4 bytes and 2 units
    const text = "a\n\u{e9}\u{1F600}x = 1;\r\n";
    try testing.expectEqual(Place{ .file = 0, .line = 1, .character = 3, .end = 4 }, position(0, text, 1, 6));
    try testing.expectEqual(Place{ .file = 0, .line = 1, .character = 9, .end = 9 }, position(0, text, 1, 99));
    try testing.expectEqual(Place{ .file = 0, .line = 2, .character = 0, .end = 0 }, position(0, text, 5, 3));
    // a name, and a character that is not part of one
    try testing.expectEqual(Place{ .file = 0, .line = 0, .character = 0, .end = 6 }, position(0, "abc_12 = 3;", 0, 0));
    try testing.expectEqual(Place{ .file = 0, .line = 0, .character = 1, .end = 3 }, position(0, "x\u{1F600}", 0, 1));
}

test utf16Len {
    try testing.expectEqual(0, utf16Len(""));
    try testing.expectEqual(3, utf16Len("abc"));
    try testing.expectEqual(3, utf16Len("\u{e9}\u{1F600}"));
    try testing.expectEqual(2, utf16Len("\xff\xfe"));
}
