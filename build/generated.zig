//! `generated ROOT [--check]`: writes the files of the repository at ROOT that
//! are generated from others, or with `--check` fails when one is out of
//! date (`zig build generated`, `zig build check-generated`). Adapted from
//! zfls's build/generated.zig.
//!
//! - package.nls.json, the user-visible strings of package.json, which
//!   refers to them as `%key%`: a translation is a
//!   package.nls.<language>.json of the same keys. Strings already moved are
//!   left alone, so this runs again after new settings or commands are added.
//! - l10n/bundle.l10n.json, the messages the extension shows while it runs
//!   (each `vscode.l10n.t("...")` of its sources), in the format of
//!   `@vscode/l10n-dev export`: each message is its own key.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Value = std.json.Value;

const package_path = "package.json";
const nls_path = "package.nls.json";
const bundle_path = "l10n/bundle.l10n.json";
const sources_path = "src";

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const a = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(a);
    const check = argv.len == 3 and std.mem.eql(u8, argv[2], "--check");
    if (argv.len != 2 and !check) {
        std.debug.print("usage: generated ROOT [--check]\n", .{});
        return 2;
    }
    var root = try Io.Dir.cwd().openDir(io, argv[1], .{});
    defer root.close(io);

    var where: []const u8 = "";
    const files = generate(io, a, root, &where) catch |e| {
        std.debug.print("{s}: {s}\n", .{ where, @errorName(e) });
        return 1;
    };
    var stale = false;
    for (files) |f| {
        if (f.changed) |changed| if (!changed) continue;
        const old = root.readFileAlloc(io, f.path, a, .limited(16 << 20)) catch |e| switch (e) {
            error.FileNotFound => "",
            else => return e,
        };
        if (std.mem.eql(u8, old, f.text)) continue;
        if (check) {
            std.debug.print("{s} is out of date: run zig build generated\n", .{f.path});
            stale = true;
            continue;
        }
        if (std.Io.Dir.path.dirname(f.path)) |d| try root.createDirPath(io, d);
        try root.writeFile(io, .{ .sub_path = f.path, .data = f.text });
        std.debug.print("wrote {s}\n", .{f.path});
    }
    return if (stale) 1 else 0;
}

/// A generated file; `changed`, when set, says whether it differs from the
/// one there is, which is otherwise compared with it
const File = struct { path: []const u8, text: []const u8, changed: ?bool = null };

/// The generated files' contents; `where` names what an error is about
fn generate(io: Io, a: Allocator, root: Io.Dir, where: *[]const u8) ![]const File {
    var files: std.ArrayList(File) = .empty;

    where.* = package_path;
    var pkg = try parseFile(io, a, root, package_path);
    where.* = nls_path;
    var strings = try parseFile(io, a, root, nls_path);
    if (strings == .null) strings = .{ .object = .empty };
    where.* = package_path;
    // the files are rewritten only when strings are left to move
    const moved = try moveStrings(a, &pkg, &strings.object) > 0;
    try files.append(a, .{ .path = package_path, .text = try jsonText(a, pkg), .changed = moved });
    try files.append(a, .{ .path = nls_path, .text = try jsonText(a, strings), .changed = moved });

    where.* = sources_path;
    try files.append(a, .{ .path = bundle_path, .text = try jsonText(a, try l10nBundle(io, a, root, where)) });
    return files.items;
}

/// `v` as Python's `json.dumps(v, indent=2)` writes it, with a final newline
fn jsonText(a: Allocator, v: Value) ![]const u8 {
    var out: Io.Writer.Allocating = .init(a);
    try std.json.Stringify.value(v, .{ .whitespace = .indent_2 }, &out.writer);
    try out.writer.writeByte('\n');
    return out.written();
}

/// The JSON of a file, `null` when there is none; numbers are kept as
/// written
fn parseFile(io: Io, a: Allocator, root: Io.Dir, path: []const u8) !Value {
    const text = root.readFileAlloc(io, path, a, .limited(16 << 20)) catch |e| switch (e) {
        error.FileNotFound => return .null,
        else => return e,
    };
    return std.json.parseFromSliceLeaky(Value, a, text, .{ .parse_numbers = false });
}

