//! The client's messages, read by a task of their own, as zfls's
//! src/__main__.zig reads them, so that the server can wait for one only
//! until the next check is due (pending.zig).

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const jsonrpc = @import("jsonrpc.zig");
const stdio = @import("stdio.zig");

pub const Inbox = struct {
    gpa: Allocator,
    io: Io,
    mutex: Io.Mutex = .init,
    cond: Io.Condition = .init,
    /// the messages read and not taken yet, owned by `gpa`
    queue: std.ArrayList([]u8) = .empty,
    /// the input has ended, or failed (`failure`)
    ended: bool = false,
    failure: ?jsonrpc.ReadError = null,

    pub const Next = union(enum) {
        /// owned by `gpa`
        message: []u8,
        /// the deadline came first
        timeout,
        end,
        failed: jsonrpc.ReadError,
    };

    /// Reads standard input until it ends or fails, or the task is canceled
    pub fn read(inbox: *Inbox) void {
        const io = inbox.io;
        var buf: [64 * 1024]u8 = undefined;
        var reader = stdio.stdin().readerStreaming(io, &buf);
        while (true) {
            const message = jsonrpc.readMessage(inbox.gpa, &reader.interface);
            inbox.mutex.lockUncancelable(io);
            defer inbox.mutex.unlock(io);
            defer inbox.cond.signal(io);
            const body = (message catch |e| {
                inbox.failure = e;
                inbox.ended = true;
                return;
            }) orelse {
                inbox.ended = true;
                return;
            };
            inbox.queue.append(inbox.gpa, body) catch {
                inbox.gpa.free(body);
                inbox.failure = error.OutOfMemory;
                inbox.ended = true;
                return;
            };
        }
    }

    /// The next message, waiting for it at most until `deadline` (the awake
    /// clock's nanoseconds; null: no limit)
    pub fn next(inbox: *Inbox, deadline: ?i96) Next {
        const io = inbox.io;
        inbox.mutex.lockUncancelable(io);
        defer inbox.mutex.unlock(io);
        while (inbox.queue.items.len == 0 and !inbox.ended) {
            const t = deadline orelse {
                inbox.cond.waitUncancelable(io, &inbox.mutex);
                continue;
            };
            if (Io.Clock.awake.now(io).nanoseconds >= t) return .timeout;
            inbox.cond.waitTimeout(io, &inbox.mutex, .{ .deadline = .{ .raw = .{ .nanoseconds = t }, .clock = .awake } }) catch {};
        }
        if (inbox.queue.items.len > 0) return .{ .message = inbox.queue.orderedRemove(0) };
        if (inbox.failure) |e| return .{ .failed = e };
        return .end;
    }

    /// Once the task has ended
    pub fn deinit(inbox: *Inbox) void {
        for (inbox.queue.items) |b| inbox.gpa.free(b);
        inbox.queue.deinit(inbox.gpa);
    }
};
