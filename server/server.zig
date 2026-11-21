//! The language server's state and the messages it answers: `initialize`,
//! `initialized`, `shutdown`, `exit`, and those of documents.zig
//! (full text sync), configuration.zig (settings), pull.zig (pull
//! diagnostics) and watched.zig (files changed on disk). Diagnostics are
//! diagnostics.zig's.

const std = @import("std");
const sysinfo = @import("builtin");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const json = std.json;
const jsonrpc = @import("jsonrpc.zig");
const lsp = @import("lsp.zig");
const uri_mod = @import("uri.zig");
const compiler = @import("compiler.zig");
const settings_mod = @import("settings.zig");
const configuration = @import("configuration.zig");
const documents = @import("documents.zig");
const pending = @import("pending.zig");
const pull = @import("pull.zig");
const watched = @import("watched.zig");

pub const Doc = documents.Doc;

pub const Error = Io.Writer.Error || Allocator.Error || Io.Cancelable;

pub const Server = struct {
    gpa: Allocator,
    io: Io,
    out: *Io.Writer,
    version: []const u8,
    /// the PATH the compilers are looked for on
    path_env: ?[]const u8,
    /// what a leading `~` of a path setting is
    home: ?[]const u8 = null,
    style: uri_mod.Style = if (sysinfo.os.tag == .windows) .windows else .posix,
    /// the workspace's directory, which relative path settings are under
    /// (owned by `gpa`)
    root: ?[]u8 = null,
    settings: settings_mod.Settings = .{},
    /// owned by `gpa`, found from the settings
    compiler: ?compiler.Compiler = null,
    /// the open documents by URI (keys owned by `gpa`)
    docs: std.StringHashMapUnmanaged(Doc) = .empty,
    /// the URIs with diagnostics published, which a later check clears
    /// (keys owned by `gpa`)
    published: std.StringHashMapUnmanaged(void) = .empty,
    /// the client pulls diagnostics, and can be asked to pull again
    pull: bool = false,
    refresh: bool = false,
    /// the client watches files for the server when asked
    watch: bool = false,
    /// counted at each change that can change the diagnostics of a check
    generation: u64 = 0,
    /// pull.zig: the last report of each open document
    results: std.StringHashMapUnmanaged(pull.Result) = .empty,
    /// pending.zig: when each changed document is to be checked
    due: std.StringHashMapUnmanaged(i96) = .empty,
    /// the id of the next request to the client
    next_id: i64 = 1,
    state: enum { uninitialized, running, shut_down } = .uninitialized,
    /// false once `exit` has come
    running: bool = true,

    pub fn deinit(s: *Server) void {
        var it = s.docs.iterator();
        while (it.next()) |e| {
            s.gpa.free(e.key_ptr.*);
            documents.freeDoc(s.gpa, e.value_ptr.*);
        }
        s.docs.deinit(s.gpa);
        var pit = s.published.keyIterator();
        while (pit.next()) |k| s.gpa.free(k.*);
        s.published.deinit(s.gpa);
        pull.deinit(s);
        pending.deinit(s);
        s.settings.deinit(s.gpa);
        if (s.compiler) |c| s.gpa.free(c.path);
        if (s.root) |r| s.gpa.free(r);
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
        // a response to a request of the server's: nothing waits for it
        const method = switch (msg.object.get("method") orelse return) {
            .string => |m| m,
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
            pending.clear(s);
            return s.respond(a, id, null);
        }
        if (std.mem.eql(u8, method, "textDocument/diagnostic")) return pull.serve(s, a, id, params);
        return s.respondError(a, id, lsp.error_codes.method_not_found, method);
    }

    fn notification(s: *Server, a: Allocator, method: []const u8, params: json.Value) Error!void {
        if (std.mem.eql(u8, method, "exit")) {
            s.running = false;
            return;
        }
        if (s.state != .running) return;
        const handlers = .{
            .{ "initialized", initialized },
            .{ "textDocument/didOpen", documents.didOpen },
            .{ "textDocument/didChange", documents.didChange },
            .{ "textDocument/didSave", documents.didSave },
            .{ "textDocument/didClose", documents.didClose },
            .{ "workspace/didChangeConfiguration", configuration.didChange },
            .{ "workspace/didChangeWatchedFiles", watched.didChange },
        };
        inline for (handlers) |h| if (std.mem.eql(u8, method, h[0])) return h[1](s, a, params);
    }

    fn initialize(s: *Server, a: Allocator, id: json.Value, params: json.Value) Error!void {
        if (s.state != .uninitialized) return s.respondError(a, id, lsp.error_codes.invalid_request, "initialized already");
        const caps = parse(lsp.ClientCapabilities, a, field(params, "capabilities")) orelse lsp.ClientCapabilities{};
        s.pull = caps.textDocument.diagnostic != null;
        s.refresh = caps.workspace.diagnostics.refreshSupport;
        s.watch = caps.workspace.didChangeWatchedFiles.dynamicRegistration;
        s.root = try rootOf(s, params);
        try configuration.load(s, a, field(params, "initializationOptions"));
        s.state = .running;
        try s.respond(a, id, lsp.InitializeResult{
            .capabilities = .{ .diagnosticProvider = if (s.pull) .{} else null },
            .serverInfo = .{ .name = "zcsls", .version = s.version },
        });
        try configuration.logCompiler(s, a, false);
    }

    fn initialized(s: *Server, a: Allocator, _: json.Value) Error!void {
        try watched.register(s, a);
        if (s.compiler == null) try configuration.warnNoCompiler(s, a);
    }

    /// `window/logMessage` of `type` (1 error ... 4 log)
    pub fn log(s: *Server, a: Allocator, @"type": u8, comptime fmt: []const u8, args: anytype) Error!void {
        try s.notify(a, "window/logMessage", lsp.MessageParams{ .type = @"type", .message = try std.fmt.allocPrint(a, fmt, args) });
    }

    pub fn notify(s: *Server, a: Allocator, method: []const u8, params: anytype) Error!void {
        const body = try std.fmt.allocPrint(a, "{{\"jsonrpc\":\"2.0\",\"method\":{f},\"params\":{f}}}", .{ fmtJson(method), fmtJson(params) });
        try jsonrpc.writeMessage(s.out, body);
    }

    /// A request to the client, whose answer is not waited for; `params`
    /// null sends none
    pub fn ask(s: *Server, a: Allocator, method: []const u8, params: anytype) Error!void {
        const id = s.next_id;
        s.next_id += 1;
        const body = if (@TypeOf(params) == @TypeOf(null))
            try std.fmt.allocPrint(a, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":{f}}}", .{ id, fmtJson(method) })
        else
            try std.fmt.allocPrint(a, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":{f},\"params\":{f}}}", .{ id, fmtJson(method), fmtJson(params) });
        try jsonrpc.writeMessage(s.out, body);
    }

    pub fn respond(s: *Server, a: Allocator, id: json.Value, result: anytype) Error!void {
        const body = try std.fmt.allocPrint(a, "{{\"jsonrpc\":\"2.0\",\"id\":{f},\"result\":{f}}}", .{ fmtJson(id), fmtJson(result) });
        try jsonrpc.writeMessage(s.out, body);
    }

    /// A response whose `result` is the JSON text `raw`
    pub fn respondRaw(s: *Server, a: Allocator, id: json.Value, raw: []const u8) Error!void {
        const body = try std.fmt.allocPrint(a, "{{\"jsonrpc\":\"2.0\",\"id\":{f},\"result\":{s}}}", .{ fmtJson(id), raw });
        try jsonrpc.writeMessage(s.out, body);
    }

    pub fn respondError(s: *Server, a: Allocator, id: json.Value, code: i64, message: []const u8) Error!void {
        const e: lsp.ResponseError = .{ .code = code, .message = message };
        const body = try std.fmt.allocPrint(a, "{{\"jsonrpc\":\"2.0\",\"id\":{f},\"error\":{f}}}", .{ fmtJson(id), fmtJson(e) });
        try jsonrpc.writeMessage(s.out, body);
    }
};

