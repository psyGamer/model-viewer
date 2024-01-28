// This file will be used as the root namespace for dendendants
// The original root is available under "app"

const builtin = @import("builtin");
const std = @import("std");
const ecs = @import("ecs");
const core = @import("mach-core");
const model_viewer = @import("model-viewer");

pub const App = @This();
const UserApp = @import("app").App;

const Engine = @This();
const MeshRenderer = model_viewer.MeshRenderer;

app: UserApp,

/// Can be used for general-purpose allocations.
allocator: std.mem.Allocator,
/// Can be used for temporary allocations.
/// Memory allocated with this will only be valid for the current frame.
arena_allocator: std.mem.Allocator,

/// Backing struct for the `arena_allocator`
arena: std.heap.ArenaAllocator,

/// The Entity-Component-System. All entities/components are managed through this.
reg: ecs.Registry,

mesh_renderer: MeshRenderer,

// TODO: Support the child application to also specify std_options
pub const std_options = struct {
    pub const log_level = if (builtin.mode == .Debug) .debug else .info;
    pub const logFn = model_viewer.colored_logging.colorizedLogging;
};

pub fn init(engine: *Engine) !void {
    try core.init(.{});

    engine.allocator = core.allocator;

    engine.arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    engine.arena_allocator = engine.arena.allocator();

    // Initialize all components
    try model_viewer.random.init();
    engine.reg = ecs.Registry.init(engine.allocator);

    engine.mesh_renderer = try MeshRenderer.init(engine.allocator);

    engine.app = try UserApp.init(engine);
}

pub fn deinit(engine: *Engine) void {
    if (std.meta.hasFn(UserApp, "deinit")) {
        engine.app.deinit(engine);
    }

    engine.mesh_renderer.deinit();

    engine.reg.deinit();
    engine.arena.deinit();

    core.deinit();
}

pub fn update(engine: *Engine) !bool {
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        if (event == .close) return true;

        switch (event) {
            .key_press => |ev| {
                switch (ev.key) {
                    .one => core.setVSync(.none),
                    .two => core.setVSync(.double),
                    .three => core.setVSync(.triple),
                    else => {},
                }
            },
            else => {},
        }

        // Forward events to all components
        engine.mesh_renderer.handleEvent(event);
    }

    // Update all components
    try engine.mesh_renderer.update(engine);
    if (std.meta.hasFn(UserApp, "update")) {
        try engine.app.update(engine);
    }

    // Draw all components
    try engine.mesh_renderer.draw(engine);
    if (std.meta.hasFn(UserApp, "draw")) {
        try engine.app.draw(engine);
    }

    core.swap_chain.present();

    return false;
}