// package.nls.json

fn isRef(s: []const u8) bool {
    return s.len > 2 and s[0] == '%' and s[s.len - 1] == '%';
}

fn isBlank(s: []const u8) bool {
    return std.mem.trim(u8, s, " \t\r\n").len == 0;
}

const Mover = struct {
    a: Allocator,
    strings: *std.json.ObjectMap,
    moved: usize = 0,

    /// `obj[name]`, a string, to `key`
    fn move(m: *Mover, obj: ?*Value, name: []const u8, key: []const u8) !void {
        const o = obj orelse return;
        if (o.* != .object) return;
        const v = o.object.getPtr(name) orelse return;
        if (v.* != .string or isRef(v.string) or isBlank(v.string)) return;
        try m.strings.put(m.a, key, v.*);
        v.* = .{ .string = try m.a.print("%{s}%", .{key}) };
        m.moved += 1;
    }

    /// Each string of the list `obj[name]`, to `key.<index>`
    fn moveList(m: *Mover, obj: *Value, name: []const u8, key: []const u8) !void {
        const v = obj.object.getPtr(name) orelse return;
        if (v.* != .array) return;
        for (v.array.items, 0..) |*s, i| {
            if (s.* != .string or isRef(s.string) or isBlank(s.string)) continue;
            const k = try m.a.print("{s}.{d}", .{ key, i });
            try m.strings.put(m.a, k, s.*);
            s.* = .{ .string = try m.a.print("%{s}%", .{k}) };
            m.moved += 1;
        }
    }

    /// The descriptions of JSON schema properties, and of theirs
    fn schema(m: *Mover, props: ?*Value, prefix: []const u8) !void {
        const p = props orelse return;
        if (p.* != .object) return;
        for (p.object.keys(), p.object.values()) |name, *prop| {
            if (prop.* != .object) continue;
            const key = try m.a.print("{s}.{s}", .{ prefix, name });
            for ([_][]const u8{ "description", "markdownDescription", "deprecationMessage", "markdownDeprecationMessage" }) |f|
                try m.move(prop, f, try m.a.print("{s}.{s}", .{ key, f }));
            for ([_][]const u8{ "enumDescriptions", "markdownEnumDescriptions" }) |f|
                try m.moveList(prop, f, try m.a.print("{s}.{s}", .{ key, f }));
            try m.schema(prop.object.getPtr("properties"), key);
        }
    }

    fn print(m: *Mover, comptime fmt: []const u8, args: anytype) ![]const u8 {
        return m.a.print(fmt, args);
    }
};

fn field(v: *Value, name: []const u8) ?*Value {
    return if (v.* == .object) v.object.getPtr(name) else null;
}

fn items(v: ?*Value) []Value {
    const x = v orelse return &.{};
    return if (x.* == .array) x.array.items else &.{};
}

fn string(v: *Value, name: []const u8) []const u8 {
    const x = field(v, name) orelse return "";
    return if (x.* == .string) x.string else "";
}

