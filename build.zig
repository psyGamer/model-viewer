const std = @import("std");
const mach_core = @import("mach_core");

const content_dir = "assets";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mach_core_dep = b.dependency("mach_core", .{
        .target = target,
        .optimize = optimize,
    });

    const zmath_dep = b.anonymousDependency("deps/zmath", @import("deps/zmath/build.zig"), .{});
    const model3d_dep = b.dependency("mach_model3d", .{});

    const app = try mach_core.App.init(b, mach_core_dep.builder, .{
        .name = "model-viewer",
        .src = "src/main.zig",
        .target = target,
        .optimize = optimize,
        .deps = &[_]std.Build.Module.Import{
            .{ .name = "zmath", .module = zmath_dep.module("zmath") },
            .{ .name = "model3d", .module = model3d_dep.module("mach-model3d") },
        },
    });
    app.compile.linkLibC();
    if (b.args) |args| app.run.addArgs(args);

    const install_content = b.addInstallDirectory(.{
        .source_dir = .{ .path = content_dir },
        .install_dir = .bin,
        .install_subdir = content_dir,
    });
    app.compile.step.dependOn(&install_content.step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&app.run.step);
}
