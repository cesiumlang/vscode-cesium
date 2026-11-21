//! The settings of zcsls, under the editor's names without `cesium.`:
//! `compiler.path` and `diagnosticsChangeDelay`. They come in
//! `initializationOptions` and in `workspace/didChangeConfiguration`, as one
//! object or in its `cesium` member, as zfls takes them. A setting left out
//! keeps its value; `null` restores its default.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const json = std.json;

/// zfls's default: milliseconds without a change before a changed document
/// is checked, for a client that does not pull diagnostics
pub const default_change_delay = 300;

pub const Settings = struct {
    /// a compiler or a directory with one, as given (owned by the server's
    /// allocator); null: the PATH
    compiler_path: ?[]u8 = null,
    /// 0: with each change; negative: only on open and save
    change_delay: i64 = default_change_delay,

    pub fn deinit(s: *Settings, gpa: Allocator) void {
        if (s.compiler_path) |p| gpa.free(p);
        s.compiler_path = null;
    }
};

/// What a change of the settings changed
pub const Changed = struct { compiler: bool = false, delay: bool = false };

/// The settings object of `v`: its `cesium` member when that is an object,
/// else `v`; null when `v` is no object
pub fn section(v: json.Value) ?json.ObjectMap {
    if (v != .object) return null;
    if (v.object.get("cesium")) |c| if (c == .object) return c.object;
    return v.object;
}

/// Applies the settings in `v` to `s`; values of the wrong type are left out
pub fn apply(gpa: Allocator, s: *Settings, v: json.Value) Allocator.Error!Changed {
    const o = section(v) orelse return .{};
    var changed: Changed = .{};
    if (o.get("compiler")) |c| switch (c) {
        .null => changed.compiler = try setPath(gpa, s, null),
        .object => |co| if (co.get("path")) |p| switch (p) {
            .null => changed.compiler = try setPath(gpa, s, null),
            .string => |str| changed.compiler = try setPath(gpa, s, str),
            else => {},
        },
        else => {},
    };
    if (o.get("diagnosticsChangeDelay")) |d| {
        const delay: ?i64 = switch (d) {
            .null => default_change_delay,
            .integer => |i| i,
            .float => |f| if (std.math.isFinite(f)) @intFromFloat(std.math.clamp(f, -1e9, 1e9)) else null,
            else => null,
        };
        if (delay) |x| if (x != s.change_delay) {
            s.change_delay = x;
            changed.delay = true;
        };
    }
    return changed;
}

/// Sets the compiler's path, an empty one being none; whether it changed
fn setPath(gpa: Allocator, s: *Settings, path: ?[]const u8) Allocator.Error!bool {
    const new: ?[]const u8 = if (path) |p| (if (std.mem.trim(u8, p, " \t").len == 0) null else p) else null;
    const old = s.compiler_path;
    if (old == null and new == null) return false;
    if (old != null and new != null and std.mem.eql(u8, old.?, new.?)) return false;
    s.compiler_path = if (new) |n| try gpa.dupe(u8, n) else null;
    if (old) |o| gpa.free(o);
    return true;
}

/// A path setting as a path, as the extension took them: a leading `~` is
/// `home`, and a relative path is taken relative to `root` (the workspace's)
/// when there is one
pub fn resolvePath(a: Allocator, value: []const u8, root: ?[]const u8, home: ?[]const u8) Allocator.Error![]const u8 {
    const v = std.mem.trim(u8, value, " \t");
    if (home) |h| {
        if (std.mem.eql(u8, v, "~")) return a.dupe(u8, h);
        if (std.mem.startsWith(u8, v, "~/") or std.mem.startsWith(u8, v, "~\\")) return Io.Dir.path.join(a, &.{ h, v[2..] });
    }
    if (Io.Dir.path.isAbsolute(v)) return a.dupe(u8, v);
    const r = root orelse return a.dupe(u8, v);
    return Io.Dir.path.join(a, &.{ r, v });
}

const testing = std.testing;

fn parse(a: Allocator, text: []const u8) !json.Value {
    return json.parseFromSliceLeaky(json.Value, a, text, .{});
}

test apply {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const gpa = testing.allocator;
    var s: Settings = .{};
    defer s.deinit(gpa);

    // one object, or in its `cesium` member, as VS Code sends them
    try testing.expectEqual(Changed{ .compiler = true }, try apply(gpa, &s, try parse(a, "{\"compiler\":{\"path\":\"/c/cesium1\"}}")));
    try testing.expectEqualStrings("/c/cesium1", s.compiler_path.?);
    const both = try apply(gpa, &s, try parse(a, "{\"cesium\":{\"compiler\":{\"path\":\"/c/cesium1\"},\"diagnosticsChangeDelay\":50,\"server\":{\"path\":\"\"}}}"));
    try testing.expectEqual(Changed{ .delay = true }, both);
    try testing.expectEqual(50, s.change_delay);

    // left out: kept; null or empty: the default
    try testing.expectEqual(Changed{}, try apply(gpa, &s, try parse(a, "{}")));
    try testing.expectEqualStrings("/c/cesium1", s.compiler_path.?);
    try testing.expectEqual(Changed{ .compiler = true, .delay = true }, try apply(gpa, &s, try parse(a, "{\"compiler\":{\"path\":\"\"},\"diagnosticsChangeDelay\":null}")));
    try testing.expectEqual(null, s.compiler_path);
    try testing.expectEqual(default_change_delay, s.change_delay);

    // the wrong types, and no object
    try testing.expectEqual(Changed{}, try apply(gpa, &s, try parse(a, "{\"compiler\":{\"path\":3},\"diagnosticsChangeDelay\":\"x\"}")));
    try testing.expectEqual(Changed{}, try apply(gpa, &s, try parse(a, "[1]")));
    try testing.expectEqual(Changed{}, try apply(gpa, &s, .null));
}

test resolvePath {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sep = Io.Dir.path.sep_str;
    const home = if (Io.Dir.path.sep == '\\') "C:\\Users\\me" else "/home/me";
    const root = if (Io.Dir.path.sep == '\\') "C:\\work" else "/work";
    try testing.expectEqualStrings(home, try resolvePath(a, "~", root, home));
    try testing.expectEqualStrings(home ++ sep ++ "bin", try resolvePath(a, "~/bin", root, home));
    try testing.expectEqualStrings(root ++ sep ++ "bin", try resolvePath(a, " bin ", root, home));
    try testing.expectEqualStrings("bin", try resolvePath(a, "bin", null, home));
    try testing.expectEqualStrings(home, try resolvePath(a, home, root, null));
}
