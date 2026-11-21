//! `package_vscode VERSION PLATFORM=ZCSLS... DIST` (`zig build
//! package-vscode -- DIST`), run at the root of the repository: packages the
//! extension as DIST/vscode-cesium-vVERSION-PLATFORM.vsix, once per VS Code
//! platform named, with that ZCSLS in bin/, and once as the universal VSIX
//! without one (it runs `cesium.server.path` or zcsls from the PATH), as
//! zfls's build/package_vscode.zig does. npm builds it and `npx vsce
//! package` packages it, with VERSION set in package.json for the packaging
//! only.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

/// Every build while the server is zcsls is a pre-release (#3, #4)
const pre_release = true;

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const a = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(a);
    if (argv.len < 3) {
        std.debug.print("usage: zig build package-vscode -- DIST\n", .{});
        return 2;
    }
    const version = argv[1];
    checkVersion(version, pre_release) catch |e| {
        std.debug.print("build.zig.zon: version {s}: {s} (a pre-release is 0.<odd>.<patch>, a release has an even minor)\n", .{ version, @errorName(e) });
        return 1;
    };
    const cwd = Io.Dir.cwd();
    const dist_arg = argv[argv.len - 1];
    try cwd.createDirPath(io, dist_arg);
    const dist = try cwd.realPathFileAlloc(io, dist_arg, a);

    try run(io, &.{ "npm", "ci", "--no-audit", "--no-fund" });
    // the version is set for packaging only
    const package_json = try cwd.readFileAlloc(io, "package.json", a, .limited(1 << 20));
    defer cwd.writeFile(io, .{ .sub_path = "package.json", .data = package_json }) catch |e|
        std.debug.print("restoring package.json: {s}\n", .{@errorName(e)});
    try run(io, &.{ "npm", "pkg", "set", try a.print("version={s}", .{version}) });

    defer cwd.deleteTree(io, "bin") catch {};
    var written: std.ArrayList([]const u8) = .empty;
    for (argv[2 .. argv.len - 1]) |arg| {
        const p = splitPlatform(arg) orelse {
            std.debug.print("not PLATFORM=ZCSLS: {s}\n", .{arg});
            return 2;
        };
        try cwd.deleteTree(io, "bin");
        try cwd.createDirPath(io, "bin");
        const exe = if (std.mem.startsWith(u8, p.platform, "win32-")) "bin/zcsls.exe" else "bin/zcsls";
        try Io.Dir.copyFile(cwd, p.zcsls, cwd, exe, io, .{ .permissions = .executable_file });
        try written.append(a, try packageVsix(io, a, dist, version, p.platform));
    }
    try cwd.deleteTree(io, "bin");
    try written.append(a, try packageVsix(io, a, dist, version, null));
    for (written.items) |vsix| {
        const st = try cwd.statFile(io, vsix, .{});
        std.debug.print("{d:>10} {s}\n", .{ st.size, vsix });
    }
    return 0;
}

const PlatformArg = struct { platform: []const u8, zcsls: []const u8 };

/// `PLATFORM=ZCSLS`: a VS Code platform and its zcsls
fn splitPlatform(arg: []const u8) ?PlatformArg {
    const eq = std.mem.findScalar(u8, arg, '=') orelse return null;
    if (eq == 0 or eq + 1 == arg.len) return null;
    return .{ .platform = arg[0..eq], .zcsls = arg[eq + 1 ..] };
}

const VersionError = error{ NotMajorMinorPatch, EvenMinorForPreRelease, OddMinorForRelease };

/// A version is MAJOR.MINOR.PATCH; the Marketplace takes no `-pre`
/// suffixes, so a pre-release has an odd minor and a release an even one
fn checkVersion(version: []const u8, pre: bool) VersionError!void {
    var parts = std.mem.splitScalar(u8, version, '.');
    var nums: [3]u32 = undefined;
    for (&nums) |*n| {
        const part = parts.next() orelse return error.NotMajorMinorPatch;
        n.* = std.fmt.parseInt(u32, part, 10) catch return error.NotMajorMinorPatch;
    }
    if (parts.next() != null) return error.NotMajorMinorPatch;
    const odd = nums[1] % 2 == 1;
    if (pre and !odd) return error.EvenMinorForPreRelease;
    if (!pre and odd) return error.OddMinorForRelease;
}

/// Packages DIST/vscode-cesium-vVERSION-PLATFORM.vsix and returns its path;
/// `platform` null is the universal VSIX, and a platform's takes the zcsls
/// in bin/
fn packageVsix(io: Io, a: Allocator, dist: []const u8, version: []const u8, platform: ?[]const u8) ![]const u8 {
    const vsix = try vsixPath(a, dist, version, platform orelse "universal");
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ "npx", "vsce", "package", "--no-dependencies", "--out", vsix });
    if (platform) |p| try argv.appendSlice(a, &.{ "--target", p });
    if (pre_release) try argv.append(a, "--pre-release");
    try run(io, argv.items);
    return vsix;
}

/// Runs `argv` in the current directory, which must succeed
fn run(io: Io, argv: []const []const u8) !void {
    var child = try std.process.spawn(io, .{ .argv = argv, .stdin = .ignore });
    const term = try child.wait(io);
    if (!term.success()) {
        std.debug.print("{s} {s} failed: {f}\n", .{ argv[0], argv[1], term });
        return error.CommandFailed;
    }
}

fn vsixPath(a: Allocator, dist: []const u8, version: []const u8, platform: []const u8) ![]const u8 {
    return a.print("{s}{c}vscode-cesium-v{s}-{s}.vsix", .{ dist, Io.Dir.path.sep, version, platform });
}

const testing = std.testing;

test checkVersion {
    try checkVersion("0.1.0", true);
    try checkVersion("0.3.12", true);
    try checkVersion("1.0.0", false);
    try testing.expectError(error.EvenMinorForPreRelease, checkVersion("0.2.0", true));
    try testing.expectError(error.OddMinorForRelease, checkVersion("1.1.0", false));
    try testing.expectError(error.NotMajorMinorPatch, checkVersion("0.1.0-pre", true));
    try testing.expectError(error.NotMajorMinorPatch, checkVersion("0.1", true));
    try testing.expectError(error.NotMajorMinorPatch, checkVersion("0.1.0.1", true));
}

test splitPlatform {
    const p = splitPlatform("win32-x64=C:\\cache\\zcsls.exe").?;
    try testing.expectEqualStrings("win32-x64", p.platform);
    try testing.expectEqualStrings("C:\\cache\\zcsls.exe", p.zcsls);
    try testing.expect(splitPlatform("dist") == null);
    try testing.expect(splitPlatform("=x") == null);
    try testing.expect(splitPlatform("linux-x64=") == null);
}

test vsixPath {
    const path = try vsixPath(testing.allocator, "dist", "0.1.0", "universal");
    defer testing.allocator.free(path);
    try testing.expectEqualStrings("dist" ++ [_]u8{Io.Dir.path.sep} ++ "vscode-cesium-v0.1.0-universal.vsix", path);
}
