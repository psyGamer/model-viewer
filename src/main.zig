const builtin = @import("builtin");
const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;
const m3d = @import("model3d");
const ecs = @import("ecs");

const m = @import("math");
const Model = @import("model.zig");
const Camera = @import("camera.zig");

pub const App = @This();
pub const World = ecs.World(.{Engine});

const Engine = @import("engine.zig");

gpa: std.heap.GeneralPurposeAllocator(.{}),
allocator: std.mem.Allocator,

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
}

pub fn deinit(app: *App) void {
    try app.world.send(null, .deinit, .{app.allocator});

    app.world.deinit();
    std.debug.assert(app.gpa.detectLeaks() == false);

    core.deinit();
}

pub fn update(app: *App) !bool {
    try app.world.send(null, .update, .{});
    return app.world.mod.engine.state.should_close; // Slightly ugly dependency on Engine, but ehh..
}
