//! The language server's state and the messages it answers: `initialize`,
//! `initialized`, `shutdown`, `exit` and full text sync (`didOpen`,
//! `didChange`, `didSave`, `didClose`). Diagnostics are diagnostics.zig's.

const std = @import("std");
const sysinfo = @import("builtin");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const json = std.json;
const jsonrpc = @import("jsonrpc.zig");
const lsp = @import("lsp.zig");
const uri_mod = @import("uri.zig");
const compiler = @import("compiler.zig");
const diagnostics = @import("diagnostics.zig");

pub const Doc = struct {
    /// owned by the server's allocator, as is `path`
    text: []u8,
    version: i64,
    /// null for a document that is not a local file
    path: ?[]u8,
};

pub const Error = Io.Writer.Error || Allocator.Error || Io.Cancelable;

pub const Server = struct {
    gpa: Allocator,
    io: Io,
    out: *Io.Writer,
    version: []const u8,
    /// the PATH the compilers are looked for on
    path_env: ?[]const u8,
    style: uri_mod.Style = if (sysinfo.os.tag == .windows) .windows else .posix,
    /// owned by `gpa`, found at `initialize`
    compiler: ?compiler.Compiler = null,
    /// the open documents by URI (keys owned by `gpa`)
    docs: std.StringHashMapUnmanaged(Doc) = .empty,
    /// the URIs with diagnostics published, which a later check clears
    /// (keys owned by `gpa`)
    published: std.StringHashMapUnmanaged(void) = .empty,
    state: enum { uninitialized, running, shut_down } = .uninitialized,
    /// false once `exit` has come
    running: bool = true,

    pub fn deinit(s: *Server) void {
        var it = s.docs.iterator();
        while (it.next()) |e| {
            s.gpa.free(e.key_ptr.*);
            freeDoc(s.gpa, e.value_ptr.*);
        }
        s.docs.deinit(s.gpa);
        var pit = s.published.keyIterator();
        while (pit.next()) |k| s.gpa.free(k.*);
        s.published.deinit(s.gpa);
        if (s.compiler) |c| s.gpa.free(c.path);
    }

    /// The exit code once the client has gone: 0 after `shutdown`
    pub fn exitCode(s: *const Server) u8 {
        return if (s.state == .shut_down) 0 else 1;
    }

    /// Answers one message; `a` is freed after it
    pub fn handle(s: *Server, a: Allocator, body: []const u8) Error!void {
        const msg = json.parseFromSliceLeaky(json.Value, a, body, .{}) catch {
            return s.respondError(a, .null, -32700, "parse error");
        };
        if (msg != .object) return s.respondError(a, .null, lsp.error_codes.invalid_request, "not an object");
        const id = msg.object.get("id");
        const method = switch (msg.object.get("method") orelse return) {
            .string => |m| m,
            // a response: the server sends no requests
            else => return s.respondError(a, id orelse .null, lsp.error_codes.invalid_request, "no method"),
        };
        const params = msg.object.get("params") orelse .null;
        if (id) |i| return s.request(a, i, method, params);
        return s.notification(a, method, params);
    }

    fn request(s: *Server, a: Allocator, id: json.Value, method: []const u8, params: json.Value) Error!void {
        if (std.mem.eql(u8, method, "initialize")) return s.initialize(a, id, params);
        if (s.state == .uninitialized) return s.respondError(a, id, lsp.error_codes.server_not_initialized, "not initialized");
        if (std.mem.eql(u8, method, "shutdown")) {
            s.state = .shut_down;
            return s.respond(a, id, null);
        }
        return s.respondError(a, id, lsp.error_codes.method_not_found, method);
    }

    fn notification(s: *Server, a: Allocator, method: []const u8, params: json.Value) Error!void {
        if (std.mem.eql(u8, method, "exit")) {
            s.running = false;
            return;
        }
        if (s.state != .running) return;
        if (std.mem.eql(u8, method, "initialized")) return s.initialized(a);
        if (std.mem.eql(u8, method, "textDocument/didOpen")) {
            const p = parse(lsp.DidOpenParams, a, params) orelse return;
            try s.open(p.textDocument);
            return diagnostics.check(s, a, p.textDocument.uri);
        }
        if (std.mem.eql(u8, method, "textDocument/didChange")) {
            const p = parse(lsp.DidChangeParams, a, params) orelse return;
            // full sync: the last change is the whole text
            if (p.contentChanges.len == 0) return;
            return s.change(p.textDocument, p.contentChanges[p.contentChanges.len - 1].text);
        }
        if (std.mem.eql(u8, method, "textDocument/didSave")) {
            const p = parse(lsp.TextDocumentParams, a, params) orelse return;
            return diagnostics.check(s, a, p.textDocument.uri);
        }
        if (std.mem.eql(u8, method, "textDocument/didClose")) {
            const p = parse(lsp.TextDocumentParams, a, params) orelse return;
            return s.close(a, p.textDocument.uri);
        }
    }

    fn initialize(s: *Server, a: Allocator, id: json.Value, params: json.Value) Error!void {
        if (s.state != .uninitialized) return s.respondError(a, id, lsp.error_codes.invalid_request, "initialized already");
        const p = parse(lsp.InitializeParams, a, params) orelse lsp.InitializeParams{};
        const configured = if (p.initializationOptions) |o| o.compiler.path else null;
        s.compiler = try compiler.find(s.gpa, s.io, configured, s.path_env);
        s.state = .running;
        try s.respond(a, id, lsp.InitializeResult{ .serverInfo = .{ .name = "zcsls", .version = s.version } });
        if (s.compiler) |c| {
            try s.log(a, 3, "checking with {s} ({s})", .{ c.path, @tagName(c.kind) });
        } else if (configured != null and configured.?.len > 0) {
            try s.log(a, 1, "cesium.compiler.path: no compiler at {s}", .{configured.?});
        }
    }

    fn initialized(s: *Server, a: Allocator) Error!void {
        if (s.compiler != null) return;
        try s.notify(a, "window/showMessage", lsp.MessageParams{
            .type = 2,
            .message = "Cesium: no cesium1 or cesium0 found, so there are no diagnostics. Set cesium.compiler.path, or put a compiler on the PATH.",
        });
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

    fn change(s: *Server, doc: lsp.VersionedTextDocumentIdentifier, text: []const u8) Error!void {
        const d = s.docs.getPtr(doc.uri) orelse return;
        const new = try s.gpa.dupe(u8, text);
        s.gpa.free(d.text);
        d.text = new;
        d.version = doc.version;
    }

    /// Forgets the document and clears its diagnostics
    fn close(s: *Server, a: Allocator, uri: []const u8) Error!void {
        if (s.docs.fetchRemove(uri)) |kv| {
            s.gpa.free(kv.key);
            freeDoc(s.gpa, kv.value);
        }
        if (s.published.fetchRemove(uri)) |kv| {
            defer s.gpa.free(kv.key);
            try s.notify(a, "textDocument/publishDiagnostics", lsp.PublishDiagnosticsParams{ .uri = uri, .diagnostics = &.{} });
        }
    }

    /// `window/logMessage` of `type` (1 error ... 4 log)
    pub fn log(s: *Server, a: Allocator, @"type": u8, comptime fmt: []const u8, args: anytype) Error!void {
        try s.notify(a, "window/logMessage", lsp.MessageParams{ .type = @"type", .message = try std.fmt.allocPrint(a, fmt, args) });
    }

    pub fn notify(s: *Server, a: Allocator, method: []const u8, params: anytype) Error!void {
        const body = try std.fmt.allocPrint(a, "{{\"jsonrpc\":\"2.0\",\"method\":{f},\"params\":{f}}}", .{ fmtJson(method), fmtJson(params) });
        try jsonrpc.writeMessage(s.out, body);
    }

    fn respond(s: *Server, a: Allocator, id: json.Value, result: anytype) Error!void {
        const body = try std.fmt.allocPrint(a, "{{\"jsonrpc\":\"2.0\",\"id\":{f},\"result\":{f}}}", .{ fmtJson(id), fmtJson(result) });
        try jsonrpc.writeMessage(s.out, body);
    }

    fn respondError(s: *Server, a: Allocator, id: json.Value, code: i64, message: []const u8) Error!void {
        const e: lsp.ResponseError = .{ .code = code, .message = message };
        const body = try std.fmt.allocPrint(a, "{{\"jsonrpc\":\"2.0\",\"id\":{f},\"error\":{f}}}", .{ fmtJson(id), fmtJson(e) });
        try jsonrpc.writeMessage(s.out, body);
    }
};

fn freeDoc(gpa: Allocator, d: Doc) void {
    gpa.free(d.text);
    if (d.path) |p| gpa.free(p);
}

fn fmtJson(v: anytype) json.Formatter(@TypeOf(v)) {
    return json.fmt(v, .{ .emit_null_optional_fields = false });
}

/// `params` as a `T`, or null when they do not fit
fn parse(comptime T: type, a: Allocator, params: json.Value) ?T {
    return json.parseFromValueLeaky(T, a, params, .{ .ignore_unknown_fields = true }) catch null;
}
