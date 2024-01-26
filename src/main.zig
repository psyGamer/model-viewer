const std = @import("std");
const ecs = @import("ecs");
const core = @import("mach-core");

const Model = @import("model.zig");

pub const App = @This();

const World = @import("modules/Engine.zig").World;

gpa: std.heap.GeneralPurposeAllocator(.{}),
allocator: std.mem.Allocator,

model: ecs.EntityID,

world: World,

pub const std_options = struct {
    pub const log_level = .debug;
};

pub fn init(app: *App) !void {
    try core.init(.{});

    app.gpa = .{};
    app.allocator = app.gpa.allocator();
    app.world = try World.init(app.allocator);

    try app.world.send(null, .init, .{app.allocator});

    const mesh = try Model.load(app.allocator, "assets/test.obj");
    app.model = try app.world.entities.new();
    try app.world.entities.setComponent(app.model, .mesh_renderer, .transform, .{
        .position = .{ 0, 0, 0 },
        .rotation = .{ 0, 0, 0 },
        .scale = .{ 1, 1, 1 },
    });
    try app.world.entities.setComponent(app.model, .mesh_renderer, .mesh, mesh);
}

pub fn deinit(app: *App) void {
    const mesh = app.world.entities.getComponent(app.model, .mesh_renderer, .mesh).?;
    mesh.deinit(app.allocator);

    try app.world.send(null, .deinit, .{app.allocator});

    app.world.deinit();
    std.debug.assert(app.gpa.detectLeaks() == false);

    core.deinit();
}

pub fn update(app: *App) !bool {
    try app.world.send(null, .update, .{});
    return app.world.mod.engine.state.should_close; // Slightly ugly dependency on Engine, but ehh..
}
