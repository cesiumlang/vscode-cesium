//! The open documents, in full text sync (`didOpen`, `didChange`,
//! `didSave`, `didClose`), and the checks they start. To a client that
//! pulls diagnostics, a change only makes the last ones out of date
//! (pull.zig); to the others, the unit is checked when a document is opened
//! or saved, and after a change once the text has rested (pending.zig).
//! `cesium0` reads files, so only a save changes what it finds.

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;
const lsp = @import("lsp.zig");
const uri_mod = @import("uri.zig");
const diagnostics = @import("diagnostics.zig");
const pending = @import("pending.zig");
const pull = @import("pull.zig");
const server_mod = @import("server.zig");

const Server = server_mod.Server;
const Error = server_mod.Error;
const parse = server_mod.parse;

pub const Doc = struct {
    /// owned by the server's allocator, as is `path`
    text: []u8,
    version: i64,
    /// null for a document that is not a local file
    path: ?[]u8,
};

pub fn freeDoc(gpa: Allocator, d: Doc) void {
    gpa.free(d.text);
    if (d.path) |p| gpa.free(p);
}

pub fn didOpen(s: *Server, a: Allocator, params: json.Value) Error!void {
    const p = parse(lsp.DidOpenParams, a, params) orelse return;
    try open(s, p.textDocument);
    s.generation +%= 1;
    if (!s.pull) return diagnostics.check(s, a, p.textDocument.uri);
    // the client pulls those of an open document: what was published of
    // the file while it was closed goes
    if (s.docs.get(p.textDocument.uri).?.path) |path| try diagnostics.forget(s, a, path);
}

pub fn didChange(s: *Server, a: Allocator, params: json.Value) Error!void {
    const p = parse(lsp.DidChangeParams, a, params) orelse return;
    // full sync: the last change is the whole text
    if (p.contentChanges.len == 0) return;
    const d = s.docs.getPtr(p.textDocument.uri) orelse return;
    const new = try s.gpa.dupe(u8, p.contentChanges[p.contentChanges.len - 1].text);
    s.gpa.free(d.text);
    d.text = new;
    d.version = p.textDocument.version;
    const c = s.compiler orelse return;
    if (c.kind == .cesium0) return;
    s.generation +%= 1;
    try pending.schedule(s, a, p.textDocument.uri);
}

pub fn didSave(s: *Server, a: Allocator, params: json.Value) Error!void {
    const p = parse(lsp.TextDocumentParams, a, params) orelse return;
    if (!s.pull) return diagnostics.check(s, a, p.textDocument.uri);
    const c = s.compiler orelse return;
    if (c.kind != .cesium0) return;
    s.generation +%= 1;
    try pull.refresh(s, a);
}

/// Forgets the document and clears its diagnostics
pub fn didClose(s: *Server, a: Allocator, params: json.Value) Error!void {
    const p = parse(lsp.TextDocumentParams, a, params) orelse return;
    const uri = p.textDocument.uri;
    if (s.docs.fetchRemove(uri)) |kv| {
        s.gpa.free(kv.key);
        freeDoc(s.gpa, kv.value);
    }
    // its unit now reads the file instead
    s.generation +%= 1;
    pending.cancel(s, uri);
    pull.forget(s, uri);
    if (s.published.fetchRemove(uri)) |kv| {
        defer s.gpa.free(kv.key);
        try s.notify(a, "textDocument/publishDiagnostics", lsp.PublishDiagnosticsParams{ .uri = uri, .diagnostics = &.{} });
    }
}

fn open(s: *Server, item: lsp.TextDocumentItem) Error!void {
    const text = try s.gpa.dupe(u8, item.text);
    errdefer s.gpa.free(text);
    const path = try uri_mod.toPath(s.gpa, item.uri, s.style);
    errdefer if (path) |p| s.gpa.free(p);
    const gop = try s.docs.getOrPut(s.gpa, item.uri);
    if (gop.found_existing) {
        freeDoc(s.gpa, gop.value_ptr.*);
    } else {
        gop.key_ptr.* = s.gpa.dupe(u8, item.uri) catch |e| {
            s.docs.removeByPtr(gop.key_ptr);
            return e;
        };
    }
    gop.value_ptr.* = .{ .text = text, .version = item.version, .path = path };
}
