//! The editor-independent test of zcsls: the built server, driven as a
//! plain LSP client would drive it (lsp_client.zig), with a stand-in for
//! `cesium1` (fake_cesium1.zig), as a client that pulls diagnostics and as
//! one that does not. `zig build test` runs it.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const json = std.json;
const testing = std.testing;
const sysinfo = @import("builtin");
const uri = @import("uri");
const paths = @import("lsp_test_paths");
const lsp_client = @import("lsp_client.zig");

const Client = lsp_client.Client;
const get = lsp_client.get;

/// `{}`: an empty tuple would be `[]`
const empty = struct {}{};

const style: uri.Style = if (sysinfo.os.tag == .windows) .windows else .posix;
const exe_suffix = if (sysinfo.os.tag == .windows) ".exe" else "";

/// The unit `u/` of a.csm and b.csm, with an error in b.csm: `bad` on line
/// 2 at byte 10, which is line 5 of the unit as cesium1 reads it
const a_text = "i32 = main() {\n  return f();\n}\n";
const b_bad = "i32 = f() {\n  return bad;\n}\n";
const b_good = "i32 = f() {\n  return 0;\n}\n";

const Workspace = struct {
    tmp: testing.TmpDir,
    root: []const u8,
    root_uri: []const u8,
    a_uri: []const u8,
    b_uri: []const u8,
    /// the stand-in for cesium1, by its absolute path
    compiler: []const u8,
    env: std.process.Environ.Map,

    fn init(w: *Workspace, a: Allocator) !void {
        const io = testing.io;
        w.tmp = testing.tmpDir(.{});
        try w.tmp.dir.createDirPath(io, "u");
        try w.tmp.dir.createDirPath(io, "bin");
        try w.tmp.dir.writeFile(io, .{ .sub_path = "u/a.csm", .data = a_text });
        try w.tmp.dir.writeFile(io, .{ .sub_path = "u/b.csm", .data = b_bad });
        // the compiler under the root, for a relative cesium.compiler.path
        try Io.Dir.cwd().copyFile(paths.compiler, w.tmp.dir, "bin/fake-cesium1" ++ exe_suffix, io, .{});
        w.root = try w.tmp.dir.realPathFileAlloc(io, ".", a);
        w.compiler = try Io.Dir.cwd().realPathFileAlloc(io, paths.compiler, a);
        w.root_uri = try uri.fromPath(a, w.root, style);
        w.a_uri = try uri.fromPath(a, try Io.Dir.path.join(a, &.{ w.root, "u", "a.csm" }), style);
        w.b_uri = try uri.fromPath(a, try Io.Dir.path.join(a, &.{ w.root, "u", "b.csm" }), style);
        // no compiler on the PATH: only the one the settings name
        w.env = try testing.environ.createMap(a);
        try w.env.put("PATH", "");
    }

    fn deinit(w: *Workspace) void {
        w.tmp.cleanup();
    }
};

fn textDocument(u: []const u8, text: []const u8) struct { textDocument: struct { uri: []const u8, languageId: []const u8 = "cesium", version: i64 = 1, text: []const u8 } } {
    return .{ .textDocument = .{ .uri = u, .text = text } };
}

/// The diagnostics of a pull's full report
fn items(report: json.Value) ![]const json.Value {
    const r = get(report, "result");
    try testing.expectEqualStrings("full", get(r, "kind").string);
    return get(r, "items").array.items;
}

/// The diagnostics a publishDiagnostics carries
fn published(m: json.Value) []const json.Value {
    return get(get(m, "params"), "diagnostics").array.items;
}

/// Checks that `d` is cesium1's error at `bad` in b.csm
fn expectBad(d: json.Value) !void {
    try testing.expectEqualStrings("unknown name 'bad'", get(d, "message").string);
    try testing.expectEqualStrings("cesium1", get(d, "source").string);
    const start = get(get(d, "range"), "start");
    try testing.expectEqual(1, get(start, "line").integer);
    try testing.expectEqual(9, get(start, "character").integer);
    try testing.expectEqual(12, get(get(get(d, "range"), "end"), "character").integer);
}

