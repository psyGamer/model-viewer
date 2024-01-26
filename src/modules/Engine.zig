const builtin = @import("builtin");
const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;
const m3d = @import("model3d");
const ecs = @import("ecs");

const m = @import("math");
const Model = @import("../model.zig");
const Camera = @import("../camera.zig");

const Engine = ecs.Module(@This());
const MeshRenderer = @import("MeshRenderer.zig");
pub const World = ecs.World(.{ Engine, MeshRenderer });

timer: core.Timer,
title_timer: core.Timer,

pub const name = .engine;
const log = std.log.scoped(name);

fn self(world: *World) *@This() {
    return getModule(@This(), name, world);
}
fn getModule(comptime Module: type, comptime module_name: @TypeOf(.EnumLiteral), world: *World) *Module {
    return @ptrCast(&@field(world.mod, @tagName(module_name)).state);
}

pub fn init(world: *World, allocator: std.mem.Allocator) !void {
    // Initialize various other parts
    try @import("../util/random.zig").init();

    _ = allocator; // autofix
    log.info("Initializing Engine...", .{});
    const engine = self(world);

    engine.* = .{
        .timer = try core.Timer.start(),
        .title_timer = try core.Timer.start(),
    };
}

pub fn deinit(world: *World, allocator: std.mem.Allocator) !void {
    _ = allocator; // autofix
    log.info("Deinitializing Engine...", .{});
    const engine = self(world);
    _ = engine; // autofix
}

pub fn handleEvent(_: *World, event: core.Event) !void {
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
}

pub fn update(world: *World, arena: std.mem.Allocator) !void {
    var engine = self(world);
    var mesh_renderer = getModule(MeshRenderer, MeshRenderer.name, world);

    // Camera movement
    const camera_move_speed: m.Vec3 = @splat((@as(f32, if (core.keyPressed(.left_shift)) 10 else 3)) * core.delta_time);
    if (core.keyPressed(.w)) mesh_renderer.camera.position += mesh_renderer.camera.front * camera_move_speed;
    if (core.keyPressed(.s)) mesh_renderer.camera.position -= mesh_renderer.camera.front * camera_move_speed;
    if (core.keyPressed(.d)) mesh_renderer.camera.position += mesh_renderer.camera.right * camera_move_speed;
    if (core.keyPressed(.a)) mesh_renderer.camera.position -= mesh_renderer.camera.right * camera_move_speed;
    if (core.keyPressed(.space)) mesh_renderer.camera.position += Camera.world_up * camera_move_speed;
    if (core.keyPressed(.left_control)) mesh_renderer.camera.position -= Camera.world_up * camera_move_speed;
    if (core.keyPressed(.left)) mesh_renderer.camera.pitch -= 5;
    if (core.keyPressed(.right)) mesh_renderer.camera.pitch += 5;

    if (core.mousePressed(.left)) {}

    mesh_renderer.camera.pitch = @mod(mesh_renderer.camera.pitch, 360);
    mesh_renderer.camera.yaw = @mod(mesh_renderer.camera.yaw, 360);

    mesh_renderer.camera.updateVectors();

    const queue = core.queue;
    _ = queue; // autofix

    try world.send(null, .draw, .{arena});

    core.swap_chain.present();

    // update the window title every second
    if (engine.title_timer.read() >= 1.0) {
        engine.title_timer.reset();
        try core.printTitle("Triangle [ {d}fps ] [ Input {d}hz ]", .{
            core.frameRate(),
            core.inputRate(),
        });
    }
}
