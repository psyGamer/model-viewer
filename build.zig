const builtin = @import("builtin");
const std = @import("std");
const mach_core = @import("mach_core");
const mach_gpu = @import("mach_gpu");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mach_core_dep = b.dependency("mach_core", .{});
    const model3d_dep = b.dependency("mach_model3d", .{});
    const ecs_dep = b.dependency("zig_ecs", .{});

    const model_viewer_mod = b.addModule("model-viewer", .{
        .root_source_file = .{ .path = "src/root.zig" },
        .imports = &.{
            .{ .name = "mach-core", .module = mach_core_dep.module("mach-core") },
            .{ .name = "model3d", .module = model3d_dep.module("mach-model3d") },
            .{ .name = "ecs", .module = ecs_dep.module("zig-ecs") },

            .{
                .name = "math",
                .module = b.addModule("math", .{ .root_source_file = .{ .path = "src/math.zig" } }),
            },

            .{
                .name = "engine",
                .module = b.addModule("engine", .{
                    .root_source_file = .{ .path = "src/Engine.zig" },
                    .imports = &.{
                        .{ .name = "mach-core", .module = mach_core_dep.module("mach-core") },
                        .{ .name = "ecs", .module = ecs_dep.module("zig-ecs") },
                    },
                }),
            },
        },
        .target = target,
        .optimize = optimize,
    });

    // Used to call into mach's native main function
    model_viewer_mod.addImport("mach-platform", b.createModule(.{
        .root_source_file = mach_core_dep.path(if (target.result.cpu.arch == .wasm32)
            "src/platform/wasm/main.zig"
        else
            "src/platform/native/main.zig"),
        .imports = &.{
            .{ .name = "mach-core", .module = mach_core_dep.module("mach-core") },
            .{ .name = "app", .module = model_viewer_mod },
        },
    }));

    // This ONLY exists to satisfy ZLS...
    // It could safely be removed.
    const lib = b.addStaticLibrary(.{
        .name = "model-viewer",
        .root_source_file = .{ .path = "src/Engine.zig" },
        .target = target,
        .optimize = optimize,
    });
    lib.root_module.addImport("model-viewer", model_viewer_mod);
}

