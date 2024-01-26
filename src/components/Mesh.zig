const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;
const m = @import("math");

const rng = @import("../util/random.zig");

const Mesh = @This();

pub const Vertex = struct {
    position: m.Vec3,
    normal: m.Vec3,
};

pub const Usage = enum { static, dynamic };

/// Unique ID for this Mesh
id: u32,

vertices: []Vertex,
indices: []u32,

/// Wheather the vertices/indices of the mesh are static or dynamic.
/// Using a dynamic mesh has a bigger performance impact and should be avoided if possible.
/// When the mesh only rarely changed, use static and manually invalidate the mesh with:
///
/// `try world.send(.mesh_renderer, .invalidateMesh, .{entity_id})`
// TODO: Actually implement this
usage: Usage = .static,

pub fn init(vertices: []Vertex, indices: []u32) Mesh {
    return .{
        .id = rng.randomInt(u32),
        .vertices = vertices,
        .indices = indices,
        .usage = .static,
    };
}
pub fn deinit(mesh: Mesh, allocator: std.mem.Allocator) void {
    allocator.free(mesh.vertices);
    allocator.free(mesh.indices);
}

/// Custom hash/eql functions using the unique ID
pub const HashmapContext = struct {
    pub fn hash(_: @This(), key: Mesh) u64 {
        var hasher = std.hash.Wyhash.init(0);
        std.hash.autoHash(&hasher, key.id);
        return hasher.final();
    }

    pub fn eql(_: @This(), a: Mesh, b: Mesh) bool {
        return a.id == b.id;
    }
};
