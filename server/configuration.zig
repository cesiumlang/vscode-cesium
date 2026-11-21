//! The settings at `initialize` (`initializationOptions`) and after
//! `workspace/didChangeConfiguration` (settings.zig), applied at once: a new
//! `compiler.path` finds the compiler again and checks the open documents'
//! units again, or asks a client that pulls diagnostics to pull them again.
//! A new `diagnosticsChangeDelay` applies from the next change.

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;
const lsp = @import("lsp.zig");
const compiler = @import("compiler.zig");
const settings = @import("settings.zig");
const diagnostics = @import("diagnostics.zig");
const pending = @import("pending.zig");
const pull = @import("pull.zig");
const server_mod = @import("server.zig");

const Server = server_mod.Server;
const Error = server_mod.Error;

pub fn load(s: *Server, a: Allocator, options: json.Value) Error!void {
    _ = try settings.apply(s.gpa, &s.settings, options);
    try findCompiler(s, a);
}

pub fn didChange(s: *Server, a: Allocator, params: json.Value) Error!void {
    const changed = try settings.apply(s.gpa, &s.settings, server_mod.field(params, "settings"));
    if (!changed.compiler) return;
    try findCompiler(s, a);
    try logCompiler(s, a, true);
    s.generation +%= 1;
    pending.clear(s);
    if (s.compiler == null) try diagnostics.clearAll(s, a);
    if (s.pull) return pull.refresh(s, a);
    if (s.compiler != null) try diagnostics.checkOpen(s, a, null);
}

/// The compiler `compiler.path` names, else one on the PATH
fn findCompiler(s: *Server, a: Allocator) Error!void {
    if (s.compiler) |c| s.gpa.free(c.path);
    s.compiler = null;
    const configured = if (s.settings.compiler_path) |p| try settings.resolvePath(a, p, s.root, s.home) else null;
    s.compiler = try compiler.find(s.gpa, s.io, configured, s.path_env);
}

/// Says which compiler checks; `changed`: after a change of the settings,
/// when no compiler is also shown to the user
pub fn logCompiler(s: *Server, a: Allocator, changed: bool) Error!void {
    if (s.compiler) |c| return s.log(a, 3, "checking with {s} ({s})", .{ c.path, @tagName(c.kind) });
    if (s.settings.compiler_path) |p| try s.log(a, 1, "cesium.compiler.path: no compiler at {s}", .{p});
    if (changed) try warnNoCompiler(s, a);
}

pub fn warnNoCompiler(s: *Server, a: Allocator) Error!void {
    try s.notify(a, "window/showMessage", lsp.MessageParams{
        .type = 2,
        .message = "Cesium: no cesium1 or cesium0 found, so there are no diagnostics. Set cesium.compiler.path, or put a compiler on the PATH.",
    });
}