test "a client that pulls diagnostics" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var w: Workspace = undefined;
    try w.init(a);
    defer w.deinit();
    var c: Client = undefined;
    try c.start(a, testing.io, paths.zcsls, &w.env);
    defer c.deinit();

    // the settings in their `cesium` member, the path relative to the root
    const init = try c.response(try c.request("initialize", .{
        .rootUri = w.root_uri,
        .capabilities = .{
            .textDocument = .{ .diagnostic = .{ .dynamicRegistration = false } },
            .workspace = .{ .diagnostics = .{ .refreshSupport = true }, .didChangeWatchedFiles = .{ .dynamicRegistration = true } },
        },
        .initializationOptions = .{ .cesium = .{ .compiler = .{ .path = "bin/fake-cesium1" ++ exe_suffix } } },
    }));
    const provider = get(get(get(init, "result"), "capabilities"), "diagnosticProvider");
    try testing.expect(get(provider, "interFileDependencies").bool);
    try c.notify("initialized", empty);
    const reg = try c.expect(.{ .method = "client/registerCapability" });
    const watcher = get(get(get(get(reg, "params"), "registrations").array.items[0], "registerOptions"), "watchers").array.items[0];
    try testing.expectEqualStrings("**/*.{csm,csi}", get(watcher, "globPattern").string);

    // a.csm is pulled; b.csm, of its unit and not open, is published
    try c.notify("textDocument/didOpen", textDocument(w.a_uri, a_text));
    const from = c.count();
    const first = try c.response(try c.request("textDocument/diagnostic", .{ .textDocument = .{ .uri = w.a_uri } }));
    try testing.expectEqual(0, (try items(first)).len);
    try testing.expect(!c.sent(from, "textDocument/publishDiagnostics", "a.csm"));
    const pushed = try c.expect(.{ .method = "textDocument/publishDiagnostics", .uri = "b.csm" });
    try expectBad(published(pushed)[0]);
    const again = try c.response(try c.request("textDocument/diagnostic", .{ .textDocument = .{ .uri = w.a_uri }, .previousResultId = get(get(first, "result"), "resultId").string }));
    try testing.expectEqualStrings("unchanged", get(get(again, "result"), "kind").string);

    // opened, b.csm is pulled instead
    try c.notify("textDocument/didOpen", textDocument(w.b_uri, b_bad));
    try testing.expectEqual(0, published(try c.expect(.{ .method = "textDocument/publishDiagnostics", .uri = "b.csm" })).len);
    const b = try c.response(try c.request("textDocument/diagnostic", .{ .textDocument = .{ .uri = w.b_uri } }));
    try testing.expectEqual(1, (try items(b)).len);
    try expectBad((try items(b))[0]);

    // the editor's text, unsaved
    try c.notify("textDocument/didChange", .{ .textDocument = .{ .uri = w.b_uri, .version = 2 }, .contentChanges = .{.{ .text = b_good }} });
    try testing.expectEqual(0, (try items(try c.response(try c.request("textDocument/diagnostic", .{ .textDocument = .{ .uri = w.b_uri } })))).len);

    // a compiler that is not there: said so, and pulled again
    try c.notify("workspace/didChangeConfiguration", .{ .settings = .{ .cesium = .{ .compiler = .{ .path = "nowhere" } } } });
    _ = try c.expect(.{ .method = "window/showMessage" });
    _ = try c.expect(.{ .method = "workspace/diagnostic/refresh" });
    try c.notify("textDocument/didChange", .{ .textDocument = .{ .uri = w.b_uri, .version = 3 }, .contentChanges = .{.{ .text = b_bad }} });
    try testing.expectEqual(0, (try items(try c.response(try c.request("textDocument/diagnostic", .{ .textDocument = .{ .uri = w.b_uri } })))).len);

    try testing.expect(get(try c.response(try c.request("shutdown", null)), "result") == .null);
    try c.notify("exit", null);
    try testing.expectEqual(0, try c.exitCode());
}

test "a client that does not pull diagnostics" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = testing.io;
    var w: Workspace = undefined;
    try w.init(a);
    defer w.deinit();
    var c: Client = undefined;
    try c.start(a, io, paths.zcsls, &w.env);
    defer c.deinit();

    // no compiler yet
    const init = try c.response(try c.request("initialize", .{
        .rootUri = w.root_uri,
        .capabilities = .{ .workspace = .{ .didChangeWatchedFiles = .{ .dynamicRegistration = true } } },
        .initializationOptions = empty,
    }));
    try testing.expect(get(get(get(init, "result"), "capabilities"), "diagnosticProvider") == .null);
    try c.notify("initialized", empty);
    _ = try c.expect(.{ .method = "window/showMessage" });
    _ = try c.expect(.{ .method = "client/registerCapability" });

    // the compiler from the settings, as one object, checks the open unit
    try c.notify("textDocument/didOpen", textDocument(w.a_uri, a_text));
    try c.notify("workspace/didChangeConfiguration", .{ .settings = .{ .compiler = .{ .path = w.compiler }, .diagnosticsChangeDelay = 100 } });
    try expectBad(published(try c.expect(.{ .method = "textDocument/publishDiagnostics", .uri = "b.csm" }))[0]);

    try c.notify("textDocument/didOpen", textDocument(w.b_uri, b_bad));
    try expectBad(published(try c.expect(.{ .method = "textDocument/publishDiagnostics", .uri = "b.csm" }))[0]);

    // a change is checked once the text has rested for the delay
    const changed = Io.Clock.awake.now(io).nanoseconds;
    try c.notify("textDocument/didChange", .{ .textDocument = .{ .uri = w.b_uri, .version = 2 }, .contentChanges = .{.{ .text = b_good }} });
    const fixed = try c.expect(.{ .method = "textDocument/publishDiagnostics", .uri = "b.csm" });
    try testing.expect(Io.Clock.awake.now(io).nanoseconds - changed >= 100 * std.time.ns_per_ms);
    try testing.expectEqual(0, published(fixed).len);
    try testing.expectEqual(2, get(get(fixed, "params"), "version").integer);

    // a file of the unit made and deleted outside the editor
    try w.tmp.dir.writeFile(io, .{ .sub_path = "u/c.csm", .data = "i32 = g() {\n  return bad;\n}\n" });
    const c_uri = try uri.fromPath(a, try Io.Dir.path.join(a, &.{ w.root, "u", "c.csm" }), style);
    try c.notify("workspace/didChangeWatchedFiles", .{ .changes = .{.{ .uri = c_uri, .type = 1 }} });
    const made = published(try c.expect(.{ .method = "textDocument/publishDiagnostics", .uri = "c.csm" }));
    try testing.expectEqual(1, get(get(get(made[0], "range"), "start"), "line").integer);
    try w.tmp.dir.deleteFile(io, "u/c.csm");
    try c.notify("workspace/didChangeWatchedFiles", .{ .changes = .{.{ .uri = c_uri, .type = 3 }} });
    try testing.expectEqual(0, published(try c.expect(.{ .method = "textDocument/publishDiagnostics", .uri = "c.csm" })).len);

    try testing.expect(get(try c.response(try c.request("shutdown", null)), "result") == .null);
    try c.notify("exit", null);
    try testing.expectEqual(0, try c.exitCode());
}
