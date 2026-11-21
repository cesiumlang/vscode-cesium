//! A stand-in for `cesium1` in the LSP test (lsp_test.zig): it reads the
//! unit on standard input and reports the first `bad` in it as `cesium1`
//! does, `line:col: error: message` with lines counted through its input.

const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    var buf: [4096]u8 = undefined;
    var r = Io.File.stdin().readerStreaming(io, &buf);
    const input = try r.interface.allocRemaining(init.arena.allocator(), .unlimited);
    const at = std.mem.find(u8, input, "bad") orelse return 0;
    const line = std.mem.countScalar(u8, input[0..at], '\n') + 1;
    const col = at - (if (std.mem.findScalarLast(u8, input[0..at], '\n')) |nl| nl + 1 else 0) + 1;
    var out_buf: [256]u8 = undefined;
    var w = Io.File.stdout().writerStreaming(io, &out_buf);
    try w.interface.print("{d}:{d}: error: unknown name 'bad'\n", .{ line, col });
    try w.interface.flush();
    return 1;
}
