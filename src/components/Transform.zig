const m = @import("math");
const ecs = @import("ecs");

const World = @import("../modules/Engine.zig").World;

position: m.Vec3 = m.vec3_zero,
rotation: m.Vec3 = m.vec3_zero,
scale: m.Vec3 = m.vec3_one,

pub fn addToEntity(world: *World, entity: ecs.EntityID, transform: @This()) !void {
    try world.entities.setComponent(entity, .mesh_renderer, .transform, transform);
}
