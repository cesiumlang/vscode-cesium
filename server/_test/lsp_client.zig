//! A plain LSP client for lsp_test.zig, after zfls's tests/lsp_client.zig:
//! it starts `zcsls` and writes messages to its standard input, while a
//! thread reads its messages, answering its requests, and another its
//! standard error. Each wait is bounded, so that a server that does not
//! answer fails the test instead of hanging it.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const json = std.json;
const jsonrpc = @import("jsonrpc");

/// How long a message may take to come
pub const timeout: Io.Duration = .fromSeconds(20);

pub const Client = struct {
    /// what the messages sent are made with
    a: Allocator,
    io: Io,
    child: std.process.Child,
    /// the messages received, valid until `deinit` (under `mutex`)
    arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator),
    mutex: Io.Mutex = .init,
    cond: Io.Condition = .init,
    /// every message the server sent, in order (under `mutex`)
    received: std.ArrayList(json.Value) = .empty,
    /// the server's output ended (under `mutex`)
    closed: bool = false,
    /// what the server wrote to standard error, once it has ended
    stderr: std.ArrayList(u8) = .empty,
    /// which of `received` an `expect` has returned (under `mutex`)
    taken: std.ArrayList(bool) = .empty,
    next_id: i64 = 1,
    out_thread: ?std.Thread = null,
    err_thread: ?std.Thread = null,

    /// Starts `exe` in `env`; `c` must stay in place until `deinit`
    pub fn start(c: *Client, a: Allocator, io: Io, exe: []const u8, env: *const std.process.Environ.Map) !void {
        c.* = .{ .a = a, .io = io, .child = try std.process.spawn(io, .{
            .argv = &.{exe},
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .pipe,
            .environ_map = env,
            .create_no_window = true,
        }) };
        c.out_thread = try std.Thread.spawn(.{}, readOutput, .{c});
        c.err_thread = try std.Thread.spawn(.{}, readStderr, .{c});
    }

    pub fn deinit(c: *Client) void {
        c.child.kill(c.io);
        if (c.out_thread) |t| t.join();
        if (c.err_thread) |t| t.join();
        c.stderr.deinit(std.heap.page_allocator);
        c.arena.deinit();
    }

    /// Sends a request; its id
    pub fn request(c: *Client, method: []const u8, params: anytype) !i64 {
        const id = c.next_id;
        c.next_id += 1;
        try c.send(try std.fmt.allocPrint(c.a, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":\"{s}\",\"params\":{f}}}", .{ id, method, json.fmt(params, .{}) }));
        return id;
    }

    pub fn notify(c: *Client, method: []const u8, params: anytype) !void {
        try c.send(try std.fmt.allocPrint(c.a, "{{\"jsonrpc\":\"2.0\",\"method\":\"{s}\",\"params\":{f}}}", .{ method, json.fmt(params, .{}) }));
    }

    fn send(c: *Client, body: []const u8) !void {
        try write(c.io, c.child.stdin.?, try std.fmt.allocPrint(c.a, "Content-Length: {d}\r\n\r\n{s}", .{ body.len, body }));
    }

    /// The answer to request `id`; the messages before it are kept
    pub fn response(c: *Client, id: i64) !json.Value {
        return c.expect(.{ .id = id });
    }

    /// The first message not taken yet that matches `want`, now taken: a
    /// response to `id`, or a message of `method`, whose `params.uri` ends
    /// with `uri` when given
    pub fn expect(c: *Client, want: struct { id: ?i64 = null, method: ?[]const u8 = null, uri: ?[]const u8 = null }) !json.Value {
        const deadline = Io.Clock.awake.now(c.io).addDuration(timeout);
        c.mutex.lockUncancelable(c.io);
        defer c.mutex.unlock(c.io);
        var i: usize = 0;
        while (true) : (i += 1) {
            while (i >= c.received.items.len) {
                const e = if (c.closed) error.ServerEnded else if (Io.Clock.awake.now(c.io).nanoseconds >= deadline.nanoseconds) error.Timeout else {
                    c.cond.waitTimeout(c.io, &c.mutex, .{ .deadline = .{ .raw = deadline, .clock = .awake } }) catch {};
                    continue;
                };
                std.debug.print("waiting for {?d} {?s} {?s}; the server sent:\n", .{ want.id, want.method, want.uri });
                for (c.received.items) |m| std.debug.print("  {f}\n", .{json.fmt(m, .{})});
                return e;
            }
            if (c.taken.items[i]) continue;
            const m = c.received.items[i];
            const match = if (want.id) |id|
                get(m, "id") == .integer and get(m, "id").integer == id and get(m, "method") == .null
            else if (want.method) |method|
                get(m, "method") == .string and std.mem.eql(u8, get(m, "method").string, method) and
                    if (want.uri) |u| get(get(m, "params"), "uri") == .string and std.mem.endsWith(u8, get(get(m, "params"), "uri").string, u) else true
            else
                false;
            if (!match) continue;
            c.taken.items[i] = true;
            return m;
        }
    }

    /// The number of messages received so far
    pub fn count(c: *Client) usize {
        c.mutex.lockUncancelable(c.io);
        defer c.mutex.unlock(c.io);
        return c.received.items.len;
    }

    /// Whether a message of `method` for `uri` came since message `from`
    pub fn sent(c: *Client, from: usize, method: []const u8, uri: []const u8) bool {
        c.mutex.lockUncancelable(c.io);
        defer c.mutex.unlock(c.io);
        for (c.received.items[from..]) |m| {
            if (get(m, "method") != .string or !std.mem.eql(u8, get(m, "method").string, method)) continue;
            const mu = get(get(m, "params"), "uri");
            if (mu == .string and std.mem.endsWith(u8, mu.string, uri)) return true;
        }
        return false;
    }

    /// Once the server is told to exit: its exit code
    pub fn exitCode(c: *Client) !u8 {
        // both streams end with the server
        for ([_]*?std.Thread{ &c.out_thread, &c.err_thread }) |t| if (t.*) |th| {
            th.join();
            t.* = null;
        };
        const term = c.child.wait(c.io) catch return error.Unexpected;
        return switch (term) {
            .exited => |code| code,
            else => error.Unexpected,
        };
    }

    fn readOutput(c: *Client) void {
        var buf: [64 * 1024]u8 = undefined;
        var reader = c.child.stdout.?.reader(c.io, &buf);
        while (true) {
            const body = (jsonrpc.readMessage(std.heap.page_allocator, &reader.interface) catch null) orelse break;
            defer std.heap.page_allocator.free(body);
            c.keep(body) catch break;
        }
        c.mutex.lockUncancelable(c.io);
        defer c.mutex.unlock(c.io);
        c.closed = true;
        c.cond.broadcast(c.io);
    }

    /// Keeps a message; a request of the server's is answered
    fn keep(c: *Client, body: []const u8) !void {
        c.mutex.lockUncancelable(c.io);
        defer c.mutex.unlock(c.io);
        const a = c.arena.allocator();
        const m = try json.parseFromSliceLeaky(json.Value, a, body, .{});
        try c.taken.append(a, false);
        try c.received.append(a, m);
        c.cond.broadcast(c.io);
        if (get(m, "id") == .null or get(m, "method") == .null) return;
        const answer = try std.fmt.allocPrint(a, "{{\"jsonrpc\":\"2.0\",\"id\":{f},\"result\":null}}", .{json.fmt(get(m, "id"), .{})});
        try write(c.io, c.child.stdin.?, try std.fmt.allocPrint(a, "Content-Length: {d}\r\n\r\n{s}", .{ answer.len, answer }));
    }

    fn readStderr(c: *Client) void {
        var buf: [4096]u8 = undefined;
        var reader = c.child.stderr.?.reader(c.io, &buf);
        reader.interface.appendRemainingUnlimited(std.heap.page_allocator, &c.stderr) catch {};
    }
};

/// One framed message at a time: the two threads both write
var write_lock: Io.Mutex = .init;

fn write(io: Io, file: Io.File, framed: []const u8) !void {
    write_lock.lockUncancelable(io);
    defer write_lock.unlock(io);
    try file.writeStreamingAll(io, framed);
}

/// The member `name` of `v`, null when there is none
pub fn get(v: json.Value, name: []const u8) json.Value {
    if (v != .object) return .null;
    return v.object.get(name) orelse .null;
}
