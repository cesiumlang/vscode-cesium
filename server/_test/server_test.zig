//! Tests of the server's messages, without a compiler, and of where the
//! compilers' messages are placed.

const std = @import("std");
const Io = std.Io;
const testing = std.testing;
const jsonrpc = @import("../jsonrpc.zig");
const Server = @import("../server.zig").Server;
const diagnostics = @import("../diagnostics.zig");
const line_map = @import("../line_map.zig");

/// A server with no compiler on its PATH, writing to `out`
fn testServer(out: *Io.Writer.Allocating) Server {
    return .{ .gpa = testing.allocator, .io = testing.io, .out = &out.writer, .version = "0.0.0", .path_env = null };
}

/// Sends `body` and returns the bodies the server wrote
fn send(s: *Server, out: *Io.Writer.Allocating, arena: *std.heap.ArenaAllocator, body: []const u8) ![]const []const u8 {
    const a = arena.allocator();
    out.clearRetainingCapacity();
    try s.handle(a, body);
    var r: Io.Reader = .fixed(out.written());
    var bodies: std.ArrayList([]const u8) = .empty;
    while (try jsonrpc.readMessage(a, &r)) |m| try bodies.append(a, m);
    return bodies.items;
}

test "initialize, shutdown and exit" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var out: Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    var s = testServer(&out);
    defer s.deinit();

    const early = try send(&s, &out, &arena, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"shutdown\"}");
    try testing.expectEqual(1, early.len);
    try testing.expect(std.mem.find(u8, early[0], "-32002") != null);

    const init = try send(&s, &out, &arena, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"initialize\",\"params\":{\"capabilities\":{}}}");
    try testing.expectEqual(1, init.len);
    try testing.expectEqualStrings(
        "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"capabilities\":{\"textDocumentSync\":{\"openClose\":true,\"change\":1,\"save\":{\"includeText\":false}}},\"serverInfo\":{\"name\":\"zcsls\",\"version\":\"0.0.0\"}}}",
        init[0],
    );

    // no compiler: the client is told so
    const warned = try send(&s, &out, &arena, "{\"jsonrpc\":\"2.0\",\"method\":\"initialized\",\"params\":{}}");
    try testing.expectEqual(1, warned.len);
    try testing.expect(std.mem.find(u8, warned[0], "window/showMessage") != null);

    const unknown = try send(&s, &out, &arena, "{\"jsonrpc\":\"2.0\",\"id\":\"x\",\"method\":\"textDocument/hover\",\"params\":{}}");
    try testing.expect(std.mem.find(u8, unknown[0], "\"id\":\"x\",\"error\":{\"code\":-32601") != null);

    const done = try send(&s, &out, &arena, "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"shutdown\"}");
    try testing.expectEqualStrings("{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":null}", done[0]);
    try testing.expectEqual(0, (try send(&s, &out, &arena, "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}")).len);
    try testing.expect(!s.running);
    try testing.expectEqual(0, s.exitCode());
}

test "the text of open documents follows the client" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var out: Io.Writer.Allocating = .init(testing.allocator);
    defer out.deinit();
    var s = testServer(&out);
    defer s.deinit();
    _ = try send(&s, &out, &arena, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}");
    _ = try send(&s, &out, &arena, "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"untitled:a\",\"languageId\":\"cesium\",\"version\":1,\"text\":\"x\"}}}");
    _ = try send(&s, &out, &arena, "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didChange\",\"params\":{\"textDocument\":{\"uri\":\"untitled:a\",\"version\":2},\"contentChanges\":[{\"text\":\"y\"},{\"text\":\"z\"}]}}");
    const doc = s.docs.get("untitled:a").?;
    try testing.expectEqualStrings("z", doc.text);
    try testing.expectEqual(2, doc.version);
    try testing.expectEqual(null, doc.path);
    _ = try send(&s, &out, &arena, "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didClose\",\"params\":{\"textDocument\":{\"uri\":\"untitled:a\"}}}");
    try testing.expectEqual(0, s.docs.count());
    // the client went away without shutdown
    try testing.expectEqual(1, s.exitCode());
}

test "cesium1's messages go to the file and line they are in" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sources = [_]diagnostics.Source{
        .{ .uri = "file:///u/a.csm", .path = "/u/a.csm", .text = "i32 = main() {\n  return 0;\n}\n" },
        .{ .uri = "file:///u/b.csm", .path = "/u/b.csm", .text = "i32 = f() {\n  return x;\n}" },
    };
    const texts = [_][]const u8{ sources[0].text, sources[1].text };
    const joined = try line_map.join(a, &texts);
    try testing.expect(try diagnostics.collect(a, &sources, &texts, joined.starts, .cesium1, 0, "5:10: error: unknown name 'x'\r\n"));
    try testing.expectEqual(0, sources[0].diagnostics.items.len);
    const d = sources[1].diagnostics.items[0];
    try testing.expectEqual(1, d.range.start.line);
    try testing.expectEqual(9, d.range.start.character);
    try testing.expectEqual(10, d.range.end.character);
    try testing.expectEqualStrings("unknown name 'x'", d.message);
    try testing.expectEqualStrings("cesium1", d.source);
}

test "cesium0's messages name their file; one without a place goes to the document" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sources = [_]diagnostics.Source{
        .{ .uri = "file:///u/a.csm", .path = "/u/a.csm", .text = "i32 = g() {\n}\n" },
        .{ .uri = "file:///u/b.csm", .path = "/u/b.csm", .text = "u8 y;\n" },
    };
    const texts = [_][]const u8{ sources[0].text, sources[1].text };
    const joined = try line_map.join(a, &texts);
    const output = "/u/b.csm:1:4: error: expected '=', found ';'\ncesium0: error: line 1: @g does not return a value on every path\n";
    try testing.expect(try diagnostics.collect(a, &sources, &texts, joined.starts, .cesium0, 1, output));
    try testing.expectEqual(0, sources[0].diagnostics.items.len);
    const b = sources[1].diagnostics.items;
    try testing.expectEqual(2, b.len);
    try testing.expectEqual(3, b[0].range.start.character);
    try testing.expectEqual(0, b[1].range.start.line);
    try testing.expectEqualStrings("line 1: @g does not return a value on every path", b[1].message);
    try testing.expect(!try diagnostics.collect(a, &sources, &texts, joined.starts, .cesium0, 0, "data $x\n"));
}
