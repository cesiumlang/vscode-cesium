//! The bootstrap language server zcsls (server/, #7) and the build steps of
//! the extension, in Zig as zfls has them (#3):
//!
//!   zig build                         zcsls in zig-out/bin
//!   zig build test                    the unit tests of zcsls and the tools,
//!                                     and the LSP test of zcsls
//!   zig build package-vscode -- DIST  one VSIX per VS Code platform, each
//!                                     with its zcsls in bin/, and the
//!                                     universal VSIX without one
//!                                     (build/package_vscode.zig); with
//!                                     the option zcsls-dir=DIR, the zcsls
//!                                     staged in DIR instead of building
//!                                     them
//!   zig build stage-zcsls             zcsls for every platform's target in
//!                                     zig-out/zcsls/TARGET/, for CI to sign
//!                                     before packaging (#40)
//!   zig build generated               the files generated from others
//!   zig build check-generated         (build/generated.zig)

const std = @import("std");
const zon = @import("build.zig.zon");

/// The VS Code platforms that get a VSIX with zcsls, and the target it is
/// built for (static on Linux, so that Alpine runs it too)
const platforms = [_]struct { []const u8, []const u8 }{
    .{ "win32-x64", "x86_64-windows" },
    .{ "win32-arm64", "aarch64-windows" },
    .{ "linux-x64", "x86_64-linux-musl" },
    .{ "linux-arm64", "aarch64-linux-musl" },
    .{ "alpine-x64", "x86_64-linux-musl" },
    .{ "alpine-arm64", "aarch64-linux-musl" },
    .{ "darwin-x64", "x86_64-macos" },
    .{ "darwin-arm64", "aarch64-macos" },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const zcsls = addZcsls(b, target, optimize, null);
    b.installArtifact(zcsls);

    const test_step = b.step("test", "Run the unit tests of zcsls and of the build tools");
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = zcsls.root_module })).step);
    test_step.dependOn(&b.addRunArtifact(addLspTest(b, target, optimize, zcsls)).step);

    // one release build per target, which several platforms can share
    var release: [platforms.len]*std.Build.Step.Compile = undefined;
    const stage = b.step("stage-zcsls", "Install zcsls for every platform's target into zig-out/zcsls/TARGET/");
    for (platforms, 0..) |p, i| {
        const first = firstWithTarget(i);
        if (first < i) {
            release[i] = release[first];
            continue;
        }
        const query = std.Target.Query.parse(.{ .arch_os_abi = p[1] }) catch unreachable;
        release[i] = addZcsls(b, b.resolveTargetQuery(query), .ReleaseSafe, true);
        stage.dependOn(&b.addInstallArtifact(release[i], .{
            .dest_dir = .{ .override = .{ .custom = b.fmt("zcsls/{s}", .{p[1]}) } },
            .pdb_dir = .disabled,
            .implib_dir = .disabled,
        }).step);
    }
    test_step.dependOn(&b.addRunArtifact(addPackageVscode(b, &release)).step);
    test_step.dependOn(&b.addRunArtifact(addGenerated(b)).step);
}

fn addZcsls(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, strip: ?bool) *std.Build.Step.Compile {
    const options = b.addOptions();
    options.addOption([]const u8, "version", zon.version);
    const mod = b.createModule(.{
        .root_source_file = b.path("server/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = strip,
    });
    mod.addOptions("build_options", options);
    return b.addExecutable(.{ .name = "zcsls", .root_module = mod });
}

/// The LSP test (server/_test/lsp_test.zig): `zcsls` driven as a plain
/// client drives it, with a stand-in for `cesium1`
fn addLspTest(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, zcsls: *std.Build.Step.Compile) *std.Build.Step.Compile {
    const fake = b.addExecutable(.{ .name = "fake-cesium1", .root_module = b.createModule(.{
        .root_source_file = b.path("server/_test/fake_cesium1.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const paths = b.addOptions();
    paths.addOptionPath("zcsls", zcsls.getEmittedBin());
    paths.addOptionPath("compiler", fake.getEmittedBin());
    const mod = b.createModule(.{
        .root_source_file = b.path("server/_test/lsp_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addOptions("lsp_test_paths", paths);
    mod.addImport("jsonrpc", b.createModule(.{ .root_source_file = b.path("server/jsonrpc.zig") }));
    mod.addImport("uri", b.createModule(.{ .root_source_file = b.path("server/uri.zig") }));
    return b.addTest(.{ .root_module = mod });
}

/// The index of the first platform whose zcsls has the target of platform `i`
fn firstWithTarget(i: usize) usize {
    for (platforms[0..i], 0..) |q, j| {
        if (std.mem.eql(u8, q[1], platforms[i][1])) return j;
    }
    return i;
}

/// `zig build package-vscode -- DIST`:build/package_vscode.zig, run at the
/// root of the repository as `package_vscode VERSION PLATFORM=ZCSLS... DIST`
/// with each platform's zcsls from `release` (safety checks on, debug
/// information stripped), or from the option `zcsls-dir` as `stage-zcsls`
/// lays them out; none with `-Dplatforms=false`.
/// Returns its unit tests.
fn addPackageVscode(b: *std.Build, release: []const *std.Build.Step.Compile) *std.Build.Step.Compile {
    const with_platforms = b.option(bool, "platforms", "package-vscode: the platform VSIX files with zcsls too (default: true)") orelse true;
    const staged = b.option([]const u8, "zcsls-dir", "package-vscode: take each platform's zcsls from DIR/TARGET/, as stage-zcsls installs them, instead of building it");
    const mod = b.createModule(.{
        .root_source_file = b.path("build/package_vscode.zig"),
        .target = b.graph.host,
    });
    const run = b.addRunArtifact(b.addExecutable(.{ .name = "package_vscode", .root_module = mod }));
    run.setCwd(b.path(""));
    run.addArg(zon.version);
    if (with_platforms) {
        for (platforms, release) |p, exe| {
            if (staged) |dir| {
                const name = if (std.mem.endsWith(u8, p[1], "-windows")) "zcsls.exe" else "zcsls";
                run.addArg(b.fmt("{s}={s}/{s}/{s}", .{ p[0], dir, p[1], name }));
            } else {
                run.addPrefixedFileArg(b.fmt("{s}=", .{p[0]}), exe.getEmittedBin());
            }
        }
    }
    run.addPassthruArgs();
    // writes outside the cache
    run.has_side_effects = true;
    b.step("package-vscode", "Package the VS Code extension into DIST (-- DIST)").dependOn(&run.step);
    return b.addTest(.{ .root_module = mod });
}

/// `zig build generated` writes the files generated from others (the
/// extension's package.nls.json and l10n bundle: build/generated.zig), and
/// `zig build check-generated` fails when one is out of date. Returns the
/// generator's unit tests.
fn addGenerated(b: *std.Build) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .root_source_file = b.path("build/generated.zig"),
        .target = b.graph.host,
    });
    const exe = b.addExecutable(.{ .name = "generated", .root_module = mod });
    const steps = .{
        .{ "generated", "Write the files generated from others (the extension's strings)", false },
        .{ "check-generated", "Fail when a file generated from others is out of date", true },
    };
    inline for (steps) |s| {
        const run = b.addRunArtifact(exe);
        run.setCwd(b.path(""));
        run.addArg(".");
        if (s[2]) run.addArg("--check");
        // reads and writes the repository
        run.has_side_effects = true;
        b.step(s[0], s[1]).dependOn(&run.step);
    }
    return b.addTest(.{ .root_module = mod });
}
