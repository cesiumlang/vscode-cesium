//! zcsls, the bootstrap Cesium language server (cesiumlang/vscode-cesium#7):
//! LSP over standard input and output, with diagnostics from the bootstrap
//! compilers. It stands in until the compiler's own `cesium lsp` answers
//! the same requests.
//!
//!   zcsls             serve on standard input and output
//!   zcsls --version   print the version

const std = @import("std");
const Io = std.Io;
const build_options = @import("build_options");
const jsonrpc = @import("jsonrpc.zig");
const stdio = @import("stdio.zig");
const Server = @import("server.zig").Server;

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--version")) {
            var buf: [64]u8 = undefined;
            var w = stdio.stdout().writerStreaming(io, &buf);
            try w.interface.print("zcsls {s}\n", .{build_options.version});
            try w.interface.flush();
            return 0;
        }
        // what clients pass to pick standard I/O, which is the only transport
        if (std.mem.eql(u8, arg, "--stdio")) continue;
        std.debug.print("usage: zcsls [--version]\n", .{});
        return 2;
    }

    var in_buf: [64 * 1024]u8 = undefined;
    var reader = stdio.stdin().readerStreaming(io, &in_buf);
    var out_buf: [64 * 1024]u8 = undefined;
    var writer = stdio.stdout().writerStreaming(io, &out_buf);
    var server: Server = .{
        .gpa = gpa,
        .io = io,
        .out = &writer.interface,
        .version = build_options.version,
        .path_env = init.environ_map.get("PATH"),
    };
    defer server.deinit();

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    while (server.running) {
        _ = arena.reset(.retain_capacity);
        const a = arena.allocator();
        const body = jsonrpc.readMessage(a, &reader.interface) catch |e| {
            std.debug.print("zcsls: reading a message: {t}\n", .{e});
            return 1;
        } orelse break;
        server.handle(a, body) catch |e| {
            std.debug.print("zcsls: {t}\n", .{e});
            return 1;
        };
    }
    return server.exitCode();
}

test {
    _ = @import("jsonrpc.zig");
    _ = @import("uri.zig");
    _ = @import("unit.zig");
    _ = @import("messages.zig");
    _ = @import("line_map.zig");
    _ = @import("compiler.zig");
    _ = @import("diagnostics.zig");
    _ = @import("_test/server_test.zig");
}
