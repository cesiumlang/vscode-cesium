//! The bootstrap compiler that checks a unit (cesium-src/bootstrap/README.md):
//! `cesium1` when there is one, since it follows S1 as it grows, else
//! `cesium0`, which knows only S0. Neither is bundled: the setting
//! `cesium.compiler.path` names one (or a directory with them), else they
//! are looked for on the PATH.

const std = @import("std");
const sysinfo = @import("builtin");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const is_windows = sysinfo.os.tag == .windows;
const exe_suffix = if (is_windows) ".exe" else "";

pub const Kind = enum {
    /// reads the unit on standard input, stops at the first error, and
    /// reports it on standard output with input-relative lines
    cesium1,
    /// takes the files, reports every error on standard error with its file
    cesium0,
};

pub const Compiler = struct {
    path: []const u8,
    kind: Kind,
};

/// The compiler to use: the one `configured` names (a file, or a directory
/// holding `cesium1` or `cesium0`), else `cesium1` or `cesium0` on `path_env`
/// (the PATH). Null when there is none.
pub fn find(a: Allocator, io: Io, configured: ?[]const u8, path_env: ?[]const u8) Allocator.Error!?Compiler {
    if (configured) |c| if (c.len > 0) {
        if (isDir(io, c)) return inDir(a, io, c);
        if (!isFile(io, c)) return null;
        return .{ .path = try a.dupe(u8, c), .kind = kindOf(c) };
    };
    var dirs = std.mem.tokenizeScalar(u8, path_env orelse "", if (is_windows) ';' else ':');
    var cesium0: ?Compiler = null;
    while (dirs.next()) |dir| {
        const found = try inDir(a, io, dir) orelse continue;
        if (found.kind == .cesium1) return found;
        cesium0 = cesium0 orelse found;
    }
    return cesium0;
}

/// `cesium1`, else `cesium0`, in `dir`
fn inDir(a: Allocator, io: Io, dir: []const u8) Allocator.Error!?Compiler {
    inline for (.{ Kind.cesium1, Kind.cesium0 }) |kind| {
        const path = try Io.Dir.path.join(a, &.{ dir, @tagName(kind) ++ exe_suffix });
        if (isFile(io, path)) return .{ .path = path, .kind = kind };
        a.free(path);
    }
    return null;
}

/// What a compiler is, by its name: `cesium0` (`cesium0.exe`, `cesium0-dev`)
/// is stage 0, anything else is taken for `cesium1`
pub fn kindOf(path: []const u8) Kind {
    return if (std.mem.startsWith(u8, Io.Dir.path.basename(path), "cesium0")) .cesium0 else .cesium1;
}

fn isFile(io: Io, path: []const u8) bool {
    const st = Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return st.kind == .file or st.kind == .sym_link;
}

fn isDir(io: Io, path: []const u8) bool {
    var dir = Io.Dir.cwd().openDir(io, path, .{}) catch return false;
    dir.close(io);
    return true;
}

pub const Output = struct {
    term: std.process.Child.Term,
    /// where the compiler reports errors: standard output for `cesium1`,
    /// standard error for `cesium0`
    messages: []u8,
};

pub const RunError = error{ CannotStart, Timeout, OutputFailed } || Allocator.Error;

/// The longest a compiler may take on a unit
const timeout_seconds = 30;

