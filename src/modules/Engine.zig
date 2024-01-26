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

prev_mouse_pos: core.Position,

should_close: bool = false,

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

        .prev_mouse_pos = .{ .x = 0, .y = 0 },
    };
}

pub fn deinit(world: *World, allocator: std.mem.Allocator) !void {
    _ = allocator; // autofix
    log.info("Deinitializing Engine...", .{});
    const engine = self(world);
    _ = engine; // autofix
}

pub fn update(world: *World) !void {
    var engine = self(world);
    var mesh_renderer = getModule(MeshRenderer, MeshRenderer.name, world);

    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                switch (ev.key) {
                    .one => core.setVSync(.none),
                    .two => core.setVSync(.double),
                    .three => core.setVSync(.triple),
                    .f3 => mesh_renderer.wireframe_visible = !mesh_renderer.wireframe_visible,

                    else => {},
                }
            },
            .mouse_press => |ev| {
                if (ev.button == .left) {
                    core.setCursorMode(.disabled);
                }
            },
            .mouse_release => |ev| {
                if (ev.button == .left) {
                    core.setCursorMode(.normal);
                }
            },
            .mouse_motion => |ev| {
                if (core.mousePressed(.left)) {
                    const delta: core.Position = .{
                        .x = ev.pos.x - engine.prev_mouse_pos.x,
                        .y = ev.pos.y - engine.prev_mouse_pos.y,
                    };
                    const camera_rotate_speed: f32 = 0.25;
                    mesh_renderer.camera.yaw -= @as(f32, @floatCast(delta.x)) * camera_rotate_speed;
                    mesh_renderer.camera.pitch -= @as(f32, @floatCast(delta.y)) * camera_rotate_speed;
                }
                engine.prev_mouse_pos = ev.pos;
            },
            .framebuffer_resize => |size| {
                // TODO: Move this into MeshRenderer
                mesh_renderer.depth_texture.release();
                mesh_renderer.depth_texture = core.device.createTexture(&gpu.Texture.Descriptor.init(.{
                    .size = .{
                        .width = size.width,
                        .height = size.height,
                    },
                    .format = .depth24_plus,
                    .usage = .{
                        .render_attachment = true,
                        .texture_binding = true,
                    },
                }));

                mesh_renderer.depth_texture_view.release();
                mesh_renderer.depth_texture_view = mesh_renderer.depth_texture.createView(&.{
                    .format = .depth24_plus,
                    .dimension = .dimension_2d,
                    .array_layer_count = 1,
                    .mip_level_count = 1,
                });
            },
            .close => {
                engine.should_close = true;
                return;
            },
            else => {},
        }
    }

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
    const encoder = core.device.createCommandEncoder(null);

    try world.send(null, .draw, .{encoder});

    var command = encoder.finish(null);
    encoder.release();

    queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();

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
