//! The messages of the bootstrap compilers (cesium-src/bootstrap/README.md):
//! `line:col: error: message` from `cesium1`, with lines counted from the
//! start of its input; `file:line:col: error: message` from `cesium0`; and
//! messages without a place, such as `cesium0: error: ...` (its verifier)
//! and `error: internal: ...` (a limit of `cesium1`). A diagnostic code
//! may follow the severity word: `error[E0101]: message`
//! (cesium-src/bootstrap/diagnostics.md).

const std = @import("std");

pub const Severity = enum(u8) { @"error" = 1, warning = 2 };

pub const Message = struct {
    /// The file named before the line, if any (`cesium0`)
    file: ?[]const u8 = null,
    /// 1-based; 0 when the message has no place
    line: usize = 0,
    /// 1-based, in bytes; 0 when the message has no place
    col: usize = 0,
    severity: Severity,
    /// The diagnostic code in brackets after the severity word, if any
    code: ?[]const u8 = null,
    text: []const u8,
};

/// The message on one line of output, or null when it is none (`\r`
/// before the line end is ignored); slices of `line`
pub fn parseLine(line: []const u8) ?Message {
    const l = std.mem.trimEnd(u8, line, "\r\n");
    // the first severity word, at the start or after ": "; the text may
    // hold another
    var at: usize = 0;
    while (true) {
        if (severityAt(l, at)) |h| {
            var m: Message = .{ .severity = h.severity, .code = h.code, .text = l[h.text..] };
            if (at > 0) place(l[0 .. at - 2], &m);
            return m;
        }
        at = (std.mem.findPos(u8, l, at, ": ") orelse return null) + 2;
    }
}

const SeverityAt = struct { severity: Severity, code: ?[]const u8, text: usize };

/// The severity word at `at`, with its code (`error[E0101]: `), and where
/// the text after it starts
fn severityAt(l: []const u8, at: usize) ?SeverityAt {
    inline for (.{ Severity.@"error", Severity.warning }) |sev| {
        const word = @tagName(sev);
        if (std.mem.startsWith(u8, l[at..], word)) {
            var end = at + word.len;
            var code: ?[]const u8 = null;
            if (end < l.len and l[end] == '[') {
                const close = std.mem.findScalarPos(u8, l, end, ']') orelse return null;
                code = l[end + 1 .. close];
                if (!isCode(code.?)) return null;
                end = close + 1;
            }
            if (std.mem.startsWith(u8, l[end..], ": ")) return .{ .severity = sev, .code = code, .text = end + 2 };
        }
    }
    return null;
}

/// A code is a few letters and digits
fn isCode(s: []const u8) bool {
    if (s.len == 0 or s.len > 16) return false;
    for (s) |c| if (!std.ascii.isAlphanumeric(c)) return false;
    return true;
}

/// Fills in the file, line and column of `prefix` (`[file:]line:col`);
/// a prefix without numbers is a program's name and gives no place
fn place(prefix: []const u8, m: *Message) void {
    const c2 = std.mem.findScalarLast(u8, prefix, ':') orelse return;
    const col = std.fmt.parseInt(usize, prefix[c2 + 1 ..], 10) catch return;
    const head = prefix[0..c2];
    const c1 = std.mem.findScalarLast(u8, head, ':');
    const line_text = if (c1) |c| head[c + 1 ..] else head;
    const line = std.fmt.parseInt(usize, line_text, 10) catch return;
    m.line = line;
    m.col = col;
    if (c1) |c| m.file = head[0..c];
}

/// Iterates over the messages of a compiler's output
pub const Iterator = struct {
    lines: std.mem.SplitIterator(u8, .scalar),

    pub fn init(output: []const u8) Iterator {
        return .{ .lines = std.mem.splitScalar(u8, output, '\n') };
    }

    pub fn next(it: *Iterator) ?Message {
        while (it.lines.next()) |line| if (parseLine(line)) |m| return m;
        return null;
    }
};

const testing = std.testing;

test "cesium1: input-relative line" {
    const m = parseLine("5:10: error: unknown name 'x'\r\n").?;
    try testing.expectEqual(null, m.file);
    try testing.expectEqual(5, m.line);
    try testing.expectEqual(10, m.col);
    try testing.expectEqual(Severity.@"error", m.severity);
    try testing.expectEqualStrings("unknown name 'x'", m.text);
}

test "cesium0: a file with a drive letter" {
    const m = parseLine("C:\\src\\b.csm:2:10: error: expected ';', found end of file").?;
    try testing.expectEqualStrings("C:\\src\\b.csm", m.file.?);
    try testing.expectEqual(2, m.line);
    try testing.expectEqual(10, m.col);
    try testing.expectEqualStrings("expected ';', found end of file", m.text);
}

test "messages without a place" {
    const verifier = parseLine("cesium0: error: line 1: @g does not return a value on every path").?;
    try testing.expectEqual(0, verifier.line);
    try testing.expectEqual(null, verifier.file);
    try testing.expectEqualStrings("line 1: @g does not return a value on every path", verifier.text);
    const internal = parseLine("error: internal: too many tokens").?;
    try testing.expectEqual(0, internal.line);
    try testing.expectEqualStrings("internal: too many tokens", internal.text);
}

test "a diagnostic code after the severity word" {
    const m1 = parseLine("5:10: error[E0301]: unknown name 'x'").?;
    try testing.expectEqual(5, m1.line);
    try testing.expectEqualStrings("E0301", m1.code.?);
    try testing.expectEqualStrings("unknown name 'x'", m1.text);
    const m0 = parseLine("C:\\src\\b.csm:2:10: error[E0201]: expected ';', found end of file").?;
    try testing.expectEqualStrings("C:\\src\\b.csm", m0.file.?);
    try testing.expectEqual(2, m0.line);
    try testing.expectEqualStrings("E0201", m0.code.?);
    try testing.expectEqualStrings("expected ';', found end of file", m0.text);
    try testing.expectEqual(null, parseLine("5:10: error: unknown name 'x'").?.code);
    // brackets that are no code leave the line without a message
    try testing.expectEqual(null, parseLine("5:10: error[a b]: x"));
}

test "a message whose text holds a colon and the word error" {
    const m = parseLine("3:1: error: expected ': error: ', found x").?;
    try testing.expectEqual(3, m.line);
    try testing.expectEqualStrings("expected ': error: ', found x", m.text);
}

test Iterator {
    var it: Iterator = .init("data $x = { w 1 }\r\na.csm:1:2: error: one\r\nb.csm:3:4: warning: two\r\n");
    try testing.expectEqualStrings("one", it.next().?.text);
    const w = it.next().?;
    try testing.expectEqual(Severity.warning, w.severity);
    try testing.expectEqualStrings("b.csm", w.file.?);
    try testing.expectEqual(null, it.next());
}
