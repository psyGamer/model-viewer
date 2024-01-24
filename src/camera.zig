const std = @import("std");
const zm = @import("zmath");
const m = @import("math.zig");

const Camera = @This();

pub const world_up = m.vec3_pos_y;

fov: f32,

yaw: f32,
pitch: f32,
position: m.Vec3,

front: m.Vec3,
up: m.Vec3,
right: m.Vec3,

pub fn init(fov: f32, yaw: f32, pitch: f32, position: m.Vec3) Camera {
    var cam: Camera = .{
        .fov = fov,

        .yaw = yaw,
        .pitch = pitch,
        .position = position,

        .front = undefined,
        .up = undefined,
        .right = undefined,
    };
    cam.updateVectors();

    return cam;
}

pub fn getViewMatrix(cam: Camera) m.Mat4 {
    return m.createLookMatrix(cam.position, -cam.front, cam.up);
}

pub fn updateVectors(cam: *Camera) void {
    const yaw = std.math.degreesToRadians(f32, cam.yaw);
    const pitch = std.math.degreesToRadians(f32, cam.pitch);

    const front = m.vec3(
        std.math.cos(yaw) * std.math.cos(pitch),
        std.math.sin(pitch),
        -std.math.sin(yaw) * std.math.cos(pitch),
    );

    cam.front = m.normalize(front);
    cam.right = m.normalize(m.cross(cam.front, world_up));
    cam.up = m.normalize(m.cross(cam.right, cam.front));
}
