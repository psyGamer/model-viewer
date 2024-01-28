const std = @import("std");
const ecs = @import("ecs");
const core = @import("mach-core");

const model_viewer = @import("model-viewer");
const Engine = model_viewer.Engine;

pub const App = struct {
    cubes: [4]ecs.Entity,
    plane: ecs.Entity,

    title_timer: core.Timer,

    pub fn init(engine: *Engine) !App {
        var app: App = undefined;

        for (&app.cubes) |*cube| {
            cube.* = engine.reg.create();
            try model_viewer.model_loader.loadModel(&engine.reg, cube.*, engine.allocator, "assets/cube.m3d");
        }
        engine.reg.add(app.cubes[0], model_viewer.Transform{
            .position = .{ 0, 0, 0 },
        });
        engine.reg.add(app.cubes[1], model_viewer.Transform{
            .position = .{ 2, 4, 3 },
            .scale = .{ 3, 2, 1 },
        });
        engine.reg.add(app.cubes[2], model_viewer.Transform{
            .position = .{ 6, 9, 4.20 },
            .rotation = .{ 30, 20, 10 },
        });
        engine.reg.add(app.cubes[3], model_viewer.Transform{
            .position = .{ 2, 2, 2 },
            .scale = .{ 3, 2, 1 },
            .rotation = .{ 30, 20, 10 },
        });

        app.plane = engine.reg.create();
        engine.reg.add(app.plane, model_viewer.Transform{
            .position = .{ 0, 0, 0 },
            .scale = .{ 3, 3, 3 },
        });
        try model_viewer.model_loader.loadModel(&engine.reg, app.plane, engine.allocator, "assets/plane.m3d");

        app.title_timer = try core.Timer.start();

        return app;
    }
    pub fn deinit(app: App, engine: *Engine) void {
        for (app.cubes) |cube| {
            engine.reg.getConst(model_viewer.Mesh, cube).deinit(engine.allocator);
        }
        engine.reg.getConst(model_viewer.Mesh, app.plane).deinit(engine.allocator);
    }

    pub fn update(app: *App, _: *Engine) !void {
        if (app.title_timer.read() >= 1.0) {
            app.title_timer.reset();
            try core.printTitle("Testbed [ {d}fps ] [ Input {d}hz ]", .{
                core.frameRate(),
                core.inputRate(),
            });
        }
    }

    pub fn draw(_: *App, _: *Engine) !void {}
};