/// Moves the user-visible strings of package.json `pkg` to `strings`;
/// returns how many
fn moveStrings(a: Allocator, pkg: *Value, strings: *std.json.ObjectMap) !usize {
    var m: Mover = .{ .a = a, .strings = strings };
    try m.move(pkg, "displayName", "displayName");
    try m.move(pkg, "description", "description");
    const c = field(pkg, "contributes") orelse return m.moved;
    if (field(c, "configuration")) |configs| {
        const list: []Value = if (configs.* == .array) configs.array.items else @as(*[1]Value, configs);
        for (list) |*conf| {
            try m.move(conf, "title", "configuration.title");
            try m.schema(field(conf, "properties"), "config");
        }
    }
    for (items(field(c, "commands"))) |*cmd| {
        try m.move(cmd, "title", try m.print("command.{s}.title", .{string(cmd, "command")}));
        try m.move(cmd, "category", "command.category");
    }
    for (items(field(c, "taskDefinitions"))) |*task|
        try m.schema(field(task, "properties"), try m.print("taskDefinition.{s}", .{string(task, "type")}));
    for (items(field(c, "debuggers"))) |*dbg| {
        const t = string(dbg, "type");
        try m.move(dbg, "label", try m.print("debugger.{s}.label", .{t}));
        if (field(dbg, "configurationAttributes")) |attrs| if (attrs.* == .object) {
            for (attrs.object.keys(), attrs.object.values()) |request, *r|
                try m.schema(field(r, "properties"), try m.print("debugger.{s}.{s}", .{ t, request }));
        };
        for (items(field(dbg, "configurationSnippets")), 0..) |*snip, i| {
            try m.move(snip, "label", try m.print("debugger.{s}.snippet.{d}.label", .{ t, i }));
            try m.move(snip, "description", try m.print("debugger.{s}.snippet.{d}.description", .{ t, i }));
        }
    }
    if (field(c, "views")) |views| if (views.* == .object) {
        for (views.object.values()) |*list| for (items(list)) |*v|
            try m.move(v, "name", try m.print("view.{s}.name", .{string(v, "id")}));
    };
    for (items(field(c, "walkthroughs"))) |*w| {
        const wid = string(w, "id");
        try m.move(w, "title", try m.print("walkthrough.{s}.title", .{wid}));
        try m.move(w, "description", try m.print("walkthrough.{s}.description", .{wid}));
        for (items(field(w, "steps"))) |*step| {
            const sid = string(step, "id");
            try m.move(step, "title", try m.print("walkthrough.{s}.{s}.title", .{ wid, sid }));
            try m.move(step, "description", try m.print("walkthrough.{s}.{s}.description", .{ wid, sid }));
        }
    }
    for (items(field(c, "problemMatchers"))) |*p|
        try m.move(p, "label", try m.print("problemMatcher.{s}.label", .{string(p, "name")}));
    return m.moved;
}

// l10n/bundle.l10n.json

fn l10nBundle(io: Io, a: Allocator, root: Io.Dir, where: *[]const u8) !Value {
    var dir = try root.openDir(io, sources_path, .{ .iterate = true });
    defer dir.close(io);
    var paths: std.ArrayList([]const u8) = .empty;
    var walker = try dir.walk(a);
    defer walker.deinit();
    while (try walker.next(io)) |e| {
        if (e.kind == .file and std.mem.endsWith(u8, e.basename, ".ts")) try paths.append(a, try a.dupe(u8, e.path));
    }
    var found: std.array_hash_map.String(void) = .empty;
    for (paths.items) |p| {
        where.* = try a.print("{s}/{s}", .{ sources_path, p });
        const src = try dir.readFileAlloc(io, p, a, .limited(16 << 20));
        var line: usize = 0;
        for (try messages(a, src, &line)) |msg| try found.put(a, msg, {});
        if (line != 0) {
            where.* = try a.print("{s}:{d}: l10n.t needs a string literal (not a template or a variable)", .{ where.*, line });
            return error.NotALiteral;
        }
    }
    const keys = found.keys();
    std.mem.sort([]const u8, keys, {}, struct {
        fn lt(_: void, x: []const u8, y: []const u8) bool {
            return std.mem.order(u8, x, y) == .lt;
        }
    }.lt);
    var out: std.json.ObjectMap = .empty;
    for (keys) |k| try out.put(a, k, .{ .string = k });
    return .{ .object = out };
}

fn isWord(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c >= 0x80;
}

fn isSpace(c: u8) bool {
    return std.ascii.isWhitespace(c);
}

