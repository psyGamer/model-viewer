const std = @import("std");
const ecs = @import("ecs");

const Module = ecs.Module(@This());

pub const name = .mesh_renderer;
const log = std.log.scoped(name);

pub fn draw(world: *ecs.World, renderer: *Module) !void {
    _ = world; // autofix
    _ = renderer; // autofix
    log.info("Drawing Meshes...", .{});
}
