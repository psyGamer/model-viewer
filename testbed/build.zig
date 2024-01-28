const std = @import("std");
const model_viewer = @import("model_viewer");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const model_viewer_dep = b.dependency("model_viewer", .{});

    const app = try model_viewer.App.init(b, model_viewer_dep, .{
        .name = "testbed",
        .src = "src/main.zig",
        .target = target,
        .optimize = optimize,
        .deps = &.{},
    });
    if (b.args) |args| app.run.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&app.run.step);

    const content_dir = "assets";
    const install_content = b.addInstallDirectory(.{
        .source_dir = .{ .path = content_dir },
        .install_dir = .bin,
        .install_subdir = content_dir,
    });
    app.compile.step.dependOn(&install_content.step);
}
