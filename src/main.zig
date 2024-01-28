const std = @import("std");
const ecs = @import("ecs");
const core = @import("mach-core");

const Model = @import("model.zig");
const model_loader = @import("util/model_loader.zig");
const logging = @import("util/colored_logging.zig");

pub const App = @This();

const World = @import("modules/Engine.zig").World;
const Transform = @import("components/Transform.zig");

gpa: std.heap.GeneralPurposeAllocator(.{}),
allocator: std.mem.Allocator,
arena: std.heap.ArenaAllocator,

cubes: [3]ecs.EntityID,
plane: ecs.EntityID,

world: World,

pub const std_options = struct {
    pub const log_level = .debug;
    pub const logFn = logging.colorizedLogging;
};

pub fn init(app: *App) !void {
    try core.init(.{});

    app.gpa = .{};
    app.allocator = app.gpa.allocator();
    app.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    app.world = try World.init(app.allocator);

    try app.world.send(null, .init, .{app.allocator});

    for (&app.cubes) |*cube| {
        cube.* = try app.world.entities.new();
        try model_loader.loadModel(&app.world, cube.*, app.allocator, "assets/cube.m3d");
    }
    try Transform.addToEntity(&app.world, app.cubes[0], .{
        .position = .{ 0, 0, 0 },
    });
    try Transform.addToEntity(&app.world, app.cubes[1], .{
        .position = .{ 2, 4, 3 },
        .scale = .{ 3, 2, 1 },
    });
    try Transform.addToEntity(&app.world, app.cubes[2], .{
        .position = .{ 6, 9, 4.20 },
        .rotation = .{ 30, 20, 10 },
    });
    try Transform.addToEntity(&app.world, app.cubes[3], .{
        .position = .{ 2, 2, 2 },
        .scale = .{ 3, 2, 1 },
        .rotation = .{ 30, 20, 10 },
    });

    app.plane = try app.world.entities.new();
    try Transform.addToEntity(&app.world, app.plane, .{
        .scale = .{ 3, 3, 3 },
    });
    try model_loader.loadModel(&app.world, app.plane, app.allocator, "assets/plane.m3d");
}

pub fn deinit(app: *App) void {
    for (app.cubes) |cube| {
        app.world.entities.getComponent(cube, .mesh_renderer, .mesh).?.deinit(app.allocator);
    }
    app.world.entities.getComponent(app.plane, .mesh_renderer, .mesh).?.deinit(app.allocator);

    try app.world.send(null, .deinit, .{app.allocator});

    app.world.deinit();
    std.debug.assert(app.gpa.detectLeaks() == false);

    core.deinit();
}

pub fn update(app: *App) !bool {
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        if (event == .close) return true;

        try app.world.send(null, .handleEvent, .{event});
    }

    try app.world.send(null, .update, .{app.arena.allocator()});
    _ = app.arena.reset(.retain_capacity);

    return false;
}
