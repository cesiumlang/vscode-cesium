//! Diagnostics from the bootstrap compilers: the unit of a document is
//! checked (unit.zig), the compiler's messages are placed in its files
//! (messages.zig, line_map.zig), and each file of the unit gets its
//! diagnostics, by pull (pull.zig) or published, an empty list clearing
//! earlier ones.
//!
//! When a check runs is documents.zig's. `cesium1` reads the text of the
//! open documents, unsaved edits included; `cesium0` reads the files on
//! disk, so it sees only what is saved.

const std = @import("std");
const Allocator = std.mem.Allocator;
const lsp = @import("lsp.zig");
const uri_mod = @import("uri.zig");
const unit = @import("unit.zig");
const compiler = @import("compiler.zig");
const messages = @import("messages.zig");
const line_map = @import("line_map.zig");
const pending = @import("pending.zig");
const server_mod = @import("server.zig");

const Server = server_mod.Server;

/// A file of the unit being checked
pub const Source = struct {
    uri: []const u8,
    path: ?[]const u8,
    text: []const u8,
    diagnostics: std.ArrayList(lsp.Diagnostic) = .empty,
};

/// Checks the unit of the open document `uri` and publishes the
/// diagnostics of its files; `a` is freed after the message
pub fn check(s: *Server, a: Allocator, uri: []const u8) server_mod.Error!void {
    const sources = try run(s, a, uri) orelse return;
    pending.settle(s, sources);
    try publish(s, a, sources, false);
}

/// Checks the units of the open documents (those at `only`, when given),
/// each once, and publishes their diagnostics
pub fn checkOpen(s: *Server, a: Allocator, only: ?[]const []const u8) server_mod.Error!void {
    var uris: std.ArrayList([]const u8) = .empty;
    var it = s.docs.iterator();
    while (it.next()) |e| {
        if (only) |paths| {
            const p = e.value_ptr.path orelse continue;
            if (!contains(paths, p)) continue;
        }
        try uris.append(a, try a.dupe(u8, e.key_ptr.*));
    }
    var done: std.StringHashMapUnmanaged(void) = .empty;
    for (uris.items) |uri| {
        if (done.contains(uri)) continue;
        const sources = try run(s, a, uri) orelse continue;
        for (sources) |src| try done.put(a, src.uri, {});
        pending.settle(s, sources);
        try publish(s, a, sources, false);
    }
}

fn contains(paths: []const []const u8, path: []const u8) bool {
    for (paths) |p| if (std.mem.eql(u8, p, path)) return true;
    return false;
}

/// Checks the unit of the open document `uri`: its files with their
/// diagnostics, null when it is not checked (no compiler, no document, or
/// `cesium0` and a document that is no file)
pub fn run(s: *Server, a: Allocator, uri: []const u8) server_mod.Error!?[]Source {
    const doc = s.docs.get(uri) orelse return null;
    const c = s.compiler orelse return null;
    const sources = try unitSources(s, a, uri, doc);
    if (sources.len == 0) return null;
    // the document itself, for messages without a place
    var own: usize = 0;
    for (sources, 0..) |src, i| if (std.mem.eql(u8, src.uri, uri)) {
        own = i;
    };
    const texts = try a.alloc([]const u8, sources.len);
    for (sources, texts) |src, *t| t.* = src.text;
    const joined = try line_map.join(a, texts);
    // cesium0 reads files only: a document that is not one is not checked
    const paths = try a.alloc([]const u8, sources.len);
    for (sources, paths) |src, *p| p.* = src.path orelse if (c.kind == .cesium0) return null else "";

    const out = compiler.run(a, s.io, c, paths, joined.input) catch |e| {
        try s.log(a, 1, "cannot run {s}: {t}", .{ c.path, e });
        return null;
    };
    switch (out.term) {
        .exited => |code| if (code > 2) try s.log(a, 1, "{s} ended with exit code {d}", .{ c.path, code }),
        else => try s.log(a, 1, "{s} ended abnormally: {any}", .{ c.path, out.term }),
    }
    const failed = switch (out.term) {
        .exited => |code| code != 0,
        else => true,
    };
    const found = try collect(a, sources, texts, joined.starts, c.kind, own, out.messages);
    if (failed and !found) {
        const first = std.mem.trimEnd(u8, out.messages[0 .. std.mem.findScalar(u8, out.messages, '\n') orelse out.messages.len], "\r");
        try s.log(a, 1, "{s} failed without a message: {s}", .{ c.path, first });
    }
    return sources;
}

