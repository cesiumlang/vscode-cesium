//! What compilation unit a file belongs to, and the order of its files.
//!
//! Not decided yet (cesiumlang/vscode-cesium#7, deferred by emanspeaks). The
//! interim rule: every `.csm` file in the directory of the file, in byte
//! order of their names. Only `files` knows it, so that it can change.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const source_ext = ".csm";

/// The paths of the files of the unit `path` belongs to, in the order the
/// compiler is to read them, allocated with `a`. `path` itself is one of them
/// when it is a source file, on disk or not.
pub fn files(a: Allocator, io: Io, path: []const u8) (Allocator.Error || Io.Cancelable)![]const []const u8 {
    const dir_path = Io.Dir.path.dirname(path) orelse return a.dupe([]const u8, &.{path});
    var dir = Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch |e| switch (e) {
        error.Canceled => return error.Canceled,
        else => return a.dupe([]const u8, &.{path}),
    };
    defer dir.close(io);
    var names: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (it.next(io) catch |e| switch (e) {
        error.Canceled => return error.Canceled,
        else => null,
    }) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (!isSource(entry.name)) continue;
        try names.append(a, try a.dupe(u8, entry.name));
    }
    const own = Io.Dir.path.basename(path);
    if (isSource(own) and !contains(names.items, own)) try names.append(a, own);
    std.mem.sort([]const u8, names.items, {}, lessThan);
    const out = try a.alloc([]const u8, names.items.len);
    for (names.items, out) |name, *p| p.* = try Io.Dir.path.join(a, &.{ dir_path, name });
    return out;
}

/// Whether `name` is a source file of a unit
pub fn isSource(name: []const u8) bool {
    return name.len > source_ext.len and std.mem.endsWith(u8, name, source_ext);
}

fn contains(names: []const []const u8, name: []const u8) bool {
    for (names) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

fn lessThan(_: void, x: []const u8, y: []const u8) bool {
    return std.mem.order(u8, x, y) == .lt;
}

const testing = std.testing;

test files {
    const io = testing.io;
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    for ([_][]const u8{ "c.csm", "a.csm", "B.csm", "m.csi", "notes.txt", ".csm" }) |name|
        try tmp.dir.writeFile(io, .{ .sub_path = name, .data = "" });
    try tmp.dir.createDirPath(io, "sub.csm");
    const dir = try tmp.dir.realPathFileAlloc(io, ".", a);
    const unit = try files(a, io, try Io.Dir.path.join(a, &.{ dir, "new.csm" }));
    try testing.expectEqual(4, unit.len);
    for (unit, [_][]const u8{ "B.csm", "a.csm", "c.csm", "new.csm" }) |p, name| {
        try testing.expectEqualStrings(name, Io.Dir.path.basename(p));
        try testing.expectEqualStrings(dir, Io.Dir.path.dirname(p).?);
    }
    const interface = try files(a, io, try Io.Dir.path.join(a, &.{ dir, "m.csi" }));
    try testing.expectEqual(3, interface.len);
}

test "files: a directory that is not there" {
    const a = testing.allocator;
    const unit = try files(a, testing.io, "/no/such/dir/a.csm");
    defer a.free(unit);
    try testing.expectEqual(1, unit.len);
    try testing.expectEqualStrings("/no/such/dir/a.csm", unit[0]);
}
