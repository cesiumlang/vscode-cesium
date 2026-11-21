//! Checks after a change, for a client that does not pull diagnostics, as
//! zfls's src/server/pending.zig has them: a changed document's unit is
//! checked once its text has not changed for `diagnosticsChangeDelay`
//! milliseconds, so that a burst of typing costs one check, of the last
//! text. 0 checks with each change, a negative delay only on open and save.
//! The server's loop (main.zig) waits for a message at most until the next
//! check is due (`next`), and then makes the checks due (`checkDue`).

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const diagnostics = @import("diagnostics.zig");
const server_mod = @import("server.zig");

const Server = server_mod.Server;
const Error = server_mod.Error;

/// The text of `uri` changed
pub fn schedule(s: *Server, a: Allocator, uri: []const u8) Error!void {
    const delay = s.settings.change_delay;
    // a client that pulls them asks when it wants them (pull.zig)
    if (delay < 0 or s.pull or s.state != .running) return;
    if (delay == 0) return diagnostics.check(s, a, uri);
    const when = Io.Clock.awake.now(s.io).nanoseconds + @as(i96, delay) * std.time.ns_per_ms;
    const gop = try s.due.getOrPut(s.gpa, uri);
    if (!gop.found_existing) {
        gop.key_ptr.* = s.gpa.dupe(u8, uri) catch |e| {
            s.due.removeByPtr(gop.key_ptr);
            return e;
        };
    }
    gop.value_ptr.* = when;
}

/// The files of a unit were checked: none of them waits any more
pub fn settle(s: *Server, sources: []const diagnostics.Source) void {
    for (sources) |src| cancel(s, src.uri);
}

/// Nothing waits for `uri` any more
pub fn cancel(s: *Server, uri: []const u8) void {
    if (s.due.fetchRemove(uri)) |kv| s.gpa.free(kv.key);
}

/// When the first check is due (the awake clock's nanoseconds); null: none
/// waits
pub fn next(s: *const Server) ?i96 {
    var first: ?i96 = null;
    var it = s.due.valueIterator();
    while (it.next()) |t| first = if (first) |f| @min(f, t.*) else t.*;
    return first;
}

/// Makes the checks that are due now
pub fn checkDue(s: *Server, a: Allocator) Error!void {
    const now = Io.Clock.awake.now(s.io).nanoseconds;
    var due: std.ArrayList([]const u8) = .empty;
    var it = s.due.iterator();
    while (it.next()) |e| if (e.value_ptr.* <= now) try due.append(a, try a.dupe(u8, e.key_ptr.*));
    for (due.items) |uri| {
        // checked already with another file of its unit
        if (!s.due.contains(uri)) continue;
        cancel(s, uri);
        try diagnostics.check(s, a, uri);
    }
}

/// Nothing waits any more (`shutdown`, new settings)
pub fn clear(s: *Server) void {
    var it = s.due.keyIterator();
    while (it.next()) |k| s.gpa.free(k.*);
    s.due.clearRetainingCapacity();
}

pub fn deinit(s: *Server) void {
    clear(s);
    s.due.deinit(s.gpa);
}