// Taken from Mach-Core's build script
pub const App = struct {
    b: *std.Build,
    name: []const u8,
    compile: *std.Build.Step.Compile,
    install: *std.Build.Step.InstallArtifact,
    run: *std.Build.Step.Run,
    platform: Platform,
    res_dirs: ?[]const []const u8,
    watch_paths: ?[]const []const u8,

    pub const Platform = enum {
        native,
        web,

        pub fn fromTarget(target: std.Target) Platform {
            if (target.cpu.arch == .wasm32) return .web;
            return .native;
        }
    };

    pub fn init(
        app_builder: *std.Build,
        model_viewer_dep: *std.Build.Dependency,
        options: struct {
            name: []const u8,
            src: []const u8,
            target: std.Build.ResolvedTarget,
            optimize: std.builtin.OptimizeMode,
            custom_entrypoint: ?[]const u8 = null,
            deps: ?[]const std.Build.Module.Import = null,
            res_dirs: ?[]const []const u8 = null,
            watch_paths: ?[]const []const u8 = null,
        },
    ) !App {
        const target = options.target.result;
        const platform = Platform.fromTarget(target);

        var imports = std.ArrayList(std.Build.Module.Import).init(app_builder.allocator);

        const mach_core_dep = model_viewer_dep.builder.dependency("mach_core", .{});

        try imports.append(.{ .name = "model-viewer", .module = model_viewer_dep.module("model-viewer") });
        try imports.append(.{ .name = "mach-core", .module = mach_core_dep.module("mach-core") });
        try imports.append(.{ .name = "ecs", .module = model_viewer_dep.builder.dependency("zig_ecs", .{}).module("zig-ecs") });
        try imports.append(.{ .name = "math", .module = model_viewer_dep.module("math") });
        if (options.deps) |app_deps| try imports.appendSlice(app_deps);

        const app_module = app_builder.createModule(.{
            .root_source_file = .{ .path = options.src },
            .imports = try imports.toOwnedSlice(),
        });

        const engine_module = model_viewer_dep.module("engine");
        engine_module.addImport("app", app_module);
        engine_module.addImport("model-viewer", model_viewer_dep.module("model-viewer"));

        const compile = blk: {
            if (platform == .web) {
                // wasm libraries should go into zig-out/www/
                app_builder.lib_dir = app_builder.fmt("{s}/www", .{app_builder.install_path});

                const lib = app_builder.addStaticLibrary(.{
                    .name = options.name,
                    .root_source_file = if (options.custom_entrypoint != null) .{ .path = options.custom_entrypoint.? } else mach_core_dep.path("src/platform/wasm/main.zig"),
                    .target = options.target,
                    .optimize = options.optimize,
                });
                lib.rdynamic = true;

                break :blk lib;
            } else {
                const exe = app_builder.addExecutable(.{
                    .name = options.name,
                    .root_source_file = if (options.custom_entrypoint != null) .{ .path = options.custom_entrypoint.? } else mach_core_dep.path("src/platform/native/main.zig"),
                    .target = options.target,
                    .optimize = options.optimize,
                });
                // TODO(core): figure out why we need to disable LTO: https://github.com/hexops/mach/issues/597
                exe.want_lto = false;
                break :blk exe;
            }
        };

        compile.root_module.addImport("mach-core", mach_core_dep.module("mach-core"));
        compile.root_module.addImport("app", engine_module);

        // Installation step
        app_builder.installArtifact(compile);
        const install = app_builder.addInstallArtifact(compile, .{});
        if (options.res_dirs) |res_dirs| {
            for (res_dirs) |res| {
                const install_res = app_builder.addInstallDirectory(.{
                    .source_dir = .{ .path = res },
                    .install_dir = install.dest_dir.?,
                    .install_subdir = std.fs.path.basename(res),
                    .exclude_extensions = &.{},
                });
                install.step.dependOn(&install_res.step);
            }
        }
        if (platform == .web) {
            inline for (.{ mach_core_dep.path("src/platform/wasm/mach.js"), std.Build.LazyPath{ .path = @import("mach_sysjs").getJSPath() } }) |js| {
                const install_js = app_builder.addInstallFileWithDir(
                    js,
                    std.Build.InstallDir{ .custom = "www" },
                    std.fs.path.basename(switch (js) {
                        .path => |path| path,
                        .dependency => |dep| dep.sub_path,
                        else => unreachable,
                    }),
                );
                install.step.dependOn(&install_js.step);
            }
        }

        const content_dir = "assets";
        const install_content = app_builder.addInstallDirectory(.{
            .source_dir = model_viewer_dep.path("assets"),
            .install_dir = .bin,
            .install_subdir = app_builder.pathJoin(&.{ content_dir, "internal" }),
        });
        compile.step.dependOn(&install_content.step);

        // Link dependencies
        if (platform != .web) {
            link(mach_core_dep.builder, compile);
        }

        const run = app_builder.addRunArtifact(compile);
        run.step.dependOn(&install.step);
        return .{
            .b = app_builder,
            .compile = compile,
            .install = install,
            .run = run,
            .name = options.name,
            .platform = platform,
            .res_dirs = options.res_dirs,
            .watch_paths = options.watch_paths,
        };
    }
};

pub fn link(core_builder: *std.Build, step: *std.Build.Step.Compile) void {
    mach_gpu.link(core_builder.dependency("mach_gpu", .{
        .target = step.root_module.resolved_target orelse core_builder.host,
        .optimize = step.root_module.optimize.?,
    }).builder, step, .{}) catch unreachable;
}

comptime {
    const supported_zig = std.SemanticVersion.parse("0.12.0-dev.2063+804cee3b9") catch unreachable;
    if (builtin.zig_version.order(supported_zig) != .eq) {
        @compileError(std.fmt.comptimePrint("unsupported Zig version ({}). Required Zig version 2024.1.0-mach: https://machengine.org/about/nominated-zig/#202410-mach", .{builtin.zig_version}));
    }
}