/// The messages of the `l10n.t` calls of a TypeScript source: each a string
/// literal, or literals joined with `+`. A call without one sets `bad_line`
/// to its line.
fn messages(a: Allocator, src: []const u8, bad_line: *usize) ![]const []const u8 {
    const call = "l10n.t(";
    var out: std.ArrayList([]const u8) = .empty;
    var from: usize = 0;
    while (std.mem.findPos(u8, src, from, call)) |start| {
        from = start + call.len;
        if (start > 0 and isWord(src[start - 1])) continue;
        var pos = from;
        while (pos < src.len and isSpace(src[pos])) pos += 1;
        var msg: std.ArrayList(u8) = .empty;
        var parts: usize = 0;
        while (try literal(a, src, pos)) |lit| {
            try msg.appendSlice(a, lit.text);
            parts += 1;
            pos = lit.end;
            var next = pos;
            while (next < src.len and isSpace(src[next])) next += 1;
            if (next >= src.len or src[next] != '+') break;
            next += 1;
            while (next < src.len and isSpace(src[next])) next += 1;
            if ((try literal(a, src, next)) == null) break;
            pos = next;
        }
        if (parts == 0) {
            bad_line.* = std.mem.countScalar(u8, src[0..start], '\n') + 1;
            return out.items;
        }
        try out.append(a, msg.items);
    }
    return out.items;
}

const Literal = struct { text: []const u8, end: usize };

/// The JavaScript string literal at `pos` ('...' or "...", on one line),
/// unescaped as JSON
fn literal(a: Allocator, src: []const u8, pos: usize) !?Literal {
    if (pos >= src.len or (src[pos] != '"' and src[pos] != '\'')) return null;
    const quote = src[pos];
    var i = pos + 1;
    while (i < src.len) : (i += 1) {
        switch (src[i]) {
            '\n' => return null,
            '\\' => {
                if (i + 1 >= src.len or src[i + 1] == '\n') return null;
                i += 1;
            },
            else => if (src[i] == quote) break,
        }
    } else return null;
    const body = src[pos + 1 .. i];
    // a single-quoted literal as a JSON string
    var as_json: std.ArrayList(u8) = .empty;
    try as_json.append(a, '"');
    var j: usize = 0;
    while (j < body.len) : (j += 1) {
        const c = body[j];
        if (quote == '\'' and c == '\\' and body[j + 1] == '\'') {
            try as_json.append(a, '\'');
            j += 1;
        } else if (quote == '\'' and c == '"') {
            try as_json.appendSlice(a, "\\\"");
        } else if (c == '\\') {
            try as_json.appendSlice(a, body[j .. j + 2]);
            j += 1;
        } else try as_json.append(a, c);
    }
    try as_json.append(a, '"');
    const text = try std.json.parseFromSliceLeaky([]const u8, a, as_json.items, .{});
    return .{ .text = text, .end = i + 1 };
}

test "messages" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var bad: usize = 0;
    const msgs = try messages(a,
        \\vscode.l10n.t("one {0}", x);
        \\l10n.t( 'it\'s "two"' );
        \\l10n.t("three, " +
        \\  'and more\n');
        \\notl10n.t("skipped");
        \\l10n.t("a" + b);
    , &bad);
    try std.testing.expectEqual(0, bad);
    try std.testing.expectEqual(4, msgs.len);
    try std.testing.expectEqualStrings("one {0}", msgs[0]);
    try std.testing.expectEqualStrings("it's \"two\"", msgs[1]);
    try std.testing.expectEqualStrings("three, and more\n", msgs[2]);
    try std.testing.expectEqualStrings("a", msgs[3]);

    _ = try messages(a, "x;\nl10n.t(`template ${y}`);", &bad);
    try std.testing.expectEqual(2, bad);
}

test "moveStrings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var pkg = try std.json.parseFromSliceLeaky(Value, a,
        \\{"displayName": "%displayName%", "description": "Cesium",
        \\ "contributes": {"commands": [{"command": "cesium.restart", "title": "Restart", "category": "Cesium"}],
        \\  "configuration": {"title": "Cesium", "properties": {"cesium.server.path": {"description": "The server"}}}}}
    , .{});
    var strings: std.json.ObjectMap = .empty;
    try std.testing.expectEqual(5, try moveStrings(a, &pkg, &strings));
    try std.testing.expectEqualStrings("%description%", pkg.object.get("description").?.string);
    try std.testing.expectEqualStrings("Restart", strings.get("command.cesium.restart.title").?.string);
    try std.testing.expectEqualStrings("The server", strings.get("config.cesium.server.path.description").?.string);
    try std.testing.expect(strings.get("displayName") == null);
    try std.testing.expectEqual(0, try moveStrings(a, &pkg, &strings));
}