/// The workspace's directory: `rootUri`, else the first of
/// `workspaceFolders`, else `rootPath`; owned by `s.gpa`
fn rootOf(s: *Server, params: json.Value) Allocator.Error!?[]u8 {
    if (field(params, "rootUri") == .string) return uri_mod.toPath(s.gpa, field(params, "rootUri").string, s.style);
    const folders = field(params, "workspaceFolders");
    if (folders == .array and folders.array.items.len > 0) {
        const u = field(folders.array.items[0], "uri");
        if (u == .string) return uri_mod.toPath(s.gpa, u.string, s.style);
    }
    if (field(params, "rootPath") == .string) return try s.gpa.dupe(u8, field(params, "rootPath").string);
    return null;
}

/// The member `name` of `v`, null when there is none
pub fn field(v: json.Value, name: []const u8) json.Value {
    if (v != .object) return .null;
    return v.object.get(name) orelse .null;
}

pub fn fmtJson(v: anytype) json.Formatter(@TypeOf(v)) {
    return json.fmt(v, .{ .emit_null_optional_fields = false });
}

/// `params` as a `T`, or null when they do not fit
pub fn parse(comptime T: type, a: Allocator, params: json.Value) ?T {
    return json.parseFromValueLeaky(T, a, params, .{ .ignore_unknown_fields = true }) catch null;
}
