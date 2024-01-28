const std = @import("std");
const ecs = @import("ecs");
const core = @import("mach-core");

pub const App = @This();

const Engine = @import("modules/Engine.zig");
const MeshRenderer = @import("modules/MeshRenderer.zig");
const TestApp = @import("test_app.zig");

gpa: std.heap.GeneralPurposeAllocator(.{}),
allocator: std.mem.Allocator,
arena: std.heap.ArenaAllocator,

reg: ecs.Registry,

engine: Engine,
mesh_renderer: MeshRenderer,
test_app: TestApp,

pub fn init(app: *App) !void {
    try core.init(.{});

    app.gpa = .{};
    app.allocator = app.gpa.allocator();
    app.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);

    // Initialize all components
    try @import("util/random.zig").init();
    app.reg = ecs.Registry.init(app.allocator);

    app.engine = try Engine.init(app.allocator);
    app.mesh_renderer = try MeshRenderer.init(app.allocator);
    app.test_app = try TestApp.init(&app.reg, app.allocator);
}

pub fn deinit(app: *App) void {
    // Deinitialize all components
    app.test_app.deinit(&app.reg, app.allocator);
    app.mesh_renderer.deinit(app.allocator);
    app.engine.deinit(app.allocator);

    app.reg.deinit();
    std.debug.assert(app.gpa.detectLeaks() == false);

    core.deinit();
}

pub fn update(app: *App) !bool {
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        if (event == .close) return true;

        // Forward events to all components
        try app.engine.handleEvent(event);
        try app.mesh_renderer.handleEvent(event);
    }

    // Update all components
    try app.engine.update(&app.reg, app.arena.allocator());
    try app.mesh_renderer.update(&app.reg, app.arena.allocator());
    try app.test_app.update(&app.reg, app.arena.allocator());

    // Draw all components
    try app.mesh_renderer.draw(&app.reg, app.arena.allocator());
    try app.test_app.draw(&app.reg, app.arena.allocator());

    core.swap_chain.present();

    _ = app.arena.reset(.retain_capacity);
    return false;
}