/// The files of the unit of `doc`, with the text of the open ones
fn unitSources(s: *Server, a: Allocator, uri: []const u8, doc: server_mod.Doc) server_mod.Error![]Source {
    const path = doc.path orelse {
        const one = try a.alloc(Source, 1);
        one[0] = .{ .uri = uri, .path = null, .text = doc.text };
        return one;
    };
    const files = try unit.files(a, s.io, path);
    var out: std.ArrayList(Source) = .empty;
    for (files) |f| {
        if (openDoc(s, f)) |e| {
            try out.append(a, .{ .uri = e.key_ptr.*, .path = f, .text = e.value_ptr.text });
            continue;
        }
        const text = std.Io.Dir.cwd().readFileAlloc(s.io, f, a, .limited(64 << 20)) catch |e| {
            try s.log(a, 2, "{s} is left out of its unit: {t}", .{ f, e });
            continue;
        };
        try out.append(a, .{ .uri = try uri_mod.fromPath(a, f, s.style), .path = f, .text = text });
    }
    return out.items;
}

fn openDoc(s: *Server, path: []const u8) ?std.StringHashMapUnmanaged(server_mod.Doc).Entry {
    var it = s.docs.iterator();
    while (it.next()) |e| if (e.value_ptr.path) |p| if (std.mem.eql(u8, p, path)) return e;
    return null;
}

/// Adds the diagnostics of a compiler's `output` to the sources they belong
/// to (`texts`: theirs, `starts`: line_map.join's); returns whether there
/// were any. `own` is the document checked.
pub fn collect(a: Allocator, sources: []Source, texts: []const []const u8, starts: []const usize, kind: compiler.Kind, own: usize, output: []const u8) Allocator.Error!bool {
    var found = false;
    var it: messages.Iterator = .init(output);
    while (it.next()) |m| {
        found = true;
        const at = place(sources, texts, starts, kind, own, m);
        try sources[at.file].diagnostics.append(a, .{
            .range = .{ .start = .{ .line = at.line, .character = at.character }, .end = .{ .line = at.line, .character = at.end } },
            .severity = @backingInt(m.severity),
            .code = m.code,
            .source = @tagName(kind),
            .message = m.text,
        });
    }
    return found;
}

/// Where a message belongs: `cesium1`'s lines count through the joined
/// input, `cesium0` names the file; a message without a place goes on the
/// first line of the document checked
fn place(sources: []const Source, texts: []const []const u8, starts: []const usize, kind: compiler.Kind, own: usize, m: messages.Message) line_map.Place {
    if (m.line == 0) return line_map.position(own, texts[own], 0, 0);
    switch (kind) {
        .cesium1 => return line_map.locate(texts, starts, m.line, m.col),
        .cesium0 => {
            const file = m.file orelse return line_map.position(own, texts[own], 0, 0);
            for (sources, 0..) |src, i| if (src.path) |p| if (std.mem.eql(u8, p, file)) {
                return line_map.position(i, texts[i], m.line - 1, m.col -| 1);
            };
            return line_map.position(own, texts[own], 0, 0);
        },
    }
}

/// Publishes the diagnostics of every file of the unit that has some, or
/// had some published before; `closed_only`: of those that are not open
/// documents
pub fn publish(s: *Server, a: Allocator, sources: []Source, closed_only: bool) server_mod.Error!void {
    for (sources) |src| {
        if (closed_only and s.docs.contains(src.uri)) continue;
        const had = s.published.contains(src.uri);
        if (src.diagnostics.items.len == 0 and !had) continue;
        const version = if (s.docs.get(src.uri)) |d| d.version else null;
        try s.notify(a, "textDocument/publishDiagnostics", lsp.PublishDiagnosticsParams{
            .uri = src.uri,
            .version = version,
            .diagnostics = src.diagnostics.items,
        });
        if (src.diagnostics.items.len > 0 and !had) {
            const key = try s.gpa.dupe(u8, src.uri);
            s.published.put(s.gpa, key, {}) catch |e| {
                s.gpa.free(key);
                return e;
            };
        } else if (src.diagnostics.items.len == 0) {
            if (s.published.fetchRemove(src.uri)) |kv| s.gpa.free(kv.key);
        }
    }
}

/// Clears what was published of the file at `path`
pub fn forget(s: *Server, a: Allocator, path: []const u8) server_mod.Error!void {
    var it = s.published.keyIterator();
    while (it.next()) |k| {
        const p = try uri_mod.toPath(a, k.*, s.style) orelse continue;
        if (!uri_mod.samePath(s.style, p, path)) continue;
        const key = k.*;
        s.published.removeByPtr(k);
        defer s.gpa.free(key);
        return s.notify(a, "textDocument/publishDiagnostics", lsp.PublishDiagnosticsParams{ .uri = key, .diagnostics = &.{} });
    }
}

/// Clears everything published (no compiler any more)
pub fn clearAll(s: *Server, a: Allocator) server_mod.Error!void {
    var it = s.published.keyIterator();
    while (it.next()) |k| {
        try s.notify(a, "textDocument/publishDiagnostics", lsp.PublishDiagnosticsParams{ .uri = k.*, .diagnostics = &.{} });
        s.gpa.free(k.*);
    }
    s.published.clearRetainingCapacity();
}