/// Checks a unit: `cesium1` reads `input` (the files joined), `cesium0`
/// reads `files` from disk. The output is owned by `a`.
pub fn run(a: Allocator, io: Io, c: Compiler, files: []const []const u8, input: []const u8) RunError!Output {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(a);
    try argv.append(a, c.path);
    if (c.kind == .cesium0) {
        // the MIR is not wanted: checking stops before QBE
        try argv.appendSlice(a, &.{ "--emit-mir", "-o", if (is_windows) "NUL" else "/dev/null" });
        try argv.appendSlice(a, files);
    }
    var child = std.process.spawn(io, .{
        .argv = argv.items,
        .stdin = if (c.kind == .cesium1) .pipe else .ignore,
        .stdout = .pipe,
        .stderr = .pipe,
        .create_no_window = true,
    }) catch return error.CannotStart;
    defer child.kill(io);
    // on a thread of its own, so that a compiler that writes before it has
    // read all of its input cannot block on a full pipe
    var writer: ?std.Thread = null;
    defer if (writer) |t| t.join();
    if (child.stdin) |stdin| {
        child.stdin = null;
        writer = std.Thread.spawn(.{ .stack_size = 64 * 1024 }, writeInput, .{ io, stdin, input }) catch {
            stdin.close(io);
            return error.CannotStart;
        };
    }
    var buffer: Io.File.MultiReader.Buffer(2) = undefined;
    var multi: Io.File.MultiReader = undefined;
    multi.init(a, io, buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
    defer multi.deinit();
    const timeout: Io.Timeout = .{ .duration = .{ .raw = .fromSeconds(timeout_seconds), .clock = .awake } };
    const deadline = timeout.toDeadline(io);
    while (multi.fill(256, deadline)) |_| {} else |e| switch (e) {
        error.EndOfStream => {},
        error.Timeout => return error.Timeout,
        else => return error.OutputFailed,
    }
    multi.checkAnyError() catch return error.OutputFailed;
    const term = child.wait(io) catch return error.OutputFailed;
    return .{ .term = term, .messages = try multi.toOwnedSlice(if (c.kind == .cesium1) 0 else 1) };
}

fn writeInput(io: Io, file: Io.File, input: []const u8) void {
    defer file.close(io);
    // a compiler that ends without reading all of it: its output tells
    file.writeStreamingAll(io, input) catch {};
}

const testing = std.testing;

test kindOf {
    try testing.expectEqual(Kind.cesium0, kindOf("/opt/cesium/bin/cesium0"));
    try testing.expectEqual(Kind.cesium0, kindOf("cesium0.exe"));
    try testing.expectEqual(Kind.cesium1, kindOf("/opt/cesium/bin/cesium1"));
    try testing.expectEqual(Kind.cesium1, kindOf("my-compiler"));
}

test find {
    const io = testing.io;
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "zero");
    try tmp.dir.createDirPath(io, "both");
    try tmp.dir.writeFile(io, .{ .sub_path = "zero/cesium0" ++ exe_suffix, .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "both/cesium0" ++ exe_suffix, .data = "" });
    try tmp.dir.writeFile(io, .{ .sub_path = "both/cesium1" ++ exe_suffix, .data = "" });
    const root = try tmp.dir.realPathFileAlloc(io, ".", a);
    const zero = try Io.Dir.path.join(a, &.{ root, "zero" });
    const both = try Io.Dir.path.join(a, &.{ root, "both" });
    const sep = if (is_windows) ";" else ":";

    // cesium1 anywhere on the PATH comes before cesium0
    const on_path = (try find(a, io, null, try std.mem.concat(a, u8, &.{ zero, sep, both }))).?;
    try testing.expectEqual(Kind.cesium1, on_path.kind);
    try testing.expectEqualStrings(both, Io.Dir.path.dirname(on_path.path).?);
    try testing.expectEqual(Kind.cesium0, (try find(a, io, null, zero)).?.kind);
    try testing.expectEqual(null, try find(a, io, null, null));

    // the setting, a directory or a file, comes before the PATH
    try testing.expectEqual(Kind.cesium0, (try find(a, io, zero, both)).?.kind);
    const file = try Io.Dir.path.join(a, &.{ both, "cesium0" ++ exe_suffix });
    try testing.expectEqualStrings(file, (try find(a, io, file, both)).?.path);
    try testing.expectEqual(null, try find(a, io, try Io.Dir.path.join(a, &.{ root, "none" }), both));
}
