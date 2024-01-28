const std = @import("std");
const ecs = @import("ecs");
const core = @import("mach-core");

const Model = @import("model.zig");
const model_loader = @import("util/model_loader.zig");
const logging = @import("util/colored_logging.zig");

pub const App = @This();

const World = @import("modules/Engine.zig").World;

gpa: std.heap.GeneralPurposeAllocator(.{}),
allocator: std.mem.Allocator,
arena: std.heap.ArenaAllocator,

model: ecs.EntityID,
model2: ecs.EntityID,

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

    app.model = try app.world.entities.new();
    try app.world.entities.setComponent(app.model, .mesh_renderer, .transform, .{
        .position = .{ 0, 0, 0 },
        .rotation = .{ 0, 0, 0 },
        .scale = .{ 1, 1, 1 },
    });
    try model_loader.loadModel(&app.world, app.model, app.allocator, "assets/cube.m3d");

    app.model2 = try app.world.entities.new();
    try app.world.entities.setComponent(app.model2, .mesh_renderer, .transform, .{
        .position = .{ 0, 0, 0 },
        .rotation = .{ 0, 0, std.math.degreesToRadians(f32, 22.0) },
        .scale = .{ 0.2, 0.2, 0.2 },
    });
    try model_loader.loadModel(&app.world, app.model2, app.allocator, "assets/dragon.m3d");
}

pub fn deinit(app: *App) void {
    app.world.entities.getComponent(app.model, .mesh_renderer, .mesh).?.deinit(app.allocator);
    app.world.entities.getComponent(app.model2, .mesh_renderer, .mesh).?.deinit(app.allocator);

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

    var transform = app.world.entities.getComponent(app.model, .mesh_renderer, .transform).?;
    transform.rotation[1] += std.math.degreesToRadians(f32, 45.0) * core.delta_time;
    try app.world.entities.setComponent(app.model, .mesh_renderer, .transform, transform);

    transform = app.world.entities.getComponent(app.model2, .mesh_renderer, .transform).?;
    transform.rotation[0] += std.math.degreesToRadians(f32, -11.0) * core.delta_time;
    try app.world.entities.setComponent(app.model2, .mesh_renderer, .transform, transform);

    try app.world.send(null, .update, .{app.arena.allocator()});
    _ = app.arena.reset(.retain_capacity);

    return false;
}
