//! The build steps of the extension, in Zig as zfls has them (#3):
//! `zig build package-vscode -- DIST` packages the VSIX (build/package_vscode.zig),
//! `zig build generated` and `zig build check-generated` write and check the
//! files generated from others (build/generated.zig), and `zig build test`
//! runs the tools' unit tests.

const std = @import("std");
const zon = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const test_step = b.step("test", "Run the unit tests of the build tools");
    test_step.dependOn(&b.addRunArtifact(addPackageVscode(b)).step);
    test_step.dependOn(&b.addRunArtifact(addGenerated(b)).step);
}

/// `zig build package-vscode -- DIST`: build/package_vscode.zig, run at the
/// root of the repository with build.zig.zon's version as its first
/// argument. Returns its unit tests.
fn addPackageVscode(b: *std.Build) *std.Build.Step.Compile {
    const mod = b.createModule(.{
        .root_source_file = b.path("build/package_vscode.zig"),
        .target = b.graph.host,
    });
    const run = b.addRunArtifact(b.addExecutable(.{ .name = "package_vscode", .root_module = mod }));
    run.setCwd(b.path(""));
    run.addArg(zon.version);
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
