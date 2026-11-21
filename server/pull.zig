//! Pull diagnostics (`textDocument/diagnostic`, LSP 3.17), as zfls's
//! src/server/pull.zig serves them, for a client that pulls them: a pull
//! checks the document's unit, and the reports of the unit's other open
//! documents are kept for their pulls, until something changes
//! (`Server.generation`). The unit's files that are not open are not pulled,
//! so their diagnostics are published, as to other clients.
//!
//! A report's `resultId` is a hash of its diagnostics; a pull with the last
//! one gets an `unchanged` report.

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;
const lsp = @import("lsp.zig");
const diagnostics = @import("diagnostics.zig");
const server_mod = @import("server.zig");

const Server = server_mod.Server;
const Error = server_mod.Error;

/// The last report of a document: the generation it was made in, its id,
/// and its diagnostics as JSON (owned by the server's allocator)
pub const Result = struct { generation: u64, id: u64, items: []u8 };

pub fn serve(s: *Server, a: Allocator, id: json.Value, params: json.Value) Error!void {
    const p = server_mod.parse(lsp.DocumentDiagnosticParams, a, params) orelse {
        return s.respondError(a, id, lsp.error_codes.invalid_params, "textDocument/diagnostic: no textDocument");
    };
    const r = try result(s, a, p.textDocument.uri);
    const rid = try std.fmt.allocPrint(a, "{x}", .{r.id});
    if (p.previousResultId) |prev| if (std.mem.eql(u8, prev, rid)) {
        return s.respondRaw(a, id, try std.fmt.allocPrint(a, "{{\"kind\":\"unchanged\",\"resultId\":\"{s}\"}}", .{rid}));
    };
    try s.respondRaw(a, id, try std.fmt.allocPrint(a, "{{\"kind\":\"full\",\"resultId\":\"{s}\",\"items\":{s}}}", .{ rid, r.items }));
}

/// The report of `uri`, the one kept when nothing changed since
fn result(s: *Server, a: Allocator, uri: []const u8) Error!Result {
    if (fresh(s, uri)) |r| return r;
    if (try diagnostics.run(s, a, uri)) |sources| {
        for (sources) |src| if (s.docs.contains(src.uri)) try remember(s, src.uri, src.diagnostics.items);
        try diagnostics.publish(s, a, sources, true);
    }
    if (fresh(s, uri)) |r| return r;
    // not checked: no compiler, or a document that is not open
    const none: []const lsp.Diagnostic = &.{};
    if (s.docs.contains(uri)) {
        try remember(s, uri, none);
        return fresh(s, uri).?;
    }
    return .{ .generation = s.generation, .id = std.hash.Wyhash.hash(0, "[]"), .items = try a.dupe(u8, "[]") };
}

fn fresh(s: *const Server, uri: []const u8) ?Result {
    const r = s.results.get(uri) orelse return null;
    return if (r.generation == s.generation) r else null;
}

fn remember(s: *Server, uri: []const u8, items: []const lsp.Diagnostic) Allocator.Error!void {
    const text = try std.fmt.allocPrint(s.gpa, "{f}", .{server_mod.fmtJson(items)});
    errdefer s.gpa.free(text);
    const gop = try s.results.getOrPut(s.gpa, uri);
    if (gop.found_existing) {
        s.gpa.free(gop.value_ptr.items);
    } else {
        gop.key_ptr.* = s.gpa.dupe(u8, uri) catch |e| {
            s.results.removeByPtr(gop.key_ptr);
            return e;
        };
    }
    gop.value_ptr.* = .{ .generation = s.generation, .id = std.hash.Wyhash.hash(0, text), .items = text };
}

/// The document was closed
pub fn forget(s: *Server, uri: []const u8) void {
    const kv = s.results.fetchRemove(uri) orelse return;
    s.gpa.free(kv.key);
    s.gpa.free(kv.value.items);
}

/// The client's diagnostics are out of date: it is asked to pull them
/// again, where it takes that
pub fn refresh(s: *Server, a: Allocator) Error!void {
    if (s.pull and s.refresh) try s.ask(a, "workspace/diagnostic/refresh", null);
}

pub fn deinit(s: *Server) void {
    var it = s.results.iterator();
    while (it.next()) |e| {
        s.gpa.free(e.key_ptr.*);
        s.gpa.free(e.value_ptr.items);
    }
    s.results.deinit(s.gpa);
}
