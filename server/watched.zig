//! Files changed on disk outside the editor (a checkout, a generator): at
//! `initialized` the server asks the client to watch the Cesium files
//! (`workspace/didChangeWatchedFiles`), where it allows that, and checks the
//! units of the open documents that a change concerns again. An open
//! document is left alone, its text being the editor's.

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;
const lsp = @import("lsp.zig");
const uri_mod = @import("uri.zig");
const unit = @import("unit.zig");
const diagnostics = @import("diagnostics.zig");
const pull = @import("pull.zig");
const server_mod = @import("server.zig");

const Server = server_mod.Server;
const Error = server_mod.Error;

pub const pattern = "**/*.{csm,csi}";

pub fn register(s: *Server, a: Allocator) Error!void {
    if (!s.watch) return;
    try s.ask(a, "client/registerCapability", lsp.RegistrationParams{ .registrations = &.{.{
        .id = "cesium-files",
        .method = "workspace/didChangeWatchedFiles",
        .registerOptions = .{ .watchers = &.{.{ .globPattern = pattern }} },
    }} });
}

pub fn didChange(s: *Server, a: Allocator, params: json.Value) Error!void {
    const p = server_mod.parse(lsp.DidChangeWatchedFilesParams, a, params) orelse return;
    // the open documents whose units changed
    var affected: std.ArrayList([]const u8) = .empty;
    var any = false;
    for (p.changes) |ev| {
        const path = try uri_mod.toPath(a, ev.uri, s.style) orelse continue;
        if (isOpen(s, path)) continue;
        any = true;
        // a deleted file's diagnostics go with it
        if (ev.type == 3) try diagnostics.forget(s, a, path);
        const files = try unit.files(a, s.io, path);
        var it = s.docs.valueIterator();
        while (it.next()) |d| {
            const dp = d.path orelse continue;
            for (files) |f| if (uri_mod.samePath(s.style, f, dp)) {
                try affected.append(a, dp);
                break;
            };
        }
    }
    if (!any) return;
    s.generation +%= 1;
    if (s.pull) return pull.refresh(s, a);
    if (affected.items.len > 0) try diagnostics.checkOpen(s, a, affected.items);
}

fn isOpen(s: *const Server, path: []const u8) bool {
    var it = s.docs.valueIterator();
    while (it.next()) |d| if (d.path) |dp| if (uri_mod.samePath(s.style, dp, path)) return true;
    return false;
}
